import 'dart:convert';
import 'dart:developer' as developer;

import '../domain/lagos_gazetteer.dart';
import '../domain/local_command_router.dart';
import '../domain/trip_prep_knowledge.dart';
import '../domain/voice_gateway.dart';
import '../../navigation/domain/navigation_gateway.dart';
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
class DeepSeekVoiceAgent implements VoiceReasoner, ConversationAwareReasoner {
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
6. Navi is activated and stopped by tapping its character. Keep "followUp": true while the destination or purpose is unknown. Once both are captured, include the destination and a nonempty purposeSummary, give a final confirmation (with the checklist for an errand), ask no further question, and set "followUp": false. Casual trips still need a purposeSummary. Do not claim a trip is ready if either detail is missing.

${TripPrepKnowledge.llmPlaybookReference}
''';

  static const _transitSystemPrompt = '''
You are Navi, a calm, street-smart Lagos transit co-pilot riding shotgun with a user who ALREADY has an active trip in progress.
Respond ONLY with a valid JSON object matching this exact schema:
{
  "intent": "transit" | "destination" | "purpose" | "clarify" | "greeting" | "identity" | "gratitude" | "sleep" | "unsupported",
  "reply": "1 to 2 short, calm, spoken sentences (max 24 words, natural for voice TTS, no markdown)",
  "destination": null,
  "purposeSummary": null,
  "isCasual": false,
  "checklist": [],
  "followUp": true,
  "changeTrip": false,
  "endTrip": false
}

Active Transit Rules:
1. Stay Strictly Anchored to the Active Trip: Keep answers focused ONLY on the active destination, current location, distance/ETA, safety, route steps, travel mode, and saved checklist in the live trip context. Do NOT start planning a new trip or ask "What are we going there to sort out?" on normal transit questions.
2. Concise & Safety-First: Speak clearly and briefly (max 24 words). Prioritize telling the user where they currently are (from "currentArea"), how far/long is left, and simple reassurance to stay guided safely.
3. Never Fabricate Telemetry: Use ONLY the currentArea, remainingDistance, remainingEta, routeSteps, destination, and checklist provided in the live trip context. If "currentArea" or route numbers say unavailable, honestly say GPS/route details are still settling. A destination label is not a confirmed address: when destinationStatus is awaiting_address_confirmation, explain that the user must choose an exact address. Never claim it is confirmed or that route guidance has begun. Only the app can confirm a place. Remaining distance is an approximate route-shape estimate, never proof of arrival or the correct bus stop. When routeSteps is empty, do not invent junction or turn instructions. Planning time from a previous origin is not a live remaining ETA. When routeKind is road_corridor, the geometry is a driving-road preview, not a verified bus route; never present it as bus guidance, a bus ETA, a stop, or evidence that the bus is off route. An unavailable currentArea must not be replaced with an old place from conversation history.
4. Normal Mentions Never Switch Trips: Unless the user EXPLICITLY asks to cancel/change/switch destination, set "changeTrip": false, "destination": null, "followUp": true. Never treat landmarks or passing places they ask about as a new destination.
5. Explicit Trip Change ("changeTrip": true): ONLY when the user clearly says they want to change/switch/redirect their trip to a different place:
   - Set "changeTrip": true, "intent": "destination", "destination": "<new canonical Lagos place>".
   - If the new purpose is NOT stated yet, set "purposeSummary": null, "checklist": [], "followUp": true, and ask what they are going to the new place to sort out.
   - If they ALSO gave the purpose in the same request, set "purposeSummary", populate "checklist" (for errands) or "isCasual": true, confirm the switch + essentials, and set "followUp": false.
6. Ending the Trip ("endTrip": true): ONLY when the user explicitly asks to end/cancel/finish the trip via voice, set "endTrip": true, "intent": "sleep", "followUp": false, and confirm the trip is ended.
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
  String? _destinationContext;
  JourneyTransitContext _transitContext = const JourneyTransitContext();
  bool _pendingTripSwitch = false;
  int _requestRevision = 0;

  bool get _useTransitPrompt => _transitContext.isActive && !_pendingTripSwitch;

