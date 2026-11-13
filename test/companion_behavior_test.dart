import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/character/domain/companion_idle_policy.dart';
import 'package:navi/features/character/domain/navi_clip.dart';
import 'package:navi/features/character/presentation/companion_controller.dart';
import 'package:navi/features/voice/application/voice_session_controller.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

class _Voice extends VoiceSessionController {
  @override
  VoiceSessionState build() => const VoiceSessionState();
  void phase(VoicePhase phase) {
    state = VoiceSessionState(phase: phase);
  }
}

void main() {
  late ProviderContainer container;
  late CompanionController companion;
  late _Voice voice;
  CompanionFrame frame() => container.read(companionProvider);
  setUp(() {
    container = ProviderContainer(
      overrides: [
        voiceSessionProvider.overrideWith(_Voice.new),
        companionIdlePolicyProvider.overrideWithValue(
          CompanionIdlePolicy(
            minimumQuiet: const Duration(seconds: 10),
            maximumQuiet: const Duration(seconds: 10),
          ),
        ),
      ],
    );
    container.listen(companionProvider, (_, _) {});
    companion = container.read(companionProvider.notifier);
    voice = container.read(voiceSessionProvider.notifier) as _Voice;
  });
  void behavior(String name, Future<void> Function(WidgetTester) run) {
    testWidgets(name, (tester) async {
      try {
        await run(tester);
      } finally {
        container.dispose();
      }
    });
  }

  behavior(
    'rests by default; quiet time plays exactly one gesture then rests again',
    (tester) async {
      companion.setVisible(true);
      expect(frame().still, isTrue);
      expect(frame().repeat, isFalse);
      await tester.pump(const Duration(seconds: 9));
      expect(frame().still, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(frame().activity, CompanionActivity.idle);
      expect(frame().still, isFalse);
      expect(frame().repeat, isFalse);
      final revision = frame().revision;
      companion.clipCompleted(revision);
      expect(frame().still, isTrue);
      await tester.pump(const Duration(seconds: 9));
      expect(frame().still, isTrue);
      expect(frame().revision, revision + 1);
    },
  );

  behavior(
    'interaction resets quiet time and stops a discretionary idle gesture',
    (tester) async {
      companion.setVisible(true);
      await tester.pump(const Duration(seconds: 9));
      companion.userInteracted();
      await tester.pump(const Duration(seconds: 9));
      expect(frame().still, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(frame().still, isFalse);
      companion.userInteracted();
      expect(frame().still, isTrue);
      await tester.pump(const Duration(seconds: 9));
      expect(frame().still, isTrue);
    },
  );

  behavior(
    'touch reaction plays once; missing playback completion has a bounded fallback',
    (tester) async {
      companion.setVisible(true);
      companion.touched();
      expect(frame().activity, CompanionActivity.reaction);
      expect(frame().clip, NaviClips.smile);
      expect(frame().repeat, isFalse);
      await tester.pump(const Duration(seconds: 12));
      expect(frame().activity, CompanionActivity.idle);
      expect(frame().still, isTrue);
    },
  );

  behavior(
    'listening expression is held until the voice state ends, independent of clip length',
    (tester) async {
      companion.setVisible(true);
      voice.phase(VoicePhase.listening);
      expect(frame().clip, NaviClips.listening);
      expect(frame().still, isTrue);
      final revision = frame().revision;
      await tester.pump(const Duration(seconds: 20));
      companion.clipCompleted(revision);
      companion.touched();
      expect(frame().activity, CompanionActivity.listening);
      expect(frame().revision, revision);
      voice.phase(VoicePhase.preparingReply);
      expect(frame().activity, CompanionActivity.thinking);
      companion.clipCompleted(revision);
      expect(frame().activity, CompanionActivity.thinking);
      voice.phase(VoicePhase.off);
      expect(frame().still, isTrue);
      expect(frame().activity, CompanionActivity.idle);
    },
  );

  behavior(
    'hidden screens, errors and reduced motion never schedule idle gestures',
    (tester) async {
      await tester.pump(const Duration(minutes: 3));
      expect(frame().still, isTrue);
      companion.setVisible(true);
      companion.setReducedMotion(true);
      await tester.pump(const Duration(minutes: 3));
      expect(frame().still, isTrue);
      companion.setReducedMotion(false);
      voice.phase(VoicePhase.error);
      await tester.pump(const Duration(minutes: 3));
      expect(frame().still, isTrue);
      voice.phase(VoicePhase.off);
      companion.setVisible(false);
      await tester.pump(const Duration(minutes: 3));
      expect(frame().still, isTrue);
    },
  );
}
