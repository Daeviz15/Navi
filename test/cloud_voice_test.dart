import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/voice/application/voice_dependencies.dart';
import 'package:navi/features/voice/application/voice_session_controller.dart';
import 'package:navi/features/voice/data/android_voice_output.dart';
import 'package:navi/features/voice/data/cloud_http_client.dart';
import 'package:navi/features/voice/data/deepseek_voice_agent.dart';
import 'package:navi/features/voice/data/groq_speech_engine.dart';
import 'package:navi/features/voice/data/wav_encoder.dart';
import 'package:navi/features/voice/domain/lagos_gazetteer.dart';
import 'package:navi/features/voice/domain/local_command_router.dart';
import 'package:navi/features/voice/domain/voice_gateway.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

Uint8List _pcmChunk(int samples, int amplitude) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('a tapped map conversation uses the selected destination for purpose replies', () async {
    final http = _FakeCloudHttp();
    final agent = DeepSeekVoiceAgent(groqApiKey: 'test', http: http, useLocalFastPath: true);
    addTearDown(agent.dispose);
    agent.setDestinationContext('MTN office, Ikeja');
    final reply = await agent.resolve('I need to register a new SIM card', wakeDetected: false);
    expect(reply.destination, 'MTN office, Ikeja');
    expect(reply.purposeSummary, isNotEmpty);
    expect(reply.checklist, isNotEmpty);
    expect(http.jsonCalls, 0);
  });

  test('cancelled model replies cannot pollute a later tapped conversation', () async {
    final pending = Completer<CloudHttpResponse>();
    var calls = 0;
    final http = _FakeCloudHttp(jsonHandler: ({required uri, required headers, required body}) async {
      calls++;
      if (calls == 1) return pending.future;
      final messages = body['messages'] as List;
      expect(messages.where((message) => (message as Map)['role'] == 'assistant'), isEmpty);
      expect(messages.any((message) => (message as Map)['content'].toString().contains('Current user-selected destination: "Yaba"')), isTrue);
      return CloudHttpResponse(200, jsonEncode({'choices': [{'message': {'content': jsonEncode({
        'intent': 'clarify', 'reply': 'What brings you there?', 'followUp': true,
      })}}]}));
    });
    final agent = DeepSeekVoiceAgent(groqApiKey: 'test', http: http, useLocalFastPath: true);
    addTearDown(agent.dispose);
    final first = agent.resolve('Can we check my options?', wakeDetected: false);
    await Future<void>.delayed(Duration.zero);
    agent.cancelPendingReply();
    agent.setDestinationContext('Yaba');
    pending.complete(CloudHttpResponse(200, jsonEncode({'choices': [{'message': {'content': jsonEncode({
      'intent': 'destination', 'reply': 'Ikeja is ready.', 'destination': 'Ikeja', 'purposeSummary': 'Old interview',
    })}}]})));
    await first;
    await agent.resolve('What did we decide?', wakeDetected: false);
    expect(http.jsonCalls, 2);
  });

  test(
    'production shortcuts never replace natural follow-ups with a greeting',
    () async {
      final http = _FakeCloudHttp(
        jsonHandler: ({required uri, required headers, required body}) async {
          final messages = body['messages'] as List;
          expect(body['reasoning_effort'], 'none');
          expect(
            (messages.last as Map)['content'],
            'Can we avoid the busy roads this afternoon?',
          );
          return CloudHttpResponse(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'intent': 'clarify',
                      'reply':
                          'We can check route options once your destination is confirmed.',
                      'followUp': true,
                    }),
                  },
                },
              ],
            }),
          );
        },
      );
      final agent = DeepSeekVoiceAgent(
        groqApiKey: 'test',
        http: http,
        useLocalFastPath: true,
      );
      addTearDown(agent.dispose);
      final greeting = await agent.resolve('Hi Navi', wakeDetected: true);
      expect(greeting.intent, LocalIntent.greeting);
      expect(http.jsonCalls, 0);
      final reply = await agent.resolve(
        'Can we avoid the busy roads this afternoon?',
        wakeDetected: true,
      );
      expect(http.jsonCalls, 1);
      expect(reply.text, contains('route options'));
      expect(reply.intent, LocalIntent.clarify);
    },
  );

  test(
    'provider failures produce an honest connection reply, never a greeting',
    () async {
      final budgets = <Duration>[];
      final http = _BudgetHttp(budgets);
      final agent = DeepSeekVoiceAgent(
        groqApiKey: 'test',
        http: http,
        useLocalFastPath: true,
      );
      addTearDown(agent.dispose);
      final reply = await agent.resolve(
        'Would it be better to leave after lunch?',
        wakeDetected: true,
      );
      expect(reply.intent, LocalIntent.clarify);
      expect(reply.text, contains("isn't connecting"));
      expect(http.jsonCalls, 2);
      expect(budgets.first, lessThan(const Duration(seconds: 7)));
      expect(budgets.last, lessThanOrEqualTo(const Duration(seconds: 7)));
    },
  );

  test(
    'speech onset chunk and a short pause remain in one complete long turn',
    () async {
      Uint8List? uploaded;
      final pending = Completer<CloudHttpResponse>();
      final http = _FakeCloudHttp(
        multipartHandler:
            ({
              required uri,
              required headers,
              required fields,
              required fileBytes,
            }) {
              uploaded = fileBytes;
              return pending.future;
            },
      );
      final engine = GroqSpeechEngine(apiKey: 'test', http: http);
      addTearDown(engine.dispose);
      final events = <SpeechEvent>[];
      final sub = engine.events.listen(events.add);
      addTearDown(sub.cancel);
      await engine.initialize();
      engine.setMode(SpeechMode.listening);
      // All four voiced frames arrive together in the first packet.
      engine.addAudio(_pcmChunk(3200, 6000));
      for (var i = 0; i < 10; i++) {
        engine.addAudio(_pcmChunk(800, 0));
      }
      expect(http.multipartCalls, 0); // 500 ms pause is allowed.
      for (var i = 0; i < 180; i++) {
        engine.addAudio(_pcmChunk(800, 6000));
      }
      expect(http.multipartCalls, 0); // Never submit the old 8-second prefix.
      for (var i = 0; i < 15; i++) {
        engine.addAudio(_pcmChunk(800, 0));
      }
      await Future<void>.delayed(Duration.zero);
      expect(http.multipartCalls, 1);
      expect(
        uploaded!.length,
        44 + (3200 + 10 * 800 + 180 * 800 + 15 * 800) * 2,
      );
      expect(events.whereType<SpeechStarted>(), hasLength(1));
      expect(events.whereType<TranscriptionStarted>(), hasLength(1));
      pending.complete(
        const CloudHttpResponse(200, '{"text":"Take me to Lekki"}'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<UtteranceEnded>(), hasLength(1));
    },
  );

  test(
    'capture limit reports an error rather than recognizing a truncated command',
    () async {
      final http = _FakeCloudHttp();
      final engine = GroqSpeechEngine(
        apiKey: 'test',
        http: http,
        maxUtteranceBytes: 16000,
      );
      addTearDown(engine.dispose);
      final events = <SpeechEvent>[];
      final sub = engine.events.listen(events.add);
      addTearDown(sub.cancel);
      await engine.initialize();
      engine.setMode(SpeechMode.listening);
      for (var i = 0; i < 12; i++) {
        engine.addAudio(_pcmChunk(800, 6000));
      }
      await Future<void>.delayed(Duration.zero);
      expect(http.multipartCalls, 0);
      expect(
        events.whereType<SpeechFailed>().single.failure,
        VoiceFailure.utteranceTooLong,
      );
    },
  );


  test('encodePcm16MonoWav writes a valid 44-byte RIFF/WAVE header and aligns odd bytes', () {
    final pcm = Uint8List.fromList([0x10, 0x20, 0x30, 0x40, 0xFF]);
    final wav = encodePcm16MonoWav(pcm, sampleRate: 16000);
    expect(wav.length, 48); // 44-byte header + 4 aligned PCM bytes
    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
    expect(ascii.decode(wav.sublist(36, 40)), 'data');
    final header = ByteData.sublistView(wav, 0, 44);
    expect(header.getUint16(20, Endian.little), 1); // PCM
    expect(header.getUint16(22, Endian.little), 1); // Mono
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(28, Endian.little), 32000);
    expect(header.getUint32(40, Endian.little), 4);
    expect(wav.sublist(44), [0x10, 0x20, 0x30, 0x40]);
  });

  test('normalizeStreamingWav strips LIST chunks and fixes 0xFFFFFFFF streaming sizes', () {
    final base = encodePcm16MonoWav(
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      sampleRate: 24000,
    );
    // Simulate Groq Orpheus streaming WAV with 0xFFFFFFFF sizes + LIST chunk.
    final streaming = BytesBuilder()
      ..add(base.sublist(0, 4)) // "RIFF"
      ..add([0xFF, 0xFF, 0xFF, 0xFF]) // 0xFFFFFFFF size
      ..add(base.sublist(8, 36)) // "WAVE" + "fmt " chunk (24000 Hz)
      ..add(ascii.encode('LIST'))
      ..add([4, 0, 0, 0, 65, 66, 67, 68]) // 4-byte LIST payload
      ..add(ascii.encode('data'))
      ..add([0xFF, 0xFF, 0xFF, 0xFF]) // 0xFFFFFFFF data size
      ..add([1, 2, 3, 4, 5, 6, 7, 8]);

    final normalized = normalizeStreamingWav(streaming.toBytes());
    expect(normalized, isNotNull);
    expect(normalized!.length, 52); // 44-byte canonical header + 8 PCM bytes
    final header = ByteData.sublistView(normalized, 0, 44);
    expect(header.getUint32(4, Endian.little), 44); // 36 + 8
    expect(header.getUint32(24, Endian.little), 24000);
    expect(header.getUint32(40, Endian.little), 8);
    expect(normalized.sublist(44), [1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test('LagosGazetteer normalizes Nigerian place mishearings and fuzzy matches Ikotun and Shomolu', () {
    expect(
      LagosGazetteer.normalizeTranscript('take me to he caught on'),
      'take me to Ikotun',
    );
    expect(
      LagosGazetteer.normalizeTranscript('I am going to show more loo'),
      'I am going to Shomolu',
    );
    expect(LagosGazetteer.matchPlace('ekotun'), 'Ikotun');
    expect(LagosGazetteer.matchPlace('somolo'), 'Shomolu');
    expect(LagosGazetteer.matchPlace('ayana paja'), 'Iyana Ipaja');
    expect(LagosGazetteer.matchPlace('agbeda'), 'Egbeda');
    expect(LagosGazetteer.matchPlace('bagada'), 'Gbagada');
    expect(
      LagosGazetteer.normalizeTranscript(
        'Going to empty end office in ekeja to register my seem card with en eye en',
      ),
      'Going to MTN office in Ikeja to register my SIM card with NIN',
    );
    expect(
      LagosGazetteer.matchPlace('MTN office, Ikeja'),
      'MTN office, Ikeja',
    );
  });

  test('DeepSeekVoiceAgent fast-path resolves Lagos destinations, asks purpose follow-up, and builds errand checklist or casual reply', () async {
    final http = _FakeCloudHttp();
    final agent = DeepSeekVoiceAgent(
      groqApiKey: 'valid-groq-key',
      http: http,
      useLocalFastPath: true,
    );
    addTearDown(agent.dispose);

    // Stage 1: User says they are going to MTN office in Ikeja -> locks destination & asks "what for?"
    final mtnTurn = await agent.resolve(
      'Take me to empty end office in ekeja',
      wakeDetected: true,
    );
    expect(mtnTurn.intent, LocalIntent.destination);
    expect(mtnTurn.destination, 'MTN office, Ikeja');
    expect(mtnTurn.followUp, isTrue);
    expect(mtnTurn.text, contains('SIM registration'));
    expect(mtnTurn.checklist, isEmpty);

    // Stage 2: User replies with their purpose -> provides Nigerian SIM registration checklist!
    final simTurn = await agent.resolve(
      'I want to register a new SIM card',
      wakeDetected: true,
    );
    expect(simTurn.intent, LocalIntent.purpose);
    expect(simTurn.destination, 'MTN office, Ikeja');
    expect(simTurn.isCasual, isFalse);
    expect(simTurn.checklist, isNotEmpty);
    expect(simTurn.checklist.first, contains('NIN'));

    // Casual trip: User says they are visiting a friend in Yaba -> no checklist enforced!
    final casualTurn = await agent.resolve(
      'I am going to Yaba to visit my friend',
      wakeDetected: true,
    );
    expect(casualTurn.destination, 'Yaba');
    expect(casualTurn.isCasual, isTrue);
    expect(casualTurn.checklist, isEmpty);
    expect(http.jsonCalls, 0);
  });

  test('GroqSpeechEngine ignores pure silence and endpoints after voiced speech plus pause', () async {
    final http = _FakeCloudHttp(
      multipartHandler: ({
        required uri,
        required headers,
        required fields,
        required fileBytes,
      }) async {
        expect(uri.toString(), contains('groq.com/openai/v1/audio/transcriptions'));
        expect(headers['Authorization'], 'Bearer test-groq-key');
        expect(fields['model'], 'whisper-large-v3');
        expect(ascii.decode(fileBytes.sublist(0, 4)), 'RIFF');
        return const CloudHttpResponse(
          200,
          '{"text": "Take me to Lekki Phase 1"}',
        );
      },
    );
    final engine = GroqSpeechEngine(
      apiKey: 'test-groq-key',
      http: http,
      minSpeechFrames: 3,
      silenceEndpointFrames: 4,
    );
    addTearDown(engine.dispose);
    final events = <SpeechEvent>[];
    final sub = engine.events.listen(events.add);
    addTearDown(sub.cancel);

    await engine.initialize();
    engine.setMode(SpeechMode.listening);

    // 10 frames of silence: must not trigger any network upload.
    for (var i = 0; i < 10; i++) {
      engine.addAudio(_pcmChunk(800, 0));
    }
    await Future<void>.delayed(Duration.zero);
    expect(http.multipartCalls, 0);
    expect(events, isEmpty);

    // 4 frames of voiced speech followed by 4 frames of silence -> endpoints!
    for (var i = 0; i < 4; i++) {
      engine.addAudio(_pcmChunk(800, 6000));
    }
    for (var i = 0; i < 4; i++) {
      engine.addAudio(_pcmChunk(800, 0));
    }
    await Future<void>.delayed(Duration.zero);
    expect(http.multipartCalls, 1);
    expect(
      events.where((e) => e is TranscriptChanged || e is UtteranceEnded),
      [
        isA<TranscriptChanged>().having(
          (e) => e.text,
          'text',
          'Take me to Lekki Phase 1',
        ),
        isA<UtteranceEnded>().having(
          (e) => e.text,
          'text',
          'Take me to Lekki Phase 1',
        ),
      ],
    );
  });

  test('DeepSeekVoiceAgent parses structured JSON destinations and falls back on error', () async {
    var shouldFail = false;
    final http = _FakeCloudHttp(
      jsonHandler: ({required uri, required headers, required body}) async {
        if (shouldFail) {
          return const CloudHttpResponse(503, 'Service unavailable');
        }
        expect(headers['Authorization'], 'Bearer test-deepseek-key');
        expect(body['model'], 'deepseek-chat');
        return CloudHttpResponse(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'intent': 'destination',
                    'reply':
                        'Got it, heading to Ologolo bus stop. Please check the destination field.',
                    'destination': 'Ologolo bus stop',
                    'followUp': false,
                  }),
                },
              },
            ],
          }),
        );
      },
    );
    final agent = DeepSeekVoiceAgent(apiKey: 'test-deepseek-key', http: http);
    addTearDown(agent.dispose);

    // Conversational phrasing understood by DeepSeek.
    final reply = await agent.resolve(
      'I need to get over to Ologolo bus stop please',
      wakeDetected: true,
    );
    expect(reply.intent, LocalIntent.destination);
    expect(reply.destination, 'Ologolo bus stop');
    expect(reply.followUp, isFalse);
    expect(http.jsonCalls, 1);

    // Spoken stop requests explain the tap control without ending the session.
    final sleepReply = await agent.resolve('stop listening', wakeDetected: true);
    expect(sleepReply.intent, LocalIntent.clarify);
    expect(http.jsonCalls, 1);

    // Network error falls back cleanly to LocalCommandRouter.
    shouldFail = true;
    final fallbackReply = await agent.resolve(
      'take me to Ikeja',
      wakeDetected: true,
    );
    expect(fallbackReply.intent, LocalIntent.destination);
    expect(fallbackReply.destination, 'Ikeja');
  });

  test('DeepSeekVoiceAgent uses Groq qwen/qwen3.8-27b primary and fails over to openai/gpt-oss-20b on 429', () async {
    final requestedModels = <String>[];
    final http = _FakeCloudHttp(
      jsonHandler: ({required uri, required headers, required body}) async {
        final modelName = body['model'] as String;
        requestedModels.add(modelName);
        if (modelName == 'qwen/qwen3.8-27b') {
          return const CloudHttpResponse(429, '{"error": "Rate limit reached"}');
        }
        return CloudHttpResponse(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'intent': 'destination',
                    'reply': 'I have added Victoria Island to your destination field.',
                    'destination': 'Victoria Island',
                    'followUp': false,
                  }),
                },
              },
            ],
          }),
        );
      },
    );
    final agent = DeepSeekVoiceAgent(
      groqApiKey: 'valid-groq-key',
      http: http,
    );
    addTearDown(agent.dispose);

    final result = await agent.resolve(
      'Take me to Victoria Island',
      wakeDetected: true,
    );
    expect(result.intent, LocalIntent.destination);
    expect(result.destination, 'Victoria Island');
    expect(requestedModels, ['qwen/qwen3.8-27b', 'openai/gpt-oss-20b']);
  });

  test('DeepSeekVoiceAgent retains multi-turn history and respects followUp for ongoing conversations', () async {
    List<Object?>? lastMessages;
    var turn = 0;
    final http = _FakeCloudHttp(
      jsonHandler: ({required uri, required headers, required body}) async {
        turn++;
        lastMessages = body['messages'] as List<Object?>?;
        if (turn == 1) {
          return CloudHttpResponse(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'intent': 'greeting',
                      'reply': 'Hey there! Are we doing Island or Mainland today?',
                      'destination': null,
                      'followUp': true,
                    }),
                  },
                },
              ],
            }),
          );
        }
        return CloudHttpResponse(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'intent': 'destination',
                    'reply': 'Ah, Computer Village in Ikeja! Locked in.',
                    'destination': 'Computer Village',
                    'followUp': false,
                  }),
                },
              },
            ],
          }),
        );
      },
    );
    final agent = DeepSeekVoiceAgent(groqApiKey: 'valid-groq-key', http: http);
    addTearDown(agent.dispose);

    final first = await agent.resolve('Hello Navi', wakeDetected: true);
    expect(first.followUp, isTrue);
    expect(lastMessages!.length, 2); // system + user

    final second = await agent.resolve(
      'That place where they fix phones in Ikeja',
      wakeDetected: true,
    );
    expect(second.intent, LocalIntent.destination);
    expect(second.destination, 'Computer Village');
    expect(second.followUp, isFalse);
    expect(lastMessages!.length, 4); // system + turn1 user + turn1 assistant + turn2 user
  });

  test('tap conversation captures a destination and keeps listening for purpose', () async {
    final http = _FakeCloudHttp(
      multipartHandler: ({
        required uri,
        required headers,
        required fields,
        required fileBytes,
      }) async => const CloudHttpResponse(
        200,
        '{"text": "I want to visit Lekki Phase 1"}',
      ),
      jsonHandler: ({required uri, required headers, required body}) async =>
          CloudHttpResponse(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'intent': 'destination',
                      'reply': 'Lekki Phase 1 is ready in your destination box.',
                      'destination': 'Lekki Phase 1',
                      'followUp': false,
                    }),
                  },
                },
              ],
            }),
          ),
    );
    final microphone = _FakeMic();
    final output = _FakeOutput();
    final agent = DeepSeekVoiceAgent(apiKey: 'deepseek-key', http: http);
    addTearDown(agent.dispose);

    final container = ProviderContainer(
      overrides: [
        voiceServicesProvider.overrideWithValue(
          VoiceServices(
            microphone: () => microphone,
            speech: () => GroqSpeechEngine(
              apiKey: 'groq-key',
              http: http,
              minSpeechFrames: 2,
              silenceEndpointFrames: 2,
            ),
            output: () => output,
            reasoner: agent,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(voiceSessionProvider.notifier);
    controller.setHomeVisible(true);
    await Future<void>.delayed(Duration.zero);

    // Push-to-talk opens directly in listening phase without waiting for "Hey Navi".
    await controller.toggleConversation();
    expect(container.read(voiceSessionProvider).phase, VoicePhase.listening);
    expect(microphone.running, isTrue);

    // Feed 3 voiced frames + 3 silent frames to trigger VAD endpointing.
    for (var i = 0; i < 3; i++) {
      microphone.audio.add(_pcmChunk(800, 7000));
    }
    for (var i = 0; i < 3; i++) {
      microphone.audio.add(_pcmChunk(800, 0));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final stateDuringReply = container.read(voiceSessionProvider);
    expect(stateDuringReply.destination, 'Lekki Phase 1');
    expect(output.messages, ['Lekki Phase 1 is ready in your destination box.']);
    expect(microphone.running, isFalse);

    output.finish();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A destination alone must not end the conversation, even with followUp=false.
    expect(container.read(voiceSessionProvider).phase, VoicePhase.listening);
    expect(container.read(voiceSessionProvider).enabled, isTrue);
    expect(microphone.running, isTrue);
    await controller.toggleConversation();
    expect(microphone.running, isFalse);
  });

  test('GroqSpeechEngine adapts to room noise floor and endpoints when returning to room noise', () async {
    final http = _FakeCloudHttp(
      multipartHandler: ({
        required uri,
        required headers,
        required fields,
        required fileBytes,
      }) async => const CloudHttpResponse(200, '{"text": "Take me to Yaba"}'),
    );
    final engine = GroqSpeechEngine(
      apiKey: 'test-groq-key',
      http: http,
      minSpeechFrames: 3,
      silenceEndpointFrames: 4,
    );
    addTearDown(engine.dispose);
    final events = <SpeechEvent>[];
    final sub = engine.events.listen(events.add);
    addTearDown(sub.cancel);

    await engine.initialize();
    engine.setMode(SpeechMode.listening);

    // Room noise around -38.3 dBFS (amplitude 400): above static -43 dBFS,
    // must calibrate as noise floor and NOT trigger upload.
    for (var i = 0; i < 8; i++) {
      engine.addAudio(_pcmChunk(800, 400));
    }
    await Future<void>.delayed(Duration.zero);
    expect(http.multipartCalls, 0);
    expect(events.whereType<TranscriptionStarted>(), isEmpty);

    // User speaks clearly above noise floor, then pauses back at room noise.
    for (var i = 0; i < 4; i++) {
      engine.addAudio(_pcmChunk(800, 6000));
    }
    for (var i = 0; i < 4; i++) {
      engine.addAudio(_pcmChunk(800, 400));
    }
    await Future<void>.delayed(Duration.zero);
    expect(http.multipartCalls, 1);
    expect(events.whereType<TranscriptChanged>().single.text, 'Take me to Yaba');
  });

  test('GroqSpeechEngine ignores an isolated 50ms noise spike during pause', () async {
    final http = _FakeCloudHttp(
      multipartHandler: ({
        required uri,
        required headers,
        required fields,
        required fileBytes,
      }) async => const CloudHttpResponse(200, '{"text": "Going to Ikeja"}'),
    );
    final engine = GroqSpeechEngine(
      apiKey: 'test-groq-key',
      http: http,
      minSpeechFrames: 3,
      silenceEndpointFrames: 5,
    );
    addTearDown(engine.dispose);

    await engine.initialize();
    engine.setMode(SpeechMode.listening);

    for (var i = 0; i < 4; i++) {
      engine.addAudio(_pcmChunk(800, 6000));
    }
    for (var i = 0; i < 3; i++) {
      engine.addAudio(_pcmChunk(800, 0));
    }
    // Single 50 ms click must not wipe out pause progress.
    engine.addAudio(_pcmChunk(800, 6000));
    for (var i = 0; i < 2; i++) {
      engine.addAudio(_pcmChunk(800, 0));
    }
    await Future<void>.delayed(Duration.zero);
    expect(http.multipartCalls, 1);
  });

  test(
    'short map prompt reaches its cloud wait budget and reuses late cached audio',
    () async {
      AndroidVoiceOutput.resetStateForTesting();
      final gate = Completer<CloudHttpBytesResponse>();
      final sampleWav = encodePcm16MonoWav(
        _pcmChunk(800, 1000),
        sampleRate: 24000,
      );
      final http = _FakeCloudHttp(
        jsonBytesHandler: ({required uri, required headers, required body}) =>
            gate.future,
      );
      final output = AndroidVoiceOutput(
        groqApiKey: 'test',
        googleApiKey: '',
        synthesisBudget: const Duration(milliseconds: 20),
        http: http,
      );
      expect(await output.synthesizeForPlayback('Map prompt budget'), isNull);
      expect(gate.isCompleted, isFalse);
      gate.complete(CloudHttpBytesResponse(200, sampleWav));
      expect(await output.synthesizeWav('Map prompt budget'), isNotNull);
      expect(
        await output.synthesizeForPlayback('Map prompt budget'),
        isNotNull,
      );
      expect(http.jsonBytesCalls, 1);
      await output.dispose();
    },
  );

  test(
    'prewarming and map playback share synthesis without using a Google key without Android identity',
    () async {
      AndroidVoiceOutput.resetStateForTesting();
      final gate = Completer<CloudHttpBytesResponse>();
      final requested = Completer<void>();
      final sampleWav = encodePcm16MonoWav(
        _pcmChunk(800, 1000),
        sampleRate: 24000,
      );
      final http = _FakeCloudHttp(
        jsonBytesHandler: ({required uri, required headers, required body}) {
          expect(uri.host, 'api.groq.com');
          if (!requested.isCompleted) requested.complete();
          return gate.future;
        },
      );
      final prepare = AndroidVoiceOutput(
        groqApiKey: 'test',
        googleApiKey: 'android-key',
        http: http,
      );
      final playback = AndroidVoiceOutput(
        groqApiKey: 'test',
        googleApiKey: 'android-key',
        http: http,
      );
      final warmed = prepare.prepareSpeech('Shared map prompt');
      await requested.future;
      final audio = playback.synthesizeWav('Shared map prompt');
      await Future<void>.delayed(Duration.zero);
      expect(http.jsonBytesCalls, 1);
      gate.complete(CloudHttpBytesResponse(200, sampleWav));
      await warmed;
      expect(await audio, isNotNull);
      await prepare.dispose();
      await playback.dispose();
    },
  );

  test('synthesized cache separates different models and voices', () async {
    AndroidVoiceOutput.resetStateForTesting();
    final wav = encodePcm16MonoWav(_pcmChunk(800, 1000), sampleRate: 24000);
    final http = _FakeCloudHttp(
      jsonBytesHandler:
          ({required uri, required headers, required body}) async =>
              CloudHttpBytesResponse(200, wav),
    );
    for (final identity in [
      ('model-a', 'voice-a'),
      ('model-a', 'voice-b'),
      ('model-b', 'voice-b'),
    ]) {
      final output = AndroidVoiceOutput(
        groqApiKey: 'test',
        googleApiKey: '',
        ttsModel: identity.$1,
        ttsVoice: identity.$2,
        http: http,
      );
      expect(await output.synthesizeWav('Distinct voice cache'), isNotNull);
      await output.dispose();
    }
    expect(http.jsonBytesCalls, 3);
  });

  test('AndroidVoiceOutput synthesizes Orpheus WAV when Groq is healthy', () async {
    AndroidVoiceOutput.resetStateForTesting();
    final sampleWav = encodePcm16MonoWav(_pcmChunk(800, 1000), sampleRate: 24000);
    final http = _FakeCloudHttp(
      jsonBytesHandler: ({required uri, required headers, required body}) async {
        expect(uri.toString(), contains('api.groq.com/openai/v1/audio/speech'));
        expect(headers['Authorization'], 'Bearer test-groq-key');
        expect(body['model'], 'canopylabs/orpheus-v1-english');
        expect(body['voice'], 'hannah');
        return CloudHttpBytesResponse(200, sampleWav);
      },
    );
    final output = AndroidVoiceOutput(
      groqApiKey: 'test-groq-key',
      googleApiKey: 'test-google-key',
      http: http,
    );
    addTearDown(output.dispose);

    final wav = await output.synthesizeWav('Welcome to Lagos');
    expect(wav, isNotNull);
    expect(wav!.length, sampleWav.length);
    expect(http.jsonBytesCalls, 1);
  });

  test('AndroidVoiceOutput falls back to Google Cloud Chirp3-HD-Kore when Groq hits 429', () async {
    AndroidVoiceOutput.resetStateForTesting();
    final sampleWav = encodePcm16MonoWav(_pcmChunk(800, 1500), sampleRate: 24000);
    final calls = <String>[];
    final http = _FakeCloudHttp(
      jsonBytesHandler: ({required uri, required headers, required body}) async {
        final host = uri.host;
        calls.add(host);
        if (host.contains('groq.com')) {
          return CloudHttpBytesResponse(429, Uint8List(0));
        }
        if (host.contains('googleapis.com')) {
          expect(headers['X-Goog-Api-Key'], 'test-google-key');
          final voice = body['voice'] as Map;
          expect(voice['name'], 'en-US-Chirp3-HD-Kore');
          final jsonPayload = jsonEncode({'audioContent': base64Encode(sampleWav)});
          return CloudHttpBytesResponse(200, Uint8List.fromList(utf8.encode(jsonPayload)));
        }
        return CloudHttpBytesResponse(404, Uint8List(0));
      },
    );
    final output = AndroidVoiceOutput(
      groqApiKey: 'test-groq-key',
      googleApiKey: 'test-google-key',
      http: http,
    );
    addTearDown(output.dispose);

    final wav = await output.synthesizeWav('Next stop is Ikeja');
    expect(wav, isNotNull);
    expect(wav!.length, sampleWav.length);
    expect(calls, ['api.groq.com', 'texttospeech.googleapis.com']);
  });

  test('AndroidVoiceOutput returns null for offline fallback when both Groq and Google Cloud are unavailable', () async {
    AndroidVoiceOutput.resetStateForTesting();
    final calls = <String>[];
    final http = _FakeCloudHttp(
      jsonBytesHandler: ({required uri, required headers, required body}) async {
        final host = uri.host;
        calls.add(host);
        if (host.contains('groq.com')) {
          return CloudHttpBytesResponse(429, Uint8List(0));
        }
        if (host.contains('googleapis.com')) {
          // E.g. API key service blocked / permission denied (403)
          return CloudHttpBytesResponse(403, Uint8List.fromList(utf8.encode('{"error":{"code":403}}')));
        }
        return CloudHttpBytesResponse(500, Uint8List(0));
      },
    );
    final output = AndroidVoiceOutput(
      groqApiKey: 'test-groq-key',
      googleApiKey: 'test-google-key',
      http: http,
    );
    addTearDown(output.dispose);

    final wav = await output.synthesizeWav('Offline fallback turn');
    // Returning null triggers the native Android offline/device TTS engine.
    expect(wav, isNull);
    expect(calls, ['api.groq.com', 'texttospeech.googleapis.com']);
  });

  test('active transit Q&A sends live telemetry and refuses casual destination hijack', () async {
    final capturedMessages = <List<dynamic>>[];
    final http = _FakeCloudHttp(
      jsonHandler: ({required uri, required headers, required body}) async {
        capturedMessages.add(body['messages'] as List<dynamic>);
        return CloudHttpResponse(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'intent': 'transit_answer',
                    'destination': 'Ikeja',
                    'changeTrip': false,
                    'checklist': ['Laptop'],
                    'reply': 'Stay headed toward Lekki Phase 1; you are near Admiralty Way, about 1.4 km away.',
                    'followUp': true,
                  }),
                },
              },
            ],
          }),
        );
      },
    );
    final agent = DeepSeekVoiceAgent(groqApiKey: 'test', http: http, useLocalFastPath: true);
    addTearDown(agent.dispose);
    agent.updateTransitContext(
      const JourneyTransitContext(
        isActive: true,
        destination: 'Lekki Phase 1',
        currentArea: 'Admiralty Way, Lekki Phase I',
        remainingDistanceMeters: 1400,
        remainingDurationSeconds: 360,
        travelModeLabel: 'By bus',
        purposeSummary: 'Meeting',
      ),
    );

    final reply = await agent.resolve('Am I close to Ikeja yet?', wakeDetected: false);
    expect(capturedMessages, hasLength(1));
    final serialized = jsonEncode(capturedMessages.single);
    expect(serialized, contains('LIVE ACTIVE TRIP TELEMETRY'));
    expect(serialized, contains('Admiralty Way, Lekki Phase I'));
    expect(serialized, contains('Lekki Phase 1'));
    expect(serialized, contains('By bus'));
    expect(reply.changeTrip, isFalse);
    expect(reply.endTrip, isFalse);
    expect(reply.checklist, isEmpty);
    expect(reply.destination, isNot('Ikeja'));
    expect(reply.followUp, isTrue);
  });

  test('explicit mid-trip switch asks What for? then builds checklist and new destination', () async {
    final http = _FakeCloudHttp(
      jsonHandler: ({required uri, required headers, required body}) async {
        return CloudHttpResponse(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'intent': 'clarify',
                    'destination': 'Ikeja',
                    'changeTrip': true,
                    'reply': 'Okay, switching your trip to Ikeja. What are you going there for?',
                    'followUp': true,
                  }),
                },
              },
            ],
          }),
        );
      },
    );
    final agent = DeepSeekVoiceAgent(groqApiKey: 'test', http: http, useLocalFastPath: true);
    addTearDown(agent.dispose);
    agent.updateTransitContext(
      const JourneyTransitContext(
        isActive: true,
        destination: 'Lekki Phase 1',
        currentArea: 'Lekki Expressway',
        remainingDistanceMeters: 3000,
        remainingDurationSeconds: 600,
      ),
    );

    final turn1 = await agent.resolve(
      'I want to change my trip from Lekki to Ikeja',
      wakeDetected: false,
    );
    expect(turn1.changeTrip, isTrue);
    expect(turn1.destination, 'Ikeja');
    expect(turn1.followUp, isTrue);
    expect(turn1.text.toLowerCase(), anyOf(contains('what'), contains('for')));

    // Simulate widget rebuild pushing telemetry while switch conversation continues.
    agent.updateTransitContext(
      const JourneyTransitContext(
        isActive: true,
        destination: 'Lekki Phase 1',
        currentArea: 'Lekki Expressway',
        remainingDistanceMeters: 2950,
        remainingDurationSeconds: 590,
      ),
    );

    final turn2 = await agent.resolve('To swap my SIM card', wakeDetected: false);
    expect(turn2.changeTrip, isTrue);
    expect(turn2.destination, contains('Ikeja'));
    expect(turn2.purposeSummary, isNotNull);
    expect(turn2.purposeSummary, isNotEmpty);
    expect(turn2.checklist, isNotEmpty);
  });

  test('explicit End my trip ends the active trip without follow-up', () async {
    final http = _FakeCloudHttp(
      jsonHandler: ({required uri, required headers, required body}) async {
        return CloudHttpResponse(
          200,
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'intent': 'end_trip',
                    'endTrip': true,
                    'reply': 'Ending your current trip now.',
                    'followUp': false,
                  }),
                },
              },
            ],
          }),
        );
      },
    );
    final agent = DeepSeekVoiceAgent(groqApiKey: 'test', http: http, useLocalFastPath: true);
    addTearDown(agent.dispose);
    agent.updateTransitContext(
      const JourneyTransitContext(
        isActive: true,
        destination: 'Lekki Phase 1',
        currentArea: 'Admiralty Way',
        remainingDistanceMeters: 500,
        remainingDurationSeconds: 120,
      ),
    );

    final reply = await agent.resolve('End my trip', wakeDetected: false);
    expect(reply.endTrip, isTrue);
    expect(reply.followUp, isFalse);
  });
}

