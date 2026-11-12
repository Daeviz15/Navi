import 'dart:convert';
import 'dart:developer' as developer;

import '../domain/lagos_gazetteer.dart';
import '../domain/local_command_router.dart';
import '../domain/trip_prep_knowledge.dart';
import '../domain/voice_gateway.dart';
import 'cloud_http_client.dart';

/// Conversational travel & trip-preparation companion powered by Groq
/// (`qwen/qwen3.8-27b` primary, `openai/gpt-oss-20b` secondary failover) and
/// optional DeepSeek (`deepseek-chat`).
///
/// Combines a curated Nigerian errand playbook ([TripPrepKnowledge]) with
/// multi-turn LLM reasoning so Navi locks destinations, asks smart follow-up
/// questions about the user's purpose of travel, provides accurate checklists
/// for errands, keeps casual trips checklist-free, and humbly asks for
/// clarification when speech is unclear.
class DeepSeekVoiceAgent implements VoiceReasoner {
  DeepSeekVoiceAgent({
    String? apiKey,
    String? groqApiKey,
    Uri? endpoint,
    Uri? groqEndpoint,
    this.model = const String.fromEnvironment(
      'NAVI_DEEPSEEK_MODEL',
      defaultValue: 'deepseek-chat',
    ),
    this.groqModel = const String.fromEnvironment(
      'NAVI_GROQ_LLM_MODEL',
      defaultValue: 'qwen/qwen3.8-27b',
    ),
    this.groqFallbackModel = const String.fromEnvironment(
      'NAVI_GROQ_FALLBACK_LLM_MODEL',
      defaultValue: 'openai/gpt-oss-20b',
    ),
    CloudHttpTransport? http,
    this.useLocalFastPath = false,
    this.fallback = const LocalCommandRouter(),
    this.requestTimeout = const Duration(seconds: 7),
  }) : _apiKey = (apiKey ?? const String.fromEnvironment('DEEPSEEK_API_KEY'))
           .trim(),
       _groqApiKey =
           (groqApiKey ?? const String.fromEnvironment('GROQ_API_KEY')).trim(),
       _endpoint =
           endpoint ??
           Uri.parse(
             const String.fromEnvironment(
               'NAVI_LLM_URL',
               defaultValue: 'https://api.deepseek.com/chat/completions',
             ),
           ),
       _groqEndpoint =
           groqEndpoint ??
           Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
       _http = http ?? DartIoCloudHttpTransport(),
       _ownsHttp = http == null;

  static const _diagnostics = bool.fromEnvironment('NAVI_VOICE_DIAGNOSTICS');

  static const _maxHistoryMessages = 8;
  static const _sessionMemoryTimeout = Duration(minutes: 3);

  static const _systemPrompt =
      '''
You are Navi, a warm, witty, street-smart personal travel and preparation companion in Lagos, Nigeria.
Respond ONLY with a valid JSON object matching this exact schema:
{
  "intent": "destination" | "purpose" | "clarify" | "greeting" | "identity" | "gratitude" | "sleep" | "unsupported",
  "reply": "1 to 2 short, lively spoken sentences (max 24 words, natural for voice TTS, no markdown)",
  "destination": "Canonical Lagos place, office, or landmark if mentioned/implied, otherwise null",
  "purposeSummary": "Short 2-4 word summary of trip purpose (e.g. 'MTN SIM Registration', 'Job Interview', 'Visiting a Friend'), or null",
  "isCasual": true | false,
  "checklist": ["Essential item 1", "Essential item 2"],
  "followUp": true | false
}

Companion Rules:
1. Friendly, Witty & Smart: Talk like a sharp, caring Lagos friend riding shotgun.
2. Humble Clarification ("intent": "clarify"): If the user's transcript is garbled, cut off, or unclear, DO NOT guess blindly. Humbly ask them to repeat or confirm (e.g. "Ah, my ears missed that last bit — did you mean the MTN office in Ikeja, or somewhere else?") and set "followUp": true.
3. Smart Indirect Place Recognition: If the user describes a place indirectly ("where they fix phones in Ikeja" -> "Computer Village", "uni in Akoka" -> "UNILAG", "state uni in Ojo" -> "LASU"), figure it out and set "destination".
4. Stage 1 — Destination Confirmed -> Ask "What For?":
   - When the user gives a destination without saying why they are going yet, lock "destination", set "checklist": [], set "followUp": true, and ask a smart follow-up question about what they are going there to do (e.g. for MTN Office: "MTN Office in Ikeja is locked in! What are we going there to sort out — SIM registration, SIM swap, or something else?").
5. Stage 2 — Purpose & Preparation Checklist vs Casual Trips:
   - For errands, banks, telecoms, government offices, embassies, hospitals, interviews, exams, markets, or flights: set "isCasual": false, set "purposeSummary", populate "checklist" with 3-4 specific items they must not forget at home, and mention the top items in "reply".
   - For casual movements (visiting friends/family, hanging out, eating out, beach, cinema, gym, worship, or "just going"): NEVER enforce a checklist! Set "isCasual": true and "checklist": [], and give a warm, witty companion remark.
6. Set "followUp": false ONLY when the user says they are done ("let's go", "that's all", "we are good", "bye") or when the trip is completely wrapped up with no question asked.

${TripPrepKnowledge.llmPlaybookReference}
''';

