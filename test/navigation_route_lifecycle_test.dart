import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/application/journey_transit_context_provider.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/application/navigation_controller.dart';
import 'package:navi/features/navigation/data/backend_navigation_gateway.dart';
import 'package:navi/features/navigation/data/reverse_geocoder.dart';
import 'package:navi/features/navigation/domain/destination_selection.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/navigation/domain/route_progress.dart';

GeoPoint p(double x, [double y = 0]) =>
    GeoPoint(6.52 + y / 111195, 3.37 + x / 110476);
final place = DestinationPlace(
  id: 'place',
  name: 'Destination',
  address: 'Lagos',
  point: p(1000),
);

void _routeTest(
  String name,
  Future<void> Function(WidgetTester, _Harness) run, {
  bool adopt = true,
}) {
  testWidgets(name, (tester) async {
    final h = _Harness();
    try {
      await h.start(tester, adopt: adopt);
      await run(tester, h);
    } finally {
      h.container.dispose();
      await tester.pump();
    }
  });
}

void main() {
  _routeTest(
    'active movement beyond 150 m keeps geometry without route calls',
    (tester, h) async {
      final original = h.state.route;
      for (final x in [100.0, 250.0, 400.0]) {
        await h.move(tester, x, after: const Duration(seconds: 10));
        expect(identical(h.state.route, original), isTrue);
        expect(h.state.progress.status, RouteProgressStatus.onRoute);
      }
      expect(h.gateway.calls, hasLength(1));
      expect(h.state.progress.remainingMeters, closeTo(600, 3));
    },
  );

  _routeTest(
    'active motion during first request does not reject a valid route',
    (tester, h) async {
      await h.move(tester, 200, after: const Duration(seconds: 10));
      h.complete(0);
      await h.flush(tester);
      expect(h.state.route, isNotNull);
      expect(h.state.progress.remainingMeters, closeTo(800, 3));
    },
    adopt: false,
  );

  _routeTest(
    'losing precision while a route is loading retains geometry without current progress',
    (tester, h) async {
      await h.move(tester, 200, accuracy: 100, quality: FixQuality.uncertain);
      h.complete(0);
      await h.flush(tester);
      expect(h.state.route, isNotNull);
      expect(h.state.progress.remainingMeters, isNull);
      await h.move(tester, 210);
      expect(h.state.progress.canReportRemaining, isTrue);
      expect(h.gateway.calls, hasLength(1));
    },
    adopt: false,
  );

  _routeTest(
    'five-minute expiry retains the path; suspended GPS causes no refresh',
    (tester, h) async {
      final original = h.state.route;
      h.location.suspend();
      await h.advance(tester, const Duration(minutes: 5));
      expect(identical(h.state.route, original), isTrue);
      expect(h.state.estimatesStale, isTrue);
      expect(h.state.progress.remainingMeters, isNull);
      expect(h.gateway.calls, hasLength(1));
      await h.move(tester, 200);
      expect(h.gateway.calls, hasLength(2));
      expect(h.state.refreshing, isTrue);
      expect(identical(h.state.route, original), isTrue);
      h.complete(1);
      await h.flush(tester);
      expect(h.state.estimatesStale, isFalse);
      expect(h.state.routeRevision, 2);
    },
  );

  _routeTest(
    'manual refresh shares a pending request and keeps the previous route',
    (tester, h) async {
      final original = h.state.route;
      await h.move(tester, 100, after: const Duration(seconds: 31));
      final pending = h.controller.plan();
      final repeated = h.controller.plan();
      expect(identical(pending, repeated), isTrue);
      await h.flush(tester);
      expect(h.gateway.calls, hasLength(2));
      expect(identical(h.state.route, original), isTrue);
      expect(h.state.refreshing, isTrue);
      await h.move(tester, 110);
      await h.move(tester, 120);
      expect(h.gateway.calls, hasLength(2));
      h.complete(1);
      await pending;
      expect(h.state.refreshing, isFalse);
      expect(h.state.progress.canReportRemaining, isTrue);
    },
  );

  _routeTest(
    'expiry during refresh remains visible and cannot start a second request',
    (tester, h) async {
      h.complete(0, ttl: const Duration(seconds: 40));
      await h.flush(tester);
      final original = h.state.route;
      await h.move(tester, 100, after: const Duration(seconds: 31));
      final pending = h.controller.plan();
      await h.flush(tester);
      await h.advance(tester, const Duration(seconds: 10));
      expect(h.state.estimatesStale, isTrue);
      expect(identical(h.state.route, original), isTrue);
      expect(h.gateway.calls, hasLength(2));
      h.complete(1);
      await pending;
      expect(h.state.estimatesStale, isFalse);
    },
    adopt: false,
  );

  _routeTest(
    'refresh failure preserves geometry and applies increasing backoff',
    (tester, h) async {
      final original = h.state.route;
      await h.move(tester, 100, after: const Duration(seconds: 31));
      var pending = h.controller.plan();
      await h.flush(tester);
      h.gateway.calls[1].result.completeError(
        const NavigationFailure('unavailable'),
      );
      await pending;
      expect(identical(h.state.route, original), isTrue);
      expect(h.state.message, contains('previous route remains'));
      expect(h.state.refreshAllowed, isFalse);
      await h.controller.plan();
      expect(h.gateway.calls, hasLength(2));
      await h.move(tester, 100, after: const Duration(seconds: 31));
      pending = h.controller.plan();
      await h.flush(tester);
      h.gateway.calls[2].result.completeError(
        const NavigationFailure('unavailable'),
      );
      await pending;
      await h.move(tester, 100, after: const Duration(seconds: 31));
      await h.controller.plan();
      expect(
        h.gateway.calls,
        hasLength(3),
      ); // Second failure backs off for 60 s.
      await h.move(tester, 100, after: const Duration(seconds: 30));
      pending = h.controller.plan();
      await h.flush(tester);
      expect(h.gateway.calls, hasLength(4));
      h.complete(3);
      await pending;
      expect(h.state.failureCode, isNull);
    },
  );

  _routeTest(
    'sustained deviation reroutes once; weak fixes cannot trigger it',
    (tester, h) async {
      await h.advance(tester, const Duration(seconds: 31));
      await h.move(tester, 100, y: 120, accuracy: 45);
      await h.move(
        tester,
        100,
        y: 120,
        accuracy: 45,
        after: const Duration(seconds: 3),
      );
      await h.move(
        tester,
        100,
        y: 120,
        accuracy: 45,
        after: const Duration(seconds: 3),
      );
      expect(h.gateway.calls, hasLength(1));
      await h.move(tester, 100, y: 120);
      await h.move(tester, 100, y: 120, after: const Duration(seconds: 3));
      expect(h.gateway.calls, hasLength(1));
      await h.move(tester, 100, y: 120, after: const Duration(seconds: 3));
      expect(h.state.progress.isOffRoute, isTrue);
      expect(h.state.progress.remainingMeters, isNull);
      expect(h.gateway.calls, hasLength(2));
      for (var i = 0; i < 4; i++) {
        await h.move(tester, 110, y: 120);
      }
      expect(h.gateway.calls, hasLength(2));
    },
  );

  _routeTest('old refresh cannot reappear after a destination change', (
    tester,
    h,
  ) async {
    await h.move(tester, 100, after: const Duration(seconds: 31));
    final pending = h.controller.plan();
    await h.flush(tester);
    h.container.read(journeyDraftProvider.notifier).setDestination('Yaba');
    await h.flush(tester);
    h.complete(1);
    await pending;
    expect(h.state.route, isNull);
    expect(h.state.selected, isNull);
    expect(h.state.refreshing, isFalse);
  });

  _routeTest(
    'voice uses the same progress and withholds unpositioned instructions and proportional ETA',
    (tester, h) async {
      await h.move(tester, 250, after: const Duration(seconds: 10));
      final context = h.container.read(journeyTransitContextProvider);
      expect(context.remainingDistanceMeters, h.state.progress.remainingMeters);
      expect(context.remainingDurationSeconds, isNull);
      expect(context.nextGuidanceSteps, isEmpty);
      expect(context.routeProgressStatus, RouteProgressStatus.onRoute);
      await h.move(tester, 260, accuracy: 45);
      final uncertain = h.container.read(journeyTransitContextProvider);
      expect(uncertain.remainingDistanceMeters, isNull);
      expect(uncertain.isOffRoute, isFalse);
      expect(h.state.route, isNotNull);
    },
  );

  _routeTest('invalid replacement cannot overwrite an existing route', (
    tester,
    h,
  ) async {
    final original = h.state.route;
    await h.move(tester, 100, after: const Duration(seconds: 31));
    final pending = h.controller.plan();
    await h.flush(tester);
    h.complete(1, points: [p(100), p(100)]);
    await pending;
    expect(identical(h.state.route, original), isTrue);
    expect(h.state.failureCode, 'invalid_response');
  });
}

