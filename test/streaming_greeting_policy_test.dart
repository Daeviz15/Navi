import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/voice/domain/local_command_router.dart';
import 'package:navi/features/voice/domain/streaming_greeting_policy.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

void main() {
  for (final greeting in [
    'Hi Navi',
    'Hey Navi',
    'Hello Navi',
    'Hi Navy',
    'Hello, NAVY!',
    'Hey Na Vee',
    'Hainavi',
    'HiNavi,',
    'HeyNavy!',
  ]) {
    test('$greeting accepts a final greeting and ends the listening turn', () {
      final policy = StreamingGreetingPolicy()..reset(SpeechMode.wake);
      final events = policy.accept(line: '1', text: greeting, complete: true);
      expect(events.map((e) => e.runtimeType), [
        WakeDetected,
        TranscriptChanged,
      ]);
      expect(policy.mode, SpeechMode.listening);
      final ended = policy.advance(
        audioPosition: const Duration(seconds: 1),
        quiet: true,
      );
      expect(ended.single, isA<UtteranceEnded>());
      expect(
        const LocalCommandRouter()
            .route((ended.single as UtteranceEnded).text, wakeDetected: true)
            .intent,
        LocalIntent.greeting,
      );
      expect(policy.mode, SpeechMode.muted);
      expect(policy.accept(line: '1', text: greeting, complete: true), isEmpty);
    });
  }

  test('two agreeing partials wake once and retain a one-breath command', () {
    final policy = StreamingGreetingPolicy()..reset(SpeechMode.wake);
    expect(
      policy.accept(line: '1', text: 'Hey Navi', complete: false),
      isEmpty,
    );
    final wake = policy.accept(
      line: '1',
      text: 'Hey Navi, take me',
      complete: false,
    );
    expect(wake.whereType<WakeDetected>().length, 1);
    final rest = policy.accept(
      line: '1',
      text: 'Hey Navi, take me to Lekki',
      complete: true,
    );
    expect(rest.whereType<WakeDetected>(), isEmpty);
    expect(rest.whereType<UtteranceEnded>(), isEmpty);
    final text = policy
        .advance(audioPosition: const Duration(seconds: 1), quiet: true)
        .whereType<UtteranceEnded>()
        .single
        .text;
    expect(
      const LocalCommandRouter().route(text, wakeDetected: true).destination,
      'Lekki',
    );
  });

  test('a retracted provisional name never wakes', () {
    final policy = StreamingGreetingPolicy()..reset(SpeechMode.wake);
    expect(policy.accept(line: '1', text: 'Hi Navi', complete: false), isEmpty);
    expect(
      policy.accept(line: '1', text: 'Hi David', complete: false),
      isEmpty,
    );
    expect(policy.accept(line: '1', text: 'Hi David', complete: true), isEmpty);
    expect(policy.mode, SpeechMode.wake);
  });

  test(
    'unrelated speech, quoted greetings, negations and partial names stay armed',
    () {
      final policy = StreamingGreetingPolicy()..reset(SpeechMode.wake);
      final phrases = [
        'Hey David, the navy blue car looks nice',
        'I love you',
        'Hi there',
        'Navi',
        'Hey navigator',
        'Hello navigation',
        'She said hey Navi',
        "Don't say hey Navi",
        'Hey Navis',
        'The navy is here',
        'Hainavigation',
        'Hello Navid',
      ];
      for (var i = 0; i < phrases.length; i++) {
        expect(
          policy.accept(line: '$i', text: phrases[i], complete: true),
          isEmpty,
          reason: phrases[i],
        );
      }
      expect(policy.mode, SpeechMode.wake);
    },
  );

  test('partial agreement cannot cross lines or sessions', () {
    final policy = StreamingGreetingPolicy()..reset(SpeechMode.wake);
    expect(policy.accept(line: '1', text: 'Hi Navi', complete: false), isEmpty);
    expect(policy.accept(line: '2', text: 'Hi Navi', complete: false), isEmpty);
    policy.reset(SpeechMode.wake);
    expect(policy.accept(line: '2', text: 'Hi Navi', complete: false), isEmpty);
  });

  test('follow-up accepts a command without requiring another wake', () {
    final policy = StreamingGreetingPolicy()..reset(SpeechMode.listening);
    final events = policy.accept(
      line: '1',
      text: 'Take me to Ikeja',
      complete: true,
    );
    expect(events.map((e) => e.runtimeType), [TranscriptChanged]);
    expect(
      policy
          .advance(audioPosition: const Duration(seconds: 1), quiet: true)
          .single,
      isA<UtteranceEnded>(),
    );
    policy.reset(SpeechMode.muted);
    expect(policy.accept(line: '2', text: 'Hey Navi', complete: true), isEmpty);
  });

  test('a split greeting and command remain one turn until a real pause', () {
    final policy = StreamingGreetingPolicy()..reset(SpeechMode.wake);
    final greeting = policy.accept(
      line: '1',
      text: 'Hey, Navi,',
      complete: true,
      audioPosition: const Duration(seconds: 1),
    );
    expect(greeting.whereType<WakeDetected>().length, 1);
    expect(
      policy.advance(
        audioPosition: const Duration(milliseconds: 1400),
        quiet: true,
      ),
      isEmpty,
    );
    // VAD detects the continuing speech before its words are decoded.
    policy.accept(
      line: '2',
      text: '',
      complete: false,
      audioPosition: const Duration(milliseconds: 1500),
    );
    expect(
      policy.advance(audioPosition: const Duration(seconds: 2), quiet: false),
      isEmpty,
    );
    policy.accept(
      line: '2',
      text: 'Take me to London.',
      complete: true,
      audioPosition: const Duration(seconds: 3),
    );
    expect(
      policy.advance(
        audioPosition: const Duration(milliseconds: 3600),
        quiet: true,
      ),
      isEmpty,
    );
    final ended =
        policy
                .advance(
                  audioPosition: const Duration(milliseconds: 3700),
                  quiet: true,
                )
                .single
            as UtteranceEnded;
    expect(ended.text, 'Hey, Navi, Take me to London.');
    expect(
      const LocalCommandRouter()
          .route(ended.text, wakeDetected: true)
          .destination,
      'London',
    );
  });
}