  String _apiKey;
  String _groqApiKey;
  final Uri _endpoint;
  final Uri _groqEndpoint;
  final String model;
  final String groqModel;
  final String groqFallbackModel;
  final CloudHttpTransport _http;
  final bool _ownsHttp;
  final bool useLocalFastPath;
  final LocalCommandRouter fallback;
  final Duration requestTimeout;
  final List<Map<String, String>> _history = <Map<String, String>>[];
  String? _activeDestination;
  DateTime? _lastTurnAt;
  bool _deepseekUnavailable = false;
  bool _disposed = false;

  void clearHistory() {
    _history.clear();
    _activeDestination = null;
    _lastTurnAt = null;
  }

  void _recordTurn(String userText, LocalReply reply) {
    final now = DateTime.now();
    if (_lastTurnAt != null &&
        now.difference(_lastTurnAt!) > _sessionMemoryTimeout) {
      _history.clear();
      _activeDestination = null;
    }
    _lastTurnAt = now;
    if (reply.destination != null && reply.destination!.isNotEmpty) {
      _activeDestination = reply.destination;
    }
    _history.add({'role': 'user', 'content': userText});
    _history.add({
      'role': 'assistant',
      'content': jsonEncode({
        'intent': reply.intent.name,
        'reply': reply.text,
        'destination': reply.destination ?? _activeDestination,
        'purposeSummary': reply.purposeSummary,
        'isCasual': reply.isCasual,
        'checklist': reply.checklist,
        'followUp': reply.followUp,
      }),
    });
    while (_history.length > _maxHistoryMessages) {
      _history.removeAt(0);
    }
  }

  bool get isConfigured =>
      _groqApiKey.isNotEmpty ||
      _apiKey.isNotEmpty ||
      _endpoint.host != 'api.deepseek.com';

