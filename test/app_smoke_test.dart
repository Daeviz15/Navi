import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navi/app/navi_app.dart';
import 'package:navi/app/router.dart';
import 'package:navi/core/theme/navi_theme.dart';
import 'package:navi/core/widgets/navi_companion.dart';
import 'package:navi/features/character/presentation/companion_controller.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';

void main() {
  setUp(() {
    naviRouter.go('/');
  });

  testWidgets('plans a destination, chooses a purpose and travel mode', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: NaviApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Where are we'), findsOneWidget);
    expect(find.byKey(const ValueKey('navi-cloud-canvas')), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'MTN office, Ikeja');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(find.text('What brings you there?'), findsOneWidget);
    expect(find.text('MTN office, Ikeja'), findsOneWidget);

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.brightness, Brightness.light);
    expect(find.text('Lekki'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to dark mode'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
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

    expect(
      tester.getRect(find.text('navi')).right,
      lessThan(tester.getRect(find.byTooltip('Enable hands-free')).left),
    );
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
          home: const Scaffold(
            body: NaviCompanion(
              activity: CompanionActivity.speaking,
              holdPose: false,
              repeat: true,
              engaged: true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final state = tester.state<NaviCompanionState>(
        find.byType(NaviCompanion),
      );
      expect(state.isAnimating, isTrue);

      expect(
        find.descendant(
          of: find.byType(NaviCompanion),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(state.isAnimating, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(state.isAnimating, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
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
          child: Scaffold(
            body: NaviCompanion(
              activity: CompanionActivity.speaking,
              holdPose: false,
              repeat: true,
              engaged: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<NaviCompanionState>(find.byType(NaviCompanion));
    expect(state.isAnimating, isFalse);
    expect(find.byTooltip('Pause Navi animation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows interactive checklist for errands and hides it for casual trips', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const NaviApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('companion-checklist-card')), findsNothing);

    container.read(journeyDraftProvider.notifier).setCompanionPrep(
      destination: 'MTN office, Ikeja',
      purposeSummary: 'SIM Registration & NIN',
      isCasual: false,
      checklist: const [
        'NIN slip or Virtual NIN (VNIN)',
        'Valid Government ID card',
      ],
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('companion-checklist-card')),
      findsOneWidget,
    );
    expect(find.text('0/2 ready'), findsOneWidget);

    await tester.ensureVisible(find.text('NIN slip or Virtual NIN (VNIN)'));
    await tester.tap(find.text('NIN slip or Virtual NIN (VNIN)'));
    await tester.pumpAndSettle();
    expect(find.text('1/2 ready'), findsOneWidget);

    // Casual trip must not enforce or display a checklist card.
    container.read(journeyDraftProvider.notifier).setCompanionPrep(
      destination: 'Yaba',
      purposeSummary: 'Visiting & Social Outing',
      isCasual: true,
      checklist: const ['Should never appear'],
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('companion-checklist-card')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