class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        locationClockProvider.overrideWithValue(clock),
        locationControllerProvider.overrideWith(() => _Location(clock)),
        navigationGatewayProvider.overrideWith((ref) async => gateway),
        reverseGeocoderProvider.overrideWith((ref) async => null),
      ],
    );
    final journey = container.read(journeyDraftProvider.notifier);
    journey.setDestination('Destination');
    journey.startTrip();
    controller = container.read(navigationControllerProvider.notifier);
  }
  final clock = _Clock();
  final gateway = _Gateway();
  late final ProviderContainer container;
  late final NavigationController controller;
  NavigationState get state => container.read(navigationControllerProvider);
  _Location get location =>
      container.read(locationControllerProvider.notifier) as _Location;
  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<void> start(WidgetTester tester, {required bool adopt}) async {
    await flush(tester);
    controller.confirm(
      DestinationSelectionRequest(
        token: state.suggestions!.token,
        placeId: place.id,
        source: DestinationConfirmationSource.tap,
      ),
    );
    await flush(tester);
    if (adopt) {
      complete(0);
      await flush(tester);
    }
  }

  void complete(
    int index, {
    Duration ttl = const Duration(minutes: 5),
    List<GeoPoint>? points,
  }) {
    final call = gateway.calls[index];
    call.result.complete(
      JourneyRoute(
        points: points ?? [call.origin, place.point],
        origin: call.origin,
        mode: call.mode,
        kind: call.mode == TravelMode.bus
            ? RouteKind.busTransit
            : RouteKind.walking,
        distanceMeters: call.origin.distanceTo(place.point),
        durationSeconds: 500,
        expiresAt: clock.utcNow.add(ttl),
        stepHints: const [
          'Turn at the first junction',
          'Then take the next bus',
        ],
      ),
    );
  }

  Future<void> advance(WidgetTester tester, Duration delta) async {
    clock.elapsed += delta;
    await tester.pump(delta);
    await tester.pump();
  }

  Future<void> move(
    WidgetTester tester,
    double x, {
    double y = 0,
    double accuracy = 8,
    FixQuality quality = FixQuality.usable,
    Duration after = const Duration(seconds: 1),
  }) async {
    await advance(tester, after);
    location.move(p(x, y), accuracy, quality);
    await flush(tester);
  }
}