class _FakeCloudHttp implements CloudHttpTransport {
  _FakeCloudHttp({
    this.multipartHandler,
    this.jsonHandler,
    this.jsonBytesHandler,
  });

  final Future<CloudHttpResponse> Function({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> fields,
    required Uint8List fileBytes,
  })? multipartHandler;

  final Future<CloudHttpResponse> Function({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  })? jsonHandler;

  final Future<CloudHttpBytesResponse> Function({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  })? jsonBytesHandler;

  int multipartCalls = 0;
  int jsonCalls = 0;
  int jsonBytesCalls = 0;

  @override
  Future<CloudHttpResponse> postMultipart({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required String contentType,
    required Uint8List fileBytes,
    Duration timeout = const Duration(seconds: 10),
  }) {
    multipartCalls++;
    return multipartHandler!(
      uri: uri,
      headers: headers,
      fields: fields,
      fileBytes: fileBytes,
    );
  }

  @override
  Future<CloudHttpResponse> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
  }) {
    jsonCalls++;
    return jsonHandler!(uri: uri, headers: headers, body: body);
  }

  @override
  Future<CloudHttpBytesResponse> postJsonBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
    int maxBytes = 4194304,
  }) {
    jsonBytesCalls++;
    if (jsonBytesHandler != null) {
      return jsonBytesHandler!(uri: uri, headers: headers, body: body);
    }
    return Future.value(CloudHttpBytesResponse(400, Uint8List(0)));
  }

  @override
  void close() {}
}

