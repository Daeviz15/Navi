import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/core/theme/navi_theme.dart';
import 'package:navi/core/widgets/navi_companion.dart';
import 'package:navi/features/character/domain/navi_clip.dart';
import 'package:navi/features/character/presentation/companion_controller.dart';

void main() {
  Widget stage({
    NaviClip clip = NaviClips.sip,
    CompanionActivity? activity,
    int revision = 0,
    bool engaged = false,
    bool light = false,
    bool reduceMotion = false,
    bool holdPose = false,
    bool repeat = false,
    ValueNotifier<double>? audioLevel,
    VoidCallback? onCompleted,
  }) => MaterialApp(
    theme: light ? NaviTheme.light : NaviTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: NaviCompanion(
            clip: clip,
            activity: activity,
            revision: revision,
            engaged: engaged,
            holdPose: holdPose,
            repeat: repeat,
            audioLevel: audioLevel,
            onCompleted: onCompleted,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'one-shot cloud gesture completes once and ignores superseded revisions',
    (tester) async {
      var completions = 0;
      await tester.pumpWidget(
        stage(
          clip: NaviClips.sip,
          revision: 1,
          holdPose: false,
          repeat: false,
          onCompleted: () => completions++,
        ),
      );
      final state = tester.state<NaviCompanionState>(
        find.byType(NaviCompanion),
      );
      expect(state.isAnimating, isTrue);

      // Supersede revision mid-cycle before completion.
      await tester.pump(const Duration(milliseconds: 900));
      expect(completions, 0);
      await tester.pumpWidget(
        stage(
          clip: NaviClips.smile,
          activity: CompanionActivity.reaction,
          revision: 2,
          holdPose: false,
          repeat: false,
          onCompleted: () => completions++,
        ),
      );
      await tester.pumpAndSettle();
      expect(completions, 1);
      expect(state.isAnimating, isFalse);
    },
  );

  testWidgets(
    'live microphone audio level repaints the cloud without rebuilding the widget tree',
    (tester) async {
      final level = ValueNotifier<double>(0.0);
      addTearDown(level.dispose);
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: NaviTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                builds++;
                return Center(
                  child: NaviCompanion(
                    clip: NaviClips.listening,
                    activity: CompanionActivity.listening,
                    engaged: true,
                    holdPose: true,
                    audioLevel: level,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, 1);

      level.value = 0.45;
      await tester.pump();
      level.value = 0.92;
      await tester.pump();
      level.value = 0.0;
      await tester.pump();

      expect(builds, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'attention zoom eases within a fixed padded stage and honors reduced motion',
    (tester) async {
      await tester.pumpWidget(stage(holdPose: true));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byKey(const ValueKey('navi-stage')));
      await tester.pumpWidget(stage(engaged: true, holdPose: true));
      await tester.pump(const Duration(milliseconds: 160));
      final scale = tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byKey(const ValueKey('navi-focus')),
          matching: find.byType(ScaleTransition),
        ),
      );
      expect(scale.scale.value, greaterThan(1));
      expect(scale.scale.value, lessThan(1.035));
      expect(tester.getRect(find.byKey(const ValueKey('navi-stage'))), bounds);
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        stage(engaged: true, holdPose: false, repeat: true, reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedScale>(find.byKey(const ValueKey('navi-focus')))
            .scale,
        1,
      );
      expect(
        tester
            .state<NaviCompanionState>(find.byType(NaviCompanion))
            .isAnimating,
        isFalse,
      );
    },
  );

  testWidgets(
    'light and dark themes render all companion activities cleanly',
    (tester) async {
      for (final light in [false, true]) {
        for (final activity in CompanionActivity.values) {
          await tester.pumpWidget(
            stage(
              light: light,
              activity: activity,
              revision: activity.index,
              engaged:
                  activity == CompanionActivity.listening ||
                  activity == CompanionActivity.thinking ||
                  activity == CompanionActivity.speaking,
              holdPose: activity == CompanionActivity.idle,
              repeat:
                  activity == CompanionActivity.thinking ||
                  activity == CompanionActivity.speaking,
            ),
          );
          await tester.pump(const Duration(milliseconds: 150));
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'looping behaviors animate continuously without firing one-shot completion',
    (tester) async {
      var completions = 0;
      await tester.pumpWidget(
        stage(
          clip: NaviClips.speaking,
          activity: CompanionActivity.speaking,
          engaged: true,
          holdPose: false,
          repeat: true,
          onCompleted: () => completions++,
        ),
      );
      await tester.pump(const Duration(seconds: 6));
      final state = tester.state<NaviCompanionState>(
        find.byType(NaviCompanion),
      );
      expect(state.isAnimating, isTrue);
      expect(completions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
