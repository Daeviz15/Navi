import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/navigation/domain/route_geometry.dart';
import 'package:navi/features/navigation/domain/route_progress.dart';

// Metre-scale synthetic Lagos geometry keeps expected movements easy to audit.
GeoPoint p(double x, [double y = 0]) =>
    GeoPoint(6.52 + y / 111195, 3.37 + x / 110476);
LocationFix fix(double x, double y, int seconds, {double accuracy = 8}) =>
    LocationFix(
      latitude: p(x, y).latitude,
      longitude: p(x, y).longitude,
      accuracyMeters: accuracy,
      receivedAt: Duration(seconds: seconds),
      ageAtReceipt: Duration.zero,
    );
RouteProgressTracker tracker(
  List<GeoPoint> points, {
  TravelMode mode = TravelMode.bus,
}) => RouteProgressTracker(
  geometry: RouteGeometry(points),
  routeDistanceMeters: 1000,
  mode: mode,
);
RouteProgress at(
  RouteProgressTracker engine,
  double x,
  double y,
  int seconds, {
  double accuracy = 8,
  bool usable = true,
}) => engine.update(
  fix(x, y, seconds, accuracy: accuracy),
  Duration(seconds: seconds),
  usable: usable,
);

void main() {
  test('sparse segments match their middle, not just their vertices', () {
    final engine = tracker([p(0), p(1000)]);
    final progress = at(engine, 500, 0, 0);
    expect(progress.status, RouteProgressStatus.onRoute);
    expect(progress.projection!.distanceMeters, closeTo(0, .1));
    expect(progress.remainingMeters, closeTo(500, 1));
  });

  test('progress uses bends and allows genuine backtracking', () {
    final engine = tracker([p(0), p(500), p(500, 500)]);
    expect(at(engine, 450, 0, 0).remainingMeters, closeTo(550, 2));
    expect(at(engine, 500, 50, 4).remainingMeters, closeTo(450, 2));
    expect(at(engine, 480, 0, 8).remainingMeters, closeTo(520, 2));
  });

  test('one noisy deviation is not an off-route decision', () {
    final engine = tracker([p(0), p(1000)]);
    at(engine, 100, 0, 0);
    final noise = at(engine, 100, 100, 1);
    expect(noise.status, RouteProgressStatus.deviating);
    expect(noise.remainingMeters, isNull);
    expect(at(engine, 120, 0, 2).status, RouteProgressStatus.onRoute);
  });

  test(
    'deviation requires distinct fresh samples over time; duplicate ticks do not count',
    () {
      final engine = tracker([p(0), p(1000)]);
      expect(at(engine, 100, 100, 0).isOffRoute, isFalse);
      for (var i = 0; i < 5; i++) {
        expect(
          engine
              .update(
                fix(100, 100, 0),
                const Duration(seconds: 6),
                usable: true,
              )
              .isOffRoute,
          isFalse,
        );
      }
      expect(at(engine, 100, 100, 3).isOffRoute, isFalse);
      expect(at(engine, 100, 100, 6).isOffRoute, isTrue);
      expect(
        engine
            .update(fix(100, 100, 2), const Duration(seconds: 6), usable: true)
            .isOffRoute,
        isTrue,
      );
    },
  );

  test('bad accuracy, stale fixes and long gaps break deviation evidence', () {
    for (final bad in ['accuracy', 'stale', 'gap']) {
      final engine = tracker([p(0), p(1000)]);
      at(engine, 100, 100, 0);
      at(engine, 100, 100, 3);
      if (bad == 'accuracy') at(engine, 100, 100, 4, accuracy: 45);
      if (bad == 'stale') {
        engine.update(
          fix(100, 100, 3),
          const Duration(seconds: 14),
          usable: true,
        );
      }
      final t = bad == 'gap' || bad == 'stale' ? 15 : 6;
      expect(at(engine, 100, 100, t).isOffRoute, isFalse, reason: bad);
    }
  });

  test('poor GPS withholds remaining distance and any off-route claim', () {
    final engine = tracker([p(0), p(1000)]);
    at(engine, 500, 0, 0);
    expect(at(engine, 500, 0, 1, accuracy: 40).remainingMeters, isNull);
    expect(
      at(engine, 500, 0, 2, usable: false).status,
      RouteProgressStatus.unavailable,
    );
    expect(
      engine
          .update(fix(500, 0, 2), const Duration(seconds: 13), usable: true)
          .remainingMeters,
      isNull,
    );
  });

  test(
    'recovery needs consecutive usable matches after confirmed deviation',
    () {
      final engine = tracker([p(0), p(1000)]);
      at(engine, 100, 100, 0);
      at(engine, 100, 100, 3);
      expect(at(engine, 100, 100, 6).isOffRoute, isTrue);
      expect(at(engine, 100, 0, 7).status, RouteProgressStatus.recovering);
      expect(at(engine, 110, 0, 8).status, RouteProgressStatus.onRoute);
    },
  );

  test(
    'no-history crossing is ambiguous; recent approach selects the local branch',
    () {
      final points = [p(-200), p(200), p(200, 200), p(0, 200), p(0, -200)];
      expect(
        at(tracker(points), 0, 0, 0).status,
        RouteProgressStatus.ambiguous,
      );
      final engine = tracker(points);
      expect(at(engine, -100, 0, 0).status, RouteProgressStatus.onRoute);
      final progress = at(engine, 0, 0, 4);
      expect(progress.status, RouteProgressStatus.onRoute);
      expect(progress.projection!.segment, 0);
    },
  );

  test('parallel return road does not create a forward jump', () {
    final engine = tracker([p(0), p(1000), p(1000, 20), p(0, 20)]);
    at(engine, 100, 0, 0);
    final progress = at(engine, 100, 20, 1);
    expect(progress.status, RouteProgressStatus.ambiguous);
    expect(progress.remainingMeters, isNull);
    expect(at(engine, 110, 0, 2).projection!.segment, 0);
  });

  test(
    'walking cannot teleport forward; fresh unambiguous reacquisition can recover',
    () {
      final engine = tracker([p(0), p(1000)], mode: TravelMode.walking);
      at(engine, 0, 0, 0);
      expect(at(engine, 800, 0, 1).canReportRemaining, isFalse);
      expect(at(engine, 800, 0, 25).canReportRemaining, isFalse);
      expect(at(engine, 800, 0, 200).remainingMeters, closeTo(200, 1));
    },
  );

  test('off-route positions never become straight-line remaining distance', () {
    final engine = tracker([p(0), p(500), p(500, 500)]);
    final progress = at(engine, 1000, 500, 0);
    expect(progress.remainingMeters, isNull);
    expect(progress.canReportRemaining, isFalse);
  });

  test(
    'zero-length geometry is unavailable and route inputs are immutable',
    () {
      expect(
        at(tracker([p(0), p(0)]), 0, 0, 0).status,
        RouteProgressStatus.unavailable,
      );
      final points = [p(0), p(1000)];
      final route = JourneyRoute(
        points: points,
        origin: points.first,
        mode: TravelMode.bus,
        kind: RouteKind.busTransit,
        distanceMeters: 1000,
        durationSeconds: 300,
        expiresAt: DateTime.now(),
      );
      points.clear();
      expect(route.points, hasLength(2));
      expect(identical(route.geometry, route.geometry), isTrue);
      expect(() => route.points.clear(), throwsUnsupportedError);
    },
  );
}
