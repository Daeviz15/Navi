import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/app/navi_app.dart';
import 'package:navi/app/router.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/data/maps_configuration.dart';
import 'package:navi/features/voice/application/voice_dependencies.dart';

import 'support/fake_location_gateway.dart';
import 'support/voice_harness.dart';
import 'support/journey_test_frames.dart';

void main() {
  late FakeLocationGateway gateway;
  late ProviderContainer container;

  setUp(() {
    naviRouter.go('/');
    gateway = FakeLocationGateway();
    container = ProviderContainer(
      overrides: [
        voiceServicesProvider.overrideWithValue(silentVoiceServices()),
        locationGatewayProvider.overrideWithValue(gateway),
        mapsConfigurationProvider.overrideWith(
          (ref) async => MapsConfiguration.missing,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await gateway.close();
  });

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NaviApp()),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'MTN office, Ikeja');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    container.dispose();
  }

  testWidgets(
    'checks location once after the bus lap and shares acquisition with the map',
    (tester) async {
      gateway.pendingAccess = Completer<LocationAccess>();
      final journey = container.read(journeyDraftProvider.notifier);
      journey.setCompanionPrep(
        destination: 'MTN office, Ikeja',
        purposeSummary: 'SIM registration',
        isCasual: false,
        checklist: ['NIN slip', 'Valid ID'],
      );
      journey.toggleChecklistItem('NIN slip');
      await start(tester);
      expect(find.text('Getting ready'), findsOneWidget);
      expect(find.byKey(const ValueKey('journey-bus-orbit')), findsOneWidget);
      expect(find.text('NIN slip'), findsOneWidget);
      expect(gateway.permissionRequests, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(gateway.permissionRequests, [true]);
      expect(find.text('Finding our starting point…'), findsOneWidget);

      gateway.pendingAccess!.complete(LocationAccess.precise);
      await tester.pump();
      await tester.runAsync(flushVoice);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('journey-map-preview')), findsOneWidget);
      expect(gateway.watchCalls, 1);
      expect(gateway.permissionRequests, [true]);
      expect(
        container.read(locationControllerProvider).phase,
        LocationPhase.acquiring,
      );
      expect(container.read(journeyDraftProvider).checkedItems, {'NIN slip'});

      final clock = container.read(locationClockProvider);
      gateway.positions.add(
        LocationFix(
          latitude: 6.5244,
          longitude: 3.3792,
          accuracyMeters: 8,
          receivedAt: clock.elapsed,
          ageAtReceipt: Duration.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your current position'), findsOneWidget);
      await tester.tap(find.byTooltip('Map options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Your essentials'));
      await tester.pumpAndSettle();
      expect(find.text('Valid ID'), findsOneWidget);
      final checked = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('NIN slip'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checked.value, isTrue);
      await finish(tester);
    },
  );

  testWidgets(
    'declined location still opens the map without repeating purpose',
    (tester) async {
      await start(tester);
      expect(find.text('Travel light.'), findsOneWidget);
      expect(find.text('Your essentials'), findsNothing);
      await settleMapEntry(tester);
      expect(find.byKey(const ValueKey('journey-map-preview')), findsOneWidget);
      expect(find.text('Location access is off'), findsOneWidget);
      expect(find.text('What brings you there?'), findsNothing);
      expect(find.text('Enable location'), findsOneWidget);
      expect(gateway.permissionRequests, [true]);
      await finish(tester);
    },
  );

  testWidgets('returning home before completion never prompts location', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.byTooltip('Go back'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(gateway.permissionRequests, isEmpty);
    expect(find.textContaining('Where are we'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('late permission completion cannot reopen a cancelled journey', (
    tester,
  ) async {
    gateway.pendingAccess = Completer<LocationAccess>();
    await start(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(gateway.permissionRequests, [true]);
    naviRouter.go('/');
    await tester.pumpAndSettle();
    gateway.pendingAccess!.complete(LocationAccess.precise);
    await tester.pumpAndSettle();
    expect(find.textContaining('Where are we'), findsOneWidget);
    expect(gateway.positions.hasListener, isFalse);
    expect(gateway.watchCalls, 0);
    await finish(tester);
  });

  testWidgets('permission completion cannot activate a replacement draft', (
    tester,
  ) async {
    gateway.pendingAccess = Completer<LocationAccess>();
    await start(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(gateway.permissionRequests, [true]);
    final journey = container.read(journeyDraftProvider.notifier);
    journey.reset();
    journey.setDestination('Yaba');
    gateway.pendingAccess!.complete(LocationAccess.precise);
    await tester.pumpAndSettle();
    expect(container.read(journeyDraftProvider).isActive, isFalse);
    expect(naviRouter.routeInformationProvider.value.uri.path, '/initialize');
    await finish(tester);
  });

  testWidgets(
    'backgrounding pauses the introduction before asking permission',
    (tester) async {
      await start(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(gateway.permissionRequests, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleMapEntry(tester);
      expect(find.byKey(const ValueKey('journey-map-preview')), findsOneWidget);
      expect(gateway.permissionRequests, [true]);
      await finish(tester);
    },
  );

  testWidgets(
    'reduced motion skips the bus lap and system back keeps active trip until ended',
    (tester) async {
      gateway.result = LocationAccess.precise;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await start(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('journey-map-preview')), findsOneWidget);
      expect(gateway.permissionRequests, [true]);
      expect(gateway.positions.hasListener, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('active-trip-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('resume-map-button')), findsOneWidget);
      expect(gateway.positions.hasListener, isTrue);

      await tester.ensureVisible(
        find.byKey(const ValueKey('home-end-trip-button')),
      );
      await tester.tap(find.byKey(const ValueKey('home-end-trip-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Where are we'), findsOneWidget);
      expect(gateway.positions.hasListener, isFalse);
      await finish(tester);
    },
  );

  testWidgets('tapping End trip on the map resets the trip and returns home', (
    tester,
  ) async {
    gateway.result = LocationAccess.precise;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await start(tester);
    await tester.pumpAndSettle();
    expect(gateway.positions.hasListener, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('end-trip-button')));
    await tester.tap(find.byKey(const ValueKey('end-trip-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Where are we'), findsOneWidget);
    expect(gateway.positions.hasListener, isFalse);
    await finish(tester);
  });
}