  @override
  void cancelPendingReply() => _requestRevision++;

  @override
  void setDestinationContext(String destination) {
    final target = destination.trim();
    if (target.isEmpty || target.length > 120) return;
    if (_activeDestination?.toLowerCase() != target.toLowerCase() ||
        (_lastTurnAt != null &&
            DateTime.now().difference(_lastTurnAt!) > _sessionMemoryTimeout)) {
      _history.clear();
      _lastTurnAt = null;
    }
    _activeDestination = target;
    _destinationContext = target;
  }

  @override
  void updateTransitContext(
    JourneyTransitContext context, {
    bool resetPendingSwitch = false,
  }) {
    final previousActive = _transitContext.isActive;
    final previousDest = _transitContext.destination?.trim().toLowerCase();
    final nextDest = context.destination?.trim().toLowerCase();
    _transitContext = context;
    if (resetPendingSwitch) {
      _pendingTripSwitch = false;
    } else if (!context.isActive && previousActive && !_pendingTripSwitch) {
      _pendingTripSwitch = false;
    } else if (_pendingTripSwitch &&
        context.isActive &&
        nextDest != null &&
        _activeDestination != null &&
        nextDest == _activeDestination!.toLowerCase() &&
        (context.purposeSummary?.trim().isNotEmpty ?? false)) {
      // The switched destination & purpose have landed on the active journey.
      _pendingTripSwitch = false;
    }
    if (context.isActive &&
        !_pendingTripSwitch &&
        (!previousActive || previousDest != nextDest)) {
      _history.clear();
      _lastTurnAt = null;
      if (context.destination != null &&
          context.destination!.trim().isNotEmpty) {
        _activeDestination = context.destination!.trim();
        _destinationContext = _activeDestination;
      }
    }
  }

  @override
  void clearTripContext() {
    _transitContext = const JourneyTransitContext();
    _pendingTripSwitch = false;
    clearHistory();
  }

  void clearHistory() {
    _history.clear();
    _activeDestination = null;
    _destinationContext = null;
    _lastTurnAt = null;
  }

