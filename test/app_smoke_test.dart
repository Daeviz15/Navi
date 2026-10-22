import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navi/app/navi_app.dart';
import 'package:navi/app/router.dart';
import 'package:navi/core/theme/navi_theme.dart';
import 'package:navi/core/widgets/navi_companion.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/fake_video_player.dart';

void main() {
  late FakeVideoPlayer video;
  late VideoPlayerPlatform originalVideoPlatform;

  setUp(() {
    originalVideoPlatform = VideoPlayerPlatform.instance;
    video = FakeVideoPlayer();
    VideoPlayerPlatform.instance = video;
    naviRouter.go('/');
  });

  tearDown(() => VideoPlayerPlatform.instance = originalVideoPlatform);

  testWidgets('plans a destination, chooses a purpose and travel mode', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: NaviApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Where are we'), findsOneWidget);
    expect(video.assets, [NaviCompanion.videoAsset]);
    expect(video.volumes.values, everyElement(0));
    expect(video.playing, isNotEmpty);

    await tester.enterText(find.byType(TextFormField), 'MTN office, Ikeja');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(find.text('What brings you there?'), findsOneWidget);
    expect(find.text('MTN office, Ikeja'), findsOneWidget);
    expect(video.playing, isEmpty);

    await tester.tap(find.text('Just show me the way'));
    await tester.pumpAndSettle();
    expect(find.text('Journey overview'), findsOneWidget);
    expect(find.text('MTN office, Ikeja'), findsOneWidget);

    await tester.tap(find.text('On foot'));
    await tester.pumpAndSettle();
    final selected = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('On foot'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(selected.selected, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('defaults to black and switches themes without losing input', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: NaviApp()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Lekki');

    var theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, Colors.black);
    expect(theme.colorScheme.primary, NaviColors.gold);

    await tester.tap(find.byTooltip('Switch to light mode'));
    // The transparent character now runs continuously in light mode.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.light);
    expect(video.playing, isEmpty);
    expect(find.text('Lekki'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    expect(video.playing, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact layout supports larger text and an open keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const ProviderScope(child: NaviApp()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byType(TextFormField));
    await tester.tap(find.byType(TextFormField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Ikeja');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(find.text('What brings you there?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'character has no playback controls and pauses in the background',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NaviTheme.dark,
          home: const Scaffold(body: NaviCompanion()),
        ),
      );
      await tester.pumpAndSettle();
      expect(video.playing, isNotEmpty);

      expect(
        find.descendant(
          of: find.byType(NaviCompanion),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(video.playing, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(video.playing, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => video.disposalCompleted.future);
      expect(video.disposed, isNotEmpty);
    },
  );

  testWidgets('home header stays fixed while the content scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: NaviApp()));
    await tester.pumpAndSettle();
    final logoPosition = tester.getTopLeft(find.text('navi'));
    final headingPosition = tester.getTopLeft(
      find.textContaining('Where are we'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('navi')), logoPosition);
    expect(
      tester.getTopLeft(find.textContaining('Where are we')).dy,
      lessThan(headingPosition.dy),
    );
    expect(
      find.byTooltip('Switch to light mode').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows a still frame without autoplay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: NaviCompanion()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(video.playing, isEmpty);
    expect(find.byTooltip('Pause Navi animation'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