class _BudgetHttp extends _FakeCloudHttp {
  _BudgetHttp(this.budgets);
  final List<Duration> budgets;
  @override
  Future<CloudHttpResponse> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    jsonCalls++;
    budgets.add(timeout);
    return const CloudHttpResponse(503, '{}');
  }
}

class _FakeMic implements MicrophoneInput {
  bool running = false;
  final audio = StreamController<Uint8List>.broadcast(sync: true);

  @override
  Future<bool> hasPermission({required bool request}) async => true;

  @override
  Future<Stream<Uint8List>> start() async {
    running = true;
    return audio.stream;
  }

  @override
  Future<void> stop() async {
    running = false;
  }

  @override
  Future<void> dispose() async {
    running = false;
  }
}

class _FakeOutput implements VoiceGateway {
  final stream = StreamController<OutputEvent>.broadcast(sync: true);
  final messages = <String>[];
  Completer<void>? _completion;
  int? _id;

  void finish() {
    if (_id != null) {
      stream.add(OutputEvent(_id!, OutputEventType.started));
      stream.add(OutputEvent(_id!, OutputEventType.completed));
    }
    _completion?.complete();
  }

  @override
  Stream<OutputEvent> get events => stream.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String message, {required int id}) {
    _id = id;
    messages.add(message);
    _completion = Completer<void>();
    return _completion!.future;
  }

  @override
  Future<void> stopSpeaking() async {
    _completion?.complete();
  }

  @override
  Future<void> dispose() async {}
}
