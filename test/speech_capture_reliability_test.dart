import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/voice/data/cloud_http_client.dart';
import 'package:navi/features/voice/data/deepseek_voice_agent.dart';
import 'package:navi/features/voice/data/groq_speech_engine.dart';
import 'package:navi/features/voice/data/transcription_quality.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

Uint8List pcm(List<int> amplitudes) {
  final bytes = ByteData(amplitudes.length * 1600);
  for (var frame = 0; frame < amplitudes.length; frame++) {
    for (var sample = 0; sample < 800; sample++) {
      bytes.setInt16(
        frame * 1600 + sample * 2,
        sample.isEven ? amplitudes[frame] : -amplitudes[frame],
        Endian.little,
      );
    }
  }
  return bytes.buffer.asUint8List();
}

Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final chunkSize in [33, 1600, 3200, 64000]) {
    test(
      'quiet immediate speech preserves its first words with $chunkSize-byte chunks',
      () async {
        final http = _Http();
        final engine = GroqSpeechEngine(apiKey: 'fixture', http: http);
        final events = <SpeechEvent>[];
        final subscription = engine.events.listen(events.add);
        addTearDown(subscription.cancel);
        addTearDown(engine.dispose);
        await engine.initialize();
        engine.setMode(SpeechMode.listening);
        // Around -50 dBFS, below the old fixed onset threshold. No lead-in silence.
        final input = pcm([...List.filled(9, 100), ...List.filled(15, 0)]);
        for (var offset = 0; offset < input.length; offset += chunkSize) {
          engine.addAudio(
            Uint8List.sublistView(
              input,
              offset,
              (offset + chunkSize).clamp(0, input.length),
            ),
          );
        }
        await flush();
        expect(http.uploads, hasLength(1));
        expect(http.uploads.single.sublist(44), input);
        expect(http.fields!['response_format'], 'verbose_json');
        expect(http.fields!['model'], 'whisper-large-v3');
        expect(
          events.whereType<UtteranceEnded>().single.text,
          'Take me to Ikeja',
        );
      },
    );
  }

  test(
    'stationary fan-like energy settles without uploading; louder speech endpoints over it',
    () async {
      final http = _Http();
      final engine = GroqSpeechEngine(apiKey: 'fixture', http: http);
      addTearDown(engine.dispose);
      await engine.initialize();
      engine.setMode(SpeechMode.listening);
      for (var i = 0; i < 60; i++) {
        engine.addAudio(pcm([400]));
      }
      await flush();
      expect(http.uploads, isEmpty);
      engine.addAudio(pcm([1200, 2200, 1400, 3000, 2000, 1600]));
      engine.addAudio(pcm(List.filled(15, 400)));
      await flush();
      expect(http.uploads, hasLength(1));
    },
  );

  test('a short pause inside a sentence does not submit its prefix', () async {
    final http = _Http();
    final engine = GroqSpeechEngine(apiKey: 'fixture', http: http);
    addTearDown(engine.dispose);
    await engine.initialize();
    engine.setMode(SpeechMode.listening);
    engine.addAudio(pcm([2000, 3000, 2500, 4000]));
    engine.addAudio(pcm(List.filled(12, 0)));
    expect(http.uploads, isEmpty);
    engine.addAudio(pcm([2500, 3000, 4000, 3500]));
    engine.addAudio(pcm(List.filled(15, 0)));
    await flush();
    expect(http.uploads, hasLength(1));
  });

  test(
    'poor transcription asks for a repeat without sending a guessed instruction',
    () async {
      final http = _Http()
        ..response = jsonEncode({
          'text': 'End my trip',
          'segments': [
            {
              'text': 'End my trip',
              'avg_logprob': -1.7,
              'no_speech_prob': 0.1,
              'compression_ratio': 1.1,
            },
          ],
        });
      final engine = GroqSpeechEngine(apiKey: 'fixture', http: http);
      final events = <SpeechEvent>[];
      final sub = engine.events.listen(events.add);
      addTearDown(sub.cancel);
      addTearDown(engine.dispose);
      await engine.initialize();
      engine.setMode(SpeechMode.listening);
      engine.addAudio(pcm([...List.filled(6, 3000), ...List.filled(15, 0)]));
      await flush();
      expect(events.whereType<UtteranceEnded>(), isEmpty);
      expect(events.whereType<TranscriptChanged>(), isEmpty);
      expect(events.whereType<ListeningResumed>().single.needsRepeat, isTrue);
      http.response = '{"text":"Take me to Ikeja"}';
      engine.addAudio(pcm([...List.filled(6, 3000), ...List.filled(15, 0)]));
      await flush();
      expect(
        events.whereType<UtteranceEnded>().single.text,
        'Take me to Ikeja',
      );
    },
  );

  test(
    'a cancelled upload cannot resume or publish into the next turn',
    () async {
      final http = _Http()..pending = Completer<CloudHttpResponse>();
      final engine = GroqSpeechEngine(apiKey: 'fixture', http: http);
      final events = <SpeechEvent>[];
      final sub = engine.events.listen(events.add);
      addTearDown(sub.cancel);
      addTearDown(engine.dispose);
      await engine.initialize();
      engine.setMode(SpeechMode.listening);
      engine.addAudio(pcm([...List.filled(6, 3000), ...List.filled(15, 0)]));
      engine.setMode(SpeechMode.muted);
      engine.setMode(SpeechMode.listening);
      http.pending!.complete(
        const CloudHttpResponse(200, '{"text":"Old request"}'),
      );
      await flush();
      expect(events.whereType<UtteranceEnded>(), isEmpty);
      expect(events.whereType<ListeningResumed>(), isEmpty);
    },
  );

  test(
    'quality metadata rejects noise and repetition but permits plausible accented speech',
    () {
      TranscriptionQuality quality(
        double logprob,
        double noSpeech,
        double compression,
      ) => TranscriptionQuality.evaluate({
        'segments': [
          {
            'text': 'Ikeja',
            'avg_logprob': logprob,
            'no_speech_prob': noSpeech,
            'compression_ratio': compression,
          },
        ],
      });
      expect(quality(-1.4, .95, 1), TranscriptionQuality.noSpeech);
      expect(quality(-.3, .05, 3), TranscriptionQuality.uncertain);
      expect(quality(-.8, .2, 1.1), TranscriptionQuality.usable);
      expect(
        TranscriptionQuality.evaluate({'text': 'Ikeja'}),
        TranscriptionQuality.usable,
      );
    },
  );

  test(
    'general conversational words are not rewritten as Lagos places before reasoning',
    () async {
      final http = _Http();
      final agent = DeepSeekVoiceAgent(apiKey: 'fixture', http: http);
      addTearDown(agent.dispose);
      const words =
          'We caught on quickly, but the bag was empty and I stayed home.';
      await agent.resolve(words, wakeDetected: false);
      final messages = http.reasoning!['messages'] as List;
      expect((messages.last as Map)['content'], words);
    },
  );
}

class _Http extends Fake implements CloudHttpTransport {
  final uploads = <Uint8List>[];
  Map<String, String>? fields;
  Map<String, Object?>? reasoning;
  String response = '{"text":"Take me to Ikeja"}';
  Completer<CloudHttpResponse>? pending;
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
  }) async {
    uploads.add(Uint8List.fromList(fileBytes));
    this.fields = fields;
    return pending?.future ?? CloudHttpResponse(200, response);
  }

  @override
  Future<CloudHttpResponse> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    reasoning = body;
    return const CloudHttpResponse(
      200,
      '{"choices":[{"message":{"content":"{\\"intent\\":\\"clarify\\",\\"reply\\":\\"Where would you like to go?\\"}"}}]}',
    );
  }

  @override
  void close() {}
}