class _Clock implements LocationClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => DateTime.utc(2026, 11, 13).add(elapsed);
}

class _Location extends LocationController {
  _Location(this.clock);
  final _Clock clock;
  @override
  LocationState build() => _state(p(0), 8, FixQuality.usable);
  LocationState _state(GeoPoint point, double accuracy, FixQuality quality) =>
      LocationState(
        phase: LocationPhase.tracking,
        quality: quality,
        fix: LocationFix(
          latitude: point.latitude,
          longitude: point.longitude,
          accuracyMeters: accuracy,
          receivedAt: clock.elapsed,
          ageAtReceipt: Duration.zero,
        ),
      );
  void move(GeoPoint point, double accuracy, FixQuality quality) =>
      state = _state(point, accuracy, quality);
  void suspend() => state = const LocationState(phase: LocationPhase.suspended);
}

class _PendingRoute {
  _PendingRoute(this.origin, this.mode);
  final GeoPoint origin;
  final TravelMode mode;
  final result = Completer<JourneyRoute>();
}

class _Gateway implements NavigationGateway {
  final calls = <_PendingRoute>[];
  @override
  Future<List<DestinationPlace>> search(String query) async => [place];
  @override
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  }) {
    final call = _PendingRoute(origin, mode);
    calls.add(call);
    return call.result.future;
  }
}
