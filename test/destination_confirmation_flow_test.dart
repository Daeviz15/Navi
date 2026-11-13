import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/app/navi_app.dart';
import 'package:navi/app/router.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/application/destination_selection_commands.dart';
import 'package:navi/features/navigation/application/navigation_controller.dart';
import 'package:navi/features/navigation/data/backend_navigation_gateway.dart';
import 'package:navi/features/navigation/data/maps_configuration.dart';
import 'package:navi/features/navigation/data/reverse_geocoder.dart';
import 'package:navi/features/navigation/domain/destination_selection.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/voice/application/voice_dependencies.dart';
import 'package:navi/features/voice/application/voice_session_controller.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

import 'support/voice_harness.dart';

const _first = DestinationPlace(
  id: 'lekki',
  name: 'MTN Lekki',
  address: 'Admiralty Way, Lekki, Lagos',
  point: GeoPoint(6.45, 3.47),
);
const _second = DestinationPlace(
  id: 'ikeja',
  name: 'MTN Ikeja',
  address: 'Allen Avenue, Ikeja, Lagos',
  point: GeoPoint(6.6, 3.35),
);

void main() {
  late ProviderContainer container;
  late _Gateway gateway;
  late List<TestSpeech> speech;
  late List<TestVoiceOutput> output;
  late bool closed;
  late bool holdGuidance;
  setUp(() {
    closed = false;
    holdGuidance = false;
    speech = [];
    output = [];
    gateway = _Gateway();
    container = ProviderContainer(
      overrides: [
        locationControllerProvider.overrideWith(_Location.new),
        navigationGatewayProvider.overrideWith((ref) async => gateway),
        reverseGeocoderProvider.overrideWith((ref) async => null),
        mapsConfigurationProvider.overrideWith(
          (ref) async => MapsConfiguration.missing,
        ),
        voiceServicesProvider.overrideWith(
          (ref) => VoiceServices(
            microphone: () => TestMicrophone(true, null, null),
            speech: () {
              final engine = TestSpeech(null);
              speech.add(engine);
              return engine;
            },
            output: () {
              final engine = _GuidedVoiceOutput(hold: holdGuidance);
              output.add(engine);
              return engine;
            },
            reasoner: QueueReasoner([]),
            destinations: RiverpodDestinationSelectionCommands(ref),
          ),
        ),
      ],
    );
    final journey = container.read(journeyDraftProvider.notifier);
    journey.setCompanionPrep(
      destination: 'MTN office',
      purposeSummary: 'SIM replacement',
      isCasual: false,
      checklist: ['ID'],
    );
    journey.startTrip();
    naviRouter.go('/preview');
  });

  Future<void> finish(WidgetTester tester) async {
    if (!closed) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(flushVoice);
      container.dispose();
      await tester.runAsync(flushVoice);
      await tester.pumpAndSettle();
      closed = true;
      naviRouter.go('/');
    }
  }

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    addTearDown(() => finish(tester));
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const NaviApp()),
    );
    await tester.pump();
    await tester.runAsync(flushVoice);
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets(
    'leaving the screen cancels an announcement without provider mutation during disposal',
    (tester) async {
      holdGuidance = true;
      await mount(tester, settle: false);
      expect(output.single.messages, hasLength(1));
      expect(container.read(voiceSessionProvider).enabled, isFalse);
      expect(speech, isEmpty);
      await finish(tester);
      expect(output.single.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'matching addresses require a tap before the destination and route appear',
    (tester) async {
      await mount(tester);
      expect(find.text('Confirm the exact place'), findsOneWidget);
      expect(find.text('Confirmed destination'), findsNothing);
      expect(container.read(navigationControllerProvider).selected, isNull);
      expect(gateway.destinations, isEmpty);
      expect(
        find.text('Confirm the exact place').hitTestable(),
        findsOneWidget,
      );
      final page = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('journey-map-preview')),
      );
      expect(page.controller!.offset, greaterThan(0));
      expect(speech, isEmpty);
      expect(container.read(voiceSessionProvider).enabled, isFalse);
      expect(output.expand((o) => o.messages), hasLength(1));
      final choice = find.byKey(const ValueKey('confirm-destination-ikeja'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
        container.read(navigationControllerProvider).selected!.id,
        _second.id,
      );
      expect(
        container
            .read(navigationControllerProvider)
            .confirmation!
            .evidence
            .source,
        DestinationConfirmationSource.tap,
      );
      expect(gateway.destinations, [_second.id]);
      expect(find.text('Confirmed destination'), findsOneWidget);
      final mapRect = tester.getRect(
        find.byKey(const ValueKey('boxed-journey-map')),
      );
      expect(mapRect.top, greaterThanOrEqualTo(0));
      expect(
        mapRect.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height),
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'tapped Navi confirms a spoken option through the same navigation owner',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('destination-navi-control')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(container.read(voiceSessionProvider).phase, VoicePhase.listening);
      await tester.runAsync(() async {
        speech.last.emit(const UtteranceEnded('option two'));
        await flushVoice();
      });
      await tester.pump();
      expect(container.read(voiceSessionProvider).failure, isNull);
      expect(
        container.read(voiceSessionProvider).reply,
        contains(_second.address),
      );
      expect(output.last.messages.last, contains(_second.address));
      expect(gateway.destinations, isEmpty);
      await tester.runAsync(() async {
        output.last.finish();
        await flushVoice();
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        speech.last.emit(const UtteranceEnded('yes that is the one'));
        await flushVoice();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(navigationControllerProvider).selected!.id,
        _second.id,
      );
      expect(
        container
            .read(navigationControllerProvider)
            .confirmation!
            .evidence
            .source,
        DestinationConfirmationSource.voice,
      );
      expect(gateway.destinations, [_second.id]);
      await tester.runAsync(() async {
        output.last.finish();
        await flushVoice();
      });
      await tester.pumpAndSettle();
      expect(container.read(voiceSessionProvider).enabled, isFalse);
      expect(find.text('Confirmed destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'an open picker cannot confirm its old addresses after a destination edit',
    (tester) async {
      await mount(tester);
      final first = find.byKey(const ValueKey('confirm-destination-lekki'));
      await tester.ensureVisible(first);
      await tester.tap(first);
      await tester.pumpAndSettle();
      final change = find.text('Change spot (2)');
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      container.read(journeyDraftProvider.notifier).setDestination('Yaba');
      await tester.pumpAndSettle();
      final old = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(_second.name),
      );
      await tester.tap(old);
      await tester.pumpAndSettle();
      expect(container.read(navigationControllerProvider).selected, isNull);
      expect(gateway.destinations, [_first.id]);
      expect(find.text('Confirmed destination'), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'a query can be refined without accepting an incorrect suggestion',
    (tester) async {
      await mount(tester);
      final refine = find.byKey(const ValueKey('refine-map-destination'));
      await tester.ensureVisible(refine);
      await tester.tap(refine);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'MTN office Allen Avenue',
      );
      await tester.tap(find.text('Find places'));
      await tester.pump();
      await tester.runAsync(flushVoice);
      await tester.pumpAndSettle();
      final draft = container.read(journeyDraftProvider);
      expect(draft.destination, 'MTN office Allen Avenue');
      expect(draft.checklist, isEmpty);
      expect(container.read(navigationControllerProvider).selected, isNull);
      expect(gateway.destinations, isEmpty);
      expect(find.text('Confirmed destination'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('a stale refinement dialog cannot overwrite a newer journey', (
    tester,
  ) async {
    await mount(tester);
    final refine = find.byKey(const ValueKey('refine-map-destination'));
    await tester.ensureVisible(refine);
    await tester.tap(refine);
    await tester.pumpAndSettle();
    final journey = container.read(journeyDraftProvider.notifier);
    journey.reset();
    journey.setDestination('Yaba');
    await tester.enterText(find.byType(TextFormField), 'Old address');
    await tester.tap(find.text('Find places'));
    await tester.pumpAndSettle();
    expect(container.read(journeyDraftProvider).destination, 'Yaba');
    expect(container.read(navigationControllerProvider).selected, isNull);
    expect(gateway.destinations, isEmpty);
    await finish(tester);
  });
  testWidgets(
    'late matches do not take scrolling away from an exploring user',
    (tester) async {
      gateway.searchGate = Completer<List<DestinationPlace>>();
      await mount(tester, settle: false);
      await tester.drag(
        find.byKey(const ValueKey('journey-map-preview')),
        const Offset(0, -180),
      );
      await tester.pump(const Duration(seconds: 1));
      final page = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('journey-map-preview')),
      );
      final offset = page.controller!.offset;
      gateway.searchGate!.complete([_first, _second]);
      await tester.pump();
      await tester.runAsync(flushVoice);
      await tester.pumpAndSettle();
      expect(page.controller!.offset, closeTo(offset, 1));
      expect(container.read(navigationControllerProvider).selected, isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'reduced motion still brings choices into view without animated scrolling',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await mount(tester);
      expect(
        find.text('Confirm the exact place').hitTestable(),
        findsOneWidget,
      );
      final page = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('journey-map-preview')),
      );
      final offset = page.controller!.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(page.controller!.offset, offset);
      expect(output.expand((o) => o.messages), hasLength(1));
      expect(speech, isEmpty);
      await finish(tester);
    },
  );
}

class _Gateway implements NavigationGateway {
  final destinations = <String>[];
  Completer<List<DestinationPlace>>? searchGate;
  @override
  Future<List<DestinationPlace>> search(String query) async =>
      searchGate?.future ?? [_first, _second];
  @override
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  }) async {
    destinations.add(destination.id);
    return JourneyRoute(
      points: [origin, destination.point],
      origin: origin,
      mode: mode,
      distanceMeters: 2000,
      durationSeconds: 500,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }
}

class _GuidedVoiceOutput extends TestVoiceOutput {
  _GuidedVoiceOutput({this.hold = false}) : super(null);
  final bool hold;

  @override
  Future<void> speak(String message, {required int id}) {
    final done = super.speak(message, id: id);
    if (message.startsWith('Let’s confirm the exact destination.')) {
      started();
      if (!hold) finish();
    }
    return done;
  }
}

class _Location extends LocationController {
  @override
  LocationState build() => const LocationState(
    phase: LocationPhase.tracking,
    quality: FixQuality.usable,
    fix: LocationFix(
      latitude: 6.52,
      longitude: 3.37,
      accuracyMeters: 8,
      receivedAt: Duration.zero,
      ageAtReceipt: Duration.zero,
    ),
  );
}