  void _recordTurn(String userText, LocalReply reply, int revision) {
    if (_disposed || revision != _requestRevision) return;
    final now = DateTime.now();
    if (_lastTurnAt != null &&
        now.difference(_lastTurnAt!) > _sessionMemoryTimeout) {
      _history.clear();
      _activeDestination = null;
    }
    _lastTurnAt = now;
    if (reply.destination != null && reply.destination!.isNotEmpty) {
      _activeDestination = reply.destination;
      if (_destinationContext != null) _destinationContext = reply.destination;
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
    final revision = ++_requestRevision;
    // Preserve what ASR actually heard. Phonetic place suggestions are scoped
    // to extracted destination candidates in _extractFastDestination.
    final trimmedUtterance = utterance.trim();
    final cleaned = fallback.removeWakePhrase(
      trimmedUtterance,
      wakeDetected: wakeDetected,
    );
    final effectiveUtterance = cleaned.isEmpty ? trimmedUtterance : cleaned;
    final local = fallback.route(
      utterance,
      wakeDetected: wakeDetected,
    );

    final hasFastPurpose =
        !_useTransitPrompt &&
        (TripPrepKnowledge.matchPurpose(
              effectiveUtterance,
              currentDestination: _activeDestination,
            ) !=
            null);

    if ((_http is DartIoCloudHttpTransport || useLocalFastPath) &&
        !_useTransitPrompt &&
        !hasFastPurpose &&
        const {
          LocalIntent.greeting,
          LocalIntent.identity,
          LocalIntent.gratitude,
        }.contains(local.intent)) {
      _recordTurn(effectiveUtterance, local, revision);
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
      return const LocalReply(
        LocalIntent.clarify,
        'Tap me once whenever you want to stop talking.',
      );
    }

    // Active transit fast-path handles explicit mid-trip switch or end requests
    // deterministically while keeping normal route questions grounded in live
    // transit telemetry.
    if ((_http is DartIoCloudHttpTransport || useLocalFastPath) &&
        _useTransitPrompt) {
      if (_matchesExplicitEndTrip(effectiveUtterance)) {
        const reply = LocalReply(
          LocalIntent.sleep,
          'Trip ended. Let me know whenever you are ready for your next journey.',
          followUp: false,
          endTrip: true,
        );
        _recordTurn(effectiveUtterance, reply, revision);
        return reply;
      }
      final switchedPlace = _extractExplicitTripSwitch(effectiveUtterance);
      if (switchedPlace != null) {
        _history.clear();
        _activeDestination = switchedPlace;
        _destinationContext = switchedPlace;
        final fastPurpose = TripPrepKnowledge.matchPurpose(
          effectiveUtterance,
          currentDestination: switchedPlace,
        );
        final LocalReply reply;
        if (fastPurpose != null) {
          _pendingTripSwitch = false;
          reply = LocalReply(
            LocalIntent.destination,
            'Switching to $switchedPlace! ${fastPurpose.spokenReply}',
            destination: switchedPlace,
            purposeSummary: fastPurpose.purposeSummary,
            isCasual: fastPurpose.isCasual,
            checklist: fastPurpose.checklist,
            followUp: false,
            changeTrip: true,
          );
        } else {
          _pendingTripSwitch = true;
          final followUpPrompt = TripPrepKnowledge.destinationFollowUpQuestion(
            switchedPlace,
          );
          reply = LocalReply(
            LocalIntent.destination,
            'Switching your trip to $switchedPlace. $followUpPrompt',
            destination: switchedPlace,
            followUp: true,
            changeTrip: true,
          );
        }
        _recordTurn(effectiveUtterance, reply, revision);
        return reply;
      }
    }

    // Zero-latency local Nigerian intelligence fast-path for planning / mid-trip switch.
    if ((_http is DartIoCloudHttpTransport || useLocalFastPath) &&
        !_useTransitPrompt) {
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
        final isTripSwitch = _pendingTripSwitch;
        if (isTripSwitch) {
          _pendingTripSwitch = false;
        }
        final fastReply = LocalReply(
          fastPlace != null ? LocalIntent.destination : LocalIntent.purpose,
          fastPurpose.spokenReply,
          destination: targetDestination,
          purposeSummary: fastPurpose.purposeSummary,
          isCasual: fastPurpose.isCasual,
          checklist: fastPurpose.checklist,
          followUp: !fastPurpose.isCasual,
          changeTrip: isTripSwitch,
        );
        _recordTurn(effectiveUtterance, fastReply, revision);
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
          changeTrip: _pendingTripSwitch,
        );
        _recordTurn(effectiveUtterance, fastReply, revision);
        return fastReply;
      }
    }

    if (!isConfigured) return _connectionFallback(local);