  @override
  Future<LocalReply> resolve(
    String utterance, {
    required bool wakeDetected,
  }) async {
    final normalizedUtterance = LagosGazetteer.normalizeTranscript(utterance);
    final trimmedUtterance = normalizedUtterance.trim();
    final cleaned = fallback.removeWakePhrase(
      trimmedUtterance,
      wakeDetected: wakeDetected,
    );
    final effectiveUtterance = cleaned.isEmpty ? trimmedUtterance : cleaned;
    final local = fallback.route(
      normalizedUtterance,
      wakeDetected: wakeDetected,
    );

    final hasFastPurpose = (TripPrepKnowledge.matchPurpose(
      effectiveUtterance,
      currentDestination: _activeDestination,
    ) != null);

    if ((_http is DartIoCloudHttpTransport || useLocalFastPath) &&
        !hasFastPurpose &&
        const {
          LocalIntent.greeting,
          LocalIntent.identity,
          LocalIntent.gratitude,
          LocalIntent.acknowledgment,
        }.contains(local.intent)) {
      _recordTurn(effectiveUtterance, local);
      return local;
    }

    if ((_http is DartIoCloudHttpTransport || useLocalFastPath) &&
        _groqApiKey.isEmpty &&
        _apiKey.isEmpty) {
      _groqApiKey = await CloudEnvConfig.resolveKey(
        'GROQ_API_KEY',
        _groqApiKey,
      );
      _apiKey = await CloudEnvConfig.resolveKey('DEEPSEEK_API_KEY', _apiKey);
    }

    if (effectiveUtterance.isEmpty || _disposed) {
      return local;
    }

    final now = DateTime.now();
    if (_lastTurnAt != null &&
        now.difference(_lastTurnAt!) > _sessionMemoryTimeout) {
      clearHistory();
    }

    if (local.intent == LocalIntent.sleep ||
        RegExp(
          r'^(?:that\x27s all|thats all|no thanks|nothing else|we are good|i am good|i\x27m good|let\x27s go|lets go|ready to go)(?:\s+thanks|\s+navi)?[.!?]*$',
          caseSensitive: false,
        ).hasMatch(effectiveUtterance)) {
      clearHistory();
      return const LocalReply(
        LocalIntent.sleep,
        'Sweet! Ready to roll whenever you are.',
        followUp: false,
      );
    }

    // Zero-latency local Nigerian intelligence fast-path in production or when
    // explicitly enabled in tests.
    if (_http is DartIoCloudHttpTransport || useLocalFastPath) {
      final fastPlace = _extractFastDestination(effectiveUtterance, local);
      final fastPurpose = TripPrepKnowledge.matchPurpose(
        effectiveUtterance,
        currentDestination: fastPlace ?? _activeDestination,
      );

      // Case 1: User stated BOTH destination and purpose in one sentence, OR
      // user is answering the follow-up purpose question for an active destination.
      if (fastPurpose != null &&
          (fastPlace != null || _activeDestination != null)) {
        final targetDestination = fastPlace ?? _activeDestination;
        final fastReply = LocalReply(
          fastPlace != null ? LocalIntent.destination : LocalIntent.purpose,
          fastPurpose.spokenReply,
          destination: targetDestination,
          purposeSummary: fastPurpose.purposeSummary,
          isCasual: fastPurpose.isCasual,
          checklist: fastPurpose.checklist,
          followUp: !fastPurpose.isCasual,
        );
        _recordTurn(effectiveUtterance, fastReply);
        return fastReply;
      }

      // Case 2: User stated a destination without a purpose yet -> Lock it in
      // and ask a smart, tailored follow-up question ("What for?").
      if (fastPlace != null) {
        final followUpPrompt = TripPrepKnowledge.destinationFollowUpQuestion(
          fastPlace,
        );
        final fastReply = LocalReply(
          LocalIntent.destination,
          followUpPrompt,
          destination: fastPlace,
          followUp: true,
        );
        _recordTurn(effectiveUtterance, fastReply);
        return fastReply;
      }
    }

    if (!isConfigured) return local;

    final clock = Stopwatch()..start();
    try {
      // 1. Primary: Groq low-latency LLM (qwen/qwen3.8-27b, ~570ms, free tier)
      // with automatic rate-limit failover to secondary Groq model (openai/gpt-oss-20b).
      if (_groqApiKey.isNotEmpty && !_disposed) {
        final primaryGroq = await _callGroqModel(groqModel, effectiveUtterance);
        if (primaryGroq != null) {
          _recordTurn(effectiveUtterance, primaryGroq);
          if (_diagnostics) {
            developer.log(
              'agent=groq_primary model=$groqModel latencyMs=${clock.elapsedMilliseconds} intent=${primaryGroq.intent.name}',
              name: 'NAVI.voice',
            );
          }
          return primaryGroq;
        }

        if (groqFallbackModel.isNotEmpty &&
            groqFallbackModel != groqModel &&
            !_disposed) {
          final secondaryGroq = await _callGroqModel(
            groqFallbackModel,
            effectiveUtterance,
          );
          if (secondaryGroq != null) {
            _recordTurn(effectiveUtterance, secondaryGroq);
            if (_diagnostics) {
              developer.log(
                'agent=groq_secondary model=$groqFallbackModel latencyMs=${clock.elapsedMilliseconds} intent=${secondaryGroq.intent.name}',
                name: 'NAVI.voice',
              );
            }
            return secondaryGroq;
          }
        }
      }

      // 2. Optional Failover / Custom Endpoint: DeepSeek API (if configured and funded)
      final canTryDeepSeek =
          !_deepseekUnavailable &&
          (_apiKey.isNotEmpty || _endpoint.host != 'api.deepseek.com');
      if (canTryDeepSeek && !_disposed) {
        final response = await _http.postJson(
          uri: _endpoint,
          headers: {if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey'},
          body: {
            'model': model,
            'temperature': 0.35,
            'max_tokens': 240,
            'response_format': const {'type': 'json_object'},
            'messages': [
              const {'role': 'system', 'content': _systemPrompt},
              ..._history,
              {'role': 'user', 'content': effectiveUtterance},
            ],
          },
          timeout: requestTimeout,
        );
        if (response.isSuccess) {
          final parsed = _parseCompletion(response.body);
          if (parsed != null) {
            _recordTurn(effectiveUtterance, parsed);
            if (_diagnostics) {
              developer.log(
                'agent=deepseek latencyMs=${clock.elapsedMilliseconds} intent=${parsed.intent.name}',
                name: 'NAVI.voice',
              );
            }
            return parsed;
          }
        } else if (response.statusCode == 401 || response.statusCode == 402) {
          _deepseekUnavailable = true;
        }
      }

      return local;
    } catch (_) {
      return local;
    }
  }

  Future<LocalReply?> _callGroqModel(
    String targetModel,
    String cleanedUtterance,
  ) async {
    try {
      final isReasoningModel = targetModel.startsWith('openai/gpt-oss');
      final response = await _http.postJson(
        uri: _groqEndpoint,
        headers: {'Authorization': 'Bearer $_groqApiKey'},
        body: {
          'model': targetModel,
          'temperature': 0.35,
          'max_tokens': isReasoningModel ? 512 : 240,
          if (isReasoningModel) 'reasoning_effort': 'low',
          'response_format': const {'type': 'json_object'},
          'messages': [
            const {'role': 'system', 'content': _systemPrompt},
            ..._history,
            {'role': 'user', 'content': cleanedUtterance},
          ],
        },
        timeout: requestTimeout,
      );
      if (!response.isSuccess) return null;
      return _parseCompletion(response.body);
    } catch (_) {
      // One provider exception must not skip the configured fallback chain.
      return null;
    }
  }

  LocalReply? _parseCompletion(String rawBody) {
    final root = jsonDecode(rawBody);
    if (root is! Map) return null;
    final choices = root['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) return null;

    final payload = jsonDecode(content);
    if (payload is! Map) return null;

    final replyText = (payload['reply'] as String? ?? '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    if (replyText.isEmpty || replyText.length > 300) return null;

    final rawIntent = (payload['intent'] as String? ?? '').toLowerCase().trim();
    final rawDestination = (payload['destination'] as String?)
        ?.replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    final validDestination =
        rawDestination != null &&
            rawDestination.length >= 2 &&
            rawDestination.length <= 120
        ? (LagosGazetteer.matchPlace(rawDestination) ?? rawDestination)
        : null;

    final rawPurposeSummary = (payload['purposeSummary'] as String?)
        ?.replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    final validPurposeSummary =
        rawPurposeSummary != null &&
            rawPurposeSummary.isNotEmpty &&
            rawPurposeSummary.length <= 80
        ? rawPurposeSummary
        : null;

    final isCasual = payload['isCasual'] == true;
    final rawChecklist = payload['checklist'];
    final checklist = <String>[];
    if (!isCasual && rawChecklist is List) {
      for (final item in rawChecklist) {
        if (item is String && item.trim().isNotEmpty && checklist.length < 5) {
          checklist.add(item.trim());
        }
      }
    }

    if (checklist.isEmpty &&
        !isCasual &&
        RegExp(
          r'\b(?:checklist|list)\b.{0,35}\b(?:ready|pinned|prepared|sorted)\b|\b(?:pinned|prepared|ready)\b.{0,25}\b(?:checklist|list)\b',
          caseSensitive: false,
        ).hasMatch(replyText)) {
      return LocalReply(
        LocalIntent.clarify,
        'I’ve noted that. What specific errand are you going for so I can prepare a useful checklist?',
        destination: validDestination,
        followUp: true,
      );
    }

    final intent = switch (rawIntent) {
      'destination' when validDestination != null => LocalIntent.destination,
      'purpose' => LocalIntent.purpose,
      'clarify' => LocalIntent.clarify,
      'greeting' => LocalIntent.greeting,
      'identity' => LocalIntent.identity,
      'gratitude' => LocalIntent.gratitude,
      'sleep' => LocalIntent.sleep,
      _ =>
        validDestination != null
            ? LocalIntent.destination
            : (checklist.isNotEmpty || isCasual
                  ? LocalIntent.purpose
                  : LocalIntent.unsupported),
    };

    final followUp = switch (intent) {
      LocalIntent.sleep => false,
      LocalIntent.destination =>
        payload['followUp'] is bool ? payload['followUp'] as bool : false,
      _ => payload['followUp'] is bool ? payload['followUp'] as bool : true,
    };

    return LocalReply(
      intent,
      replyText,
      destination: validDestination,
      purposeSummary: validPurposeSummary,
      isCasual: isCasual,
      checklist: checklist,
      followUp: followUp,
    );
  }

  String? _extractFastDestination(String cleaned, LocalReply local) {
    final strippedClause = cleaned
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .replaceFirst(
          RegExp(
            r'\s+(?:to\s+(?:register|swap|replace|fix|repair|open|renew|capture|collect|pick\s+up|buy|visit|see|chill|hang|eat|attend|do|get|link|unbar|sort)|for\s+(?:my|a|an|sim|nin|bvn|visa|passport|interview|meeting|exam|clearance)|because\s+).*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    if (local.intent == LocalIntent.destination && local.destination != null) {
      final candidate = local.destination!.replaceFirst(
        RegExp(
          r'\s+(?:to\s+(?:register|swap|replace|fix|repair|open|renew|capture|collect|pick\s+up|buy|visit|see|chill|hang|eat|attend|do|get|link|unbar|sort)|for\s+(?:my|a|an|sim|nin|bvn|visa|passport|interview|meeting|exam|clearance)|because\s+).*$',
          caseSensitive: false,
        ),
        '',
      );
      return LagosGazetteer.matchPlace(candidate) ?? candidate.trim();
    }
    return _matchFastLagosDestination(strippedClause);
  }

  String? _matchFastLagosDestination(String cleaned) {
    final stripped = cleaned.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (stripped.isEmpty) return null;
    final prefixMatch = RegExp(
      r'^(?:please\s+)?(?:i\s*am\s+|i\x27m\s+|we\s*are\s+|we\x27re\s+)?(?:going\s+to|heading\s+to|off\s+to|driving\s+to|on\s+my\s+way\s+to|taking\s+a\s+trip\s+to|to)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(stripped);
    if (prefixMatch != null) {
      final candidate = prefixMatch
          .group(1)!
          .replaceFirst(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '')
          .trim();
      return LagosGazetteer.matchPlace(candidate) ??
          (candidate.length >= 2 && candidate.length <= 80 ? candidate : null);
    }
    // If the user simply spoke a 1-3 word Lagos place name (e.g. "Ikotun", "Shomolu")
    final words = stripped.split(RegExp(r'\s+'));
    if (words.length <= 3) {
      return LagosGazetteer.matchPlace(stripped);
    }
    return null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsHttp) _http.close();
  }
}