    final clock = Stopwatch()..start();
    // The fallback chain shares one deadline, rather than stacking several
    // complete provider timeouts while the user waits for a single reply.
    Duration remaining() => requestTimeout - clock.elapsed;
    try {
      // 1. Primary: Groq low-latency LLM (qwen/qwen3.8-27b, ~570ms, free tier)
      // with automatic rate-limit failover to secondary Groq model (openai/gpt-oss-20b).
      if (_groqApiKey.isNotEmpty && !_disposed) {
        final primaryBudget = Duration(
          microseconds: (requestTimeout.inMicroseconds * .65).round(),
        );
        final primaryGroq = await _callGroqModel(
          groqModel,
          effectiveUtterance,
          timeout: primaryBudget,
        );
        if (revision != _requestRevision) return _connectionFallback(local);
        if (primaryGroq != null) {
          _recordTurn(effectiveUtterance, primaryGroq, revision);
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
            remaining() > const Duration(milliseconds: 150) &&
            !_disposed) {
          final secondaryGroq = await _callGroqModel(
            groqFallbackModel,
            effectiveUtterance,
            timeout: remaining(),
          );
          if (revision != _requestRevision) return _connectionFallback(local);
          if (secondaryGroq != null) {
            _recordTurn(effectiveUtterance, secondaryGroq, revision);
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
      if (canTryDeepSeek &&
          !_disposed &&
          remaining() > const Duration(milliseconds: 150)) {
        final response = await _http.postJson(
          uri: _endpoint,
          headers: {if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey'},
          body: {
            'model': model,
            'temperature': 0.35,
            'max_tokens': 240,
            'response_format': const {'type': 'json_object'},
            'messages': _buildMessages(effectiveUtterance),
          },
          timeout: remaining(),
        );
        if (response.isSuccess) {
          final parsed = _parseCompletion(response.body);
          if (parsed != null) {
            _recordTurn(effectiveUtterance, parsed, revision);
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

      return _connectionFallback(local);
    } catch (_) {
      return _connectionFallback(local);
    }
  }

  List<Map<String, String>> _buildMessages(String cleanedUtterance) => [
    {
      'role': 'system',
      'content': _useTransitPrompt ? _transitSystemPrompt : _systemPrompt,
    },
    if (_useTransitPrompt)
      _transitContextMessage
    else if (_destinationContext != null)
      _contextMessage,
    ..._history,
    {'role': 'user', 'content': cleanedUtterance},
  ];

  Map<String, String> get _contextMessage => {
    'role': 'system',
    'content':
        'Current user-selected destination: ${jsonEncode(_destinationContext)}. '
        'Use this destination for the current trip; ask for its purpose if it is unknown.',
  };

  Map<String, String> get _transitContextMessage {
    final c = _transitContext;
    final distMeters = c.remainingDistanceMeters;
    final remainingDistance = distMeters == null
        ? 'unavailable'
        : (distMeters < 1000
              ? '${distMeters.round()} m'
              : '${(distMeters / 1000).toStringAsFixed(1)} km');
    final durSeconds = c.remainingDurationSeconds;
    final remainingEta = durSeconds == null
        ? 'unavailable'
        : '${(durSeconds / 60).ceil().clamp(1, 300)} min';
    final summary = jsonEncode({
      'activeDestination':
          c.confirmedPlaceName ?? c.destination ?? _activeDestination,
      'confirmedAddress': c.confirmedAddress,
      'destinationStatus': c.confirmedPlaceName == null
          ? 'awaiting_address_confirmation'
          : 'confirmed',
      if (c.destinationSuggestions != null)
        'matchingAddresses': [
          for (final (index, place) in c.destinationSuggestions!.places.indexed)
            {'option': index + 1, 'name': place.name, 'address': place.address},
        ],
      'currentArea': c.currentArea ?? 'unavailable',
      'gpsSignal': c.gpsQualityLabel ?? 'unknown',
      'travelMode': c.travelModeLabel ?? 'By bus',
      'isOffRoute': c.isOffRoute,
      'isRoadCorridorFallback': c.isRoadFallback,
      'routeKind': c.routeKind?.wireName ?? 'unavailable',
      'busRouteVerified': c.routeKind == RouteKind.busTransit,
      'remainingDistance': remainingDistance,
      'remainingEta': remainingEta,
      'routeProgressStatus': c.routeProgressStatus?.name ?? 'unavailable',
      'remainingDistanceSource': c.remainingDistanceMeters == null
          ? 'unavailable'
          : 'approximate_route_geometry',
      'routeEstimatesStale': c.routeEstimatesStale,
      'routeRefreshing': c.routeRefreshing,
      'arrivalConfirmed': false,
      'routeSteps': c.nextGuidanceSteps,
      'tripPurpose': c.purposeSummary,
      'checklist': c.checklist,
      'checkedItems': c.checkedItems.toList(),
    });
    return {
      'role': 'system',
      'content': 'LIVE ACTIVE TRIP TELEMETRY: $summary',
    };
  }

  LocalReply _connectionFallback(LocalReply local) {
    if (_useTransitPrompt) {
      if (_transitContext.confirmedPlaceName == null) {
        return const LocalReply(
          LocalIntent.clarify,
          'I still need to confirm the exact destination address. Check the matching places on the map.',
        );
      }
      final dest =
          _transitContext.confirmedPlaceName ??
          _transitContext.destination ??
          'your destination';
      final area = _transitContext.currentArea;
      final hint = area != null
          ? 'You are around $area. Your destination is $dest. '
          : 'Your destination is $dest. ';
      return LocalReply(
        LocalIntent.clarify,
        '${hint}${_transitContext.isRoadFallback ? 'Only a road preview is available. ' : ''}My voice connection dropped briefly, tap me to try again.',
        followUp: true,
      );
    }
    if (local.intent != LocalIntent.acknowledgment &&
        local.intent != LocalIntent.unsupported) {
      return local;
    }
    return const LocalReply(
      LocalIntent.clarify,
      "I heard you, but my conversation service isn't connecting. Please try again.",
    );
  }

  Future<LocalReply?> _callGroqModel(
    String targetModel,
    String cleanedUtterance, {
    required Duration timeout,
  }) async {
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
          // Voice turns need concise answers; default thinking can consume the
          // small JSON output budget before a usable reply is produced.
          if (targetModel == 'qwen/qwen3.8-27b') ...{
            'reasoning_effort': 'none',
            'reasoning_format': 'hidden',
          },
          'response_format': const {'type': 'json_object'},
          'messages': _buildMessages(cleanedUtterance),
        },
        timeout: timeout,
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
    final requestedChangeTrip = payload['changeTrip'] == true;
    final requestedEndTrip = payload['endTrip'] == true;
    final rawDestination = (payload['destination'] as String?)
        ?.replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    var validDestination =
        rawDestination != null &&
            rawDestination.length >= 2 &&
            rawDestination.length <= 120
        ? (LagosGazetteer.matchPlace(rawDestination) ?? rawDestination)
        : null;

    final rawPurposeSummary = (payload['purposeSummary'] as String?)
        ?.replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    var validPurposeSummary =
        rawPurposeSummary != null &&
            rawPurposeSummary.isNotEmpty &&
            rawPurposeSummary.length <= 80
        ? rawPurposeSummary
        : null;

    var isCasual = payload['isCasual'] == true;
    final rawChecklist = payload['checklist'];
    var checklist = <String>[];
    if (!isCasual && rawChecklist is List) {
      for (final item in rawChecklist) {
        if (item is String && item.trim().isNotEmpty && checklist.length < 5) {
          checklist.add(item.trim());
        }
      }
    }

    if (requestedEndTrip && _useTransitPrompt) {
      return LocalReply(
        LocalIntent.sleep,
        replyText,
        followUp: false,
        endTrip: true,
      );
    }

    if (_pendingTripSwitch && validDestination == null) {
      validDestination = _activeDestination;
    }
    final isExplicitTripChange =
        _pendingTripSwitch ||
        (_useTransitPrompt && requestedChangeTrip && validDestination != null);

    // Guard active transit conversations so normal landmark/route Q&A can never
    // overwrite the ongoing destination, purpose, or checklist accidentally.
    if (_useTransitPrompt && !isExplicitTripChange) {
      validDestination = null;
      validPurposeSummary = null;
      isCasual = false;
      checklist = <String>[];
    }

    if (isExplicitTripChange) {
      final switchComplete =
          validPurposeSummary != null || isCasual || checklist.isNotEmpty;
      if (!_pendingTripSwitch) {
        _history.clear();
        _activeDestination = validDestination;
        _destinationContext = validDestination;
      }
      _pendingTripSwitch = !switchComplete;
    }

    if (!_useTransitPrompt &&
        checklist.isEmpty &&
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
        changeTrip: isExplicitTripChange,
      );
    }

    final intent = switch (rawIntent) {
      'transit' when !isExplicitTripChange => LocalIntent.clarify,
      'destination' when validDestination != null => LocalIntent.destination,
      'purpose' when !_useTransitPrompt || isExplicitTripChange =>
        LocalIntent.purpose,
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
                  : (_useTransitPrompt
                        ? LocalIntent.clarify
                        : LocalIntent.unsupported)),
    };

    final followUp = switch (intent) {
      LocalIntent.sleep => false,
      LocalIntent.destination =>
        payload['followUp'] is bool
            ? payload['followUp'] as bool
            : (isExplicitTripChange && validPurposeSummary == null),
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
      changeTrip: isExplicitTripChange,
    );
  }

  static final _purposeClausePattern = RegExp(
    r'\s+(?:to\s+(?:register|swap|replace|fix|repair|open|renew|capture|collect|pick\s+up|buy|visit|see|chill|hang|eat|attend|do|get|link|unbar|sort)|for\s+(?:my|a|an|sim|nin|bvn|visa|passport|interview|meeting|exam|clearance)|because\s+).*$',
    caseSensitive: false,
  );

  String _stripPurposeClause(String raw) => raw
      .replaceAll(RegExp(r'[.!?]+$'), '')
      .replaceFirst(_purposeClausePattern, '')
      .trim();

  bool _matchesExplicitEndTrip(String utterance) {
    final normalized = utterance
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .trim();
    return RegExp(
      r'^(?:please\s+)?(?:end|cancel|stop|finish|complete)(?:\s+(?:this|my|the|current))?\s+(?:trip|route|journey)$',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  String? _extractExplicitTripSwitch(String utterance) {
    final stripped = utterance.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (stripped.isEmpty) return null;
    final patterns = [
      RegExp(
        r'^(?:please\s+)?(?:actually\s+)?(?:i\s+want\s+to\s+|i\x27d\s+like\s+to\s+|let\x27s\s+|lets\s+)?(?:change|switch|redirect|update|move)\s+(?:my\s+|the\s+|this\s+)?(?:trip|route|destination|journey)(?:\s+from\s+.+?)?\s+to\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'^(?:actually|instead)[,\s]+(?:take\s+me\s+to|let\x27s\s+go\s+to|head\s+to|switch\s+to|go\s+to)\s+(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'^(?:take\s+me\s+to|go\s+to|head\s+to|switch\s+to|new\s+trip\s+to)\s+(.+?)\s+instead$',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(stripped);
      if (match == null) continue;
      final rawTarget = _stripPurposeClause(match.group(1)!)
          .replaceFirst(RegExp(r'\s+instead$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '')
          .trim();
      if (rawTarget.length < 2 || rawTarget.length > 80) return null;
      return LagosGazetteer.matchPlace(rawTarget) ?? rawTarget;
    }
    return null;
  }

  String? _extractFastDestination(String cleaned, LocalReply local) {
    final strippedClause = _stripPurposeClause(cleaned);
    if (local.intent == LocalIntent.destination && local.destination != null) {
      final candidate = _stripPurposeClause(local.destination!);
      final matched = LagosGazetteer.matchPlace(candidate);
      if (matched != null) return matched;
      if (_activeDestination != null &&
          TripPrepKnowledge.matchPurpose(cleaned) != null) {
        return null;
      }
      return candidate.trim();
    }
    if (_activeDestination != null &&
        TripPrepKnowledge.matchPurpose(cleaned) != null &&
        strippedClause == cleaned.replaceAll(RegExp(r'[.!?]+$'), '').trim()) {
      // Pure purpose answers (e.g. "To swap my SIM card") should keep the
      // already locked destination instead of re-parsing "to <verb...>" as a place.
      return LagosGazetteer.matchPlace(strippedClause);
    }
    return _matchFastLagosDestination(strippedClause);
  }

  String? _matchFastLagosDestination(String cleaned) {
    final stripped = cleaned.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (stripped.isEmpty) return null;
    final prefixMatch = RegExp(
      r'^(?:please\s+)?(?:i\s*am\s+|i\x27m\s+|we\s*are\s+|we\x27re\s+)?(?:(going\s+to|heading\s+to|off\s+to|driving\s+to|on\s+my\s+way\s+to|taking\s+a\s+trip\s+to)|to)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(stripped);
    if (prefixMatch != null) {
      final hasMovementVerb = prefixMatch.group(1) != null;
      final candidate = prefixMatch
          .group(2)!
          .replaceFirst(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '')
          .trim();
      final gazetteer = LagosGazetteer.matchPlace(candidate);
      if (gazetteer != null) return gazetteer;
      if (!hasMovementVerb &&
          TripPrepKnowledge.matchPurpose(stripped) != null) {
        return null;
      }
      if (!hasMovementVerb && _activeDestination != null) {
        return null;
      }
      return candidate.length >= 2 && candidate.length <= 80 ? candidate : null;
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
