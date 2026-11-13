import 'dart:math' as math;
import '../../journey/domain/journey_draft.dart';
import '../../location/domain/location_gateway.dart';
import 'geo_point.dart';
import 'route_geometry.dart';

enum RouteProgressStatus {
  unavailable,
  ambiguous,
  onRoute,
  deviating,
  offRoute,
  recovering,
}

class RouteProgress {
  const RouteProgress({
    this.status = RouteProgressStatus.unavailable,
    this.projection,
    this.remainingMeters,
  });
  final RouteProgressStatus status;
  final RouteProjection? projection;
  final double? remainingMeters;
  bool get canReportRemaining =>
      status == RouteProgressStatus.onRoute && remainingMeters != null;
  bool get isOffRoute => status == RouteProgressStatus.offRoute;
  String get caption => switch (status) {
    RouteProgressStatus.onRoute =>
      'About ${formatRouteDistance(remainingMeters!)} left on route',
    RouteProgressStatus.unavailable =>
      'Route shown. Waiting for a reliable position.',
    RouteProgressStatus.ambiguous =>
      'Route shown. Confirming your position on it.',
    RouteProgressStatus.deviating =>
      'Checking your position against the route.',
    RouteProgressStatus.offRoute =>
      'Your recent positions appear away from this route.',
    RouteProgressStatus.recovering =>
      'Checking that you are back on the route.',
  };
}

/// Provisional matching thresholds, separate from display accuracy and arrival
/// alerts. Device/corridor trials must calibrate them before enabling alerts.
class RouteProgressPolicy {
  const RouteProgressPolicy({
    this.maxAge = const Duration(seconds: 10),
    this.maxAccuracyMeters = 30,
    this.evidenceGap = const Duration(seconds: 8),
    this.offRouteDuration = const Duration(seconds: 6),
    this.offRouteSamples = 3,
    this.recoverySamples = 2,
    this.minOffRouteMeters = 60,
    this.ambiguityOffsetMeters = 40,
  });
  final Duration maxAge, evidenceGap, offRouteDuration;
  final double maxAccuracyMeters, minOffRouteMeters, ambiguityOffsetMeters;
  final int offRouteSamples, recoverySamples;
  bool accepts(LocationFix? fix, Duration now, {required bool usable}) =>
      usable &&
      fix != null &&
      fix.isValid &&
      now >= fix.receivedAt &&
      fix.ageAt(now) <= maxAge &&
      fix.accuracyMeters <= maxAccuracyMeters;
}

/// One engine per geometry, owned by the route controller. Immutable results
/// are published in Riverpod; widgets and voice never run their own projection.
class RouteProgressTracker {
  RouteProgressTracker({
    required this.geometry,
    required this.routeDistanceMeters,
    required this.mode,
    this.policy = const RouteProgressPolicy(),
  });
  final RouteGeometry geometry;
  final double routeDistanceMeters;
  final TravelMode mode;
  final RouteProgressPolicy policy;
  RouteProgress _state = const RouteProgress();
  RouteProjection? _anchor;
  LocationFix? _anchorFix;
  Duration? _lastSample, _offSince;
  int _offSamples = 0, _recoverySamples = 0;
  bool _confirmedOffRoute = false;

  RouteProgress update(LocationFix? fix, Duration now, {required bool usable}) {
    if (!geometry.isUsable ||
        !routeDistanceMeters.isFinite ||
        routeDistanceMeters <= 0 ||
        !policy.accepts(fix, now, usable: usable)) {
      _clearDeviation();
      return _state = const RouteProgress();
    }
    fix = fix!;
    if (_lastSample != null && fix.measuredAt <= _lastSample!) return _state;
    if (_lastSample != null &&
        fix.measuredAt - _lastSample! > policy.evidenceGap) {
      _clearDeviation();
    }
    _lastSample = fix.measuredAt;
    final candidates = geometry.project(GeoPoint(fix.latitude, fix.longitude));
    if (candidates.isEmpty) return _state = const RouteProgress();
    RouteProjection nearest(List<RouteProjection> values) => values.reduce(
      (best, next) => next.distanceMeters < best.distanceMeters ? next : best,
    );
    final global = nearest(candidates);
    final offDistance = math.max(
      policy.minOffRouteMeters,
      fix.accuracyMeters * 3,
    );
    if (global.distanceMeters > offDistance) {
      _recoverySamples = 0;
      _offSince ??= fix.measuredAt;
      _offSamples++;
      if (_offSamples >= policy.offRouteSamples &&
          fix.measuredAt - _offSince! >= policy.offRouteDuration) {
        _confirmedOffRoute = true;
      }
      return _state = RouteProgress(
        status: _confirmedOffRoute
            ? RouteProgressStatus.offRoute
            : RouteProgressStatus.deviating,
        projection: global,
      );
    }
    _offSince = null;
    _offSamples = 0;
    final elapsed = _anchorFix == null
        ? null
        : fix.measuredAt - _anchorFix!.measuredAt;
    var plausible = candidates;
    if (_anchor != null && elapsed != null) {
      final speedLimit = mode == TravelMode.walking ? 5.0 : 35.0;
      final travelBudget =
          speedLimit * elapsed.inMilliseconds / 1000 +
          fix.accuracyMeters +
          _anchorFix!.accuracyMeters +
          15;
      plausible = candidates
          .where(
            (p) =>
                (p.offsetMeters - _anchor!.offsetMeters).abs() <= travelBudget,
          )
          .toList();
    }
    if (plausible.isEmpty) return _uncertain();
    final best = nearest(plausible);
    final margin = math.max(6.0, fix.accuracyMeters);
    final ambiguous = plausible.any(
      (p) =>
          (p.offsetMeters - best.offsetMeters).abs() >
              policy.ambiguityOffsetMeters &&
          p.distanceMeters <= best.distanceMeters + margin,
    );
    if (ambiguous ||
        best.distanceMeters > math.max(20, fix.accuracyMeters * 2) ||
        best.distanceMeters - global.distanceMeters > margin) {
      return _uncertain();
    }
    if (_confirmedOffRoute && ++_recoverySamples < policy.recoverySamples) {
      return _state = RouteProgress(
        status: RouteProgressStatus.recovering,
        projection: best,
      );
    }
    _clearDeviation();
    _anchor = best;
    _anchorFix = fix;
    final remaining =
        (1 - best.offsetMeters / geometry.lengthMeters).clamp(0.0, 1.0) *
        routeDistanceMeters;
    return _state = RouteProgress(
      status: RouteProgressStatus.onRoute,
      projection: best,
      remainingMeters: remaining,
    );
  }

  RouteProgress _uncertain() {
    _recoverySamples = 0;
    return _state = const RouteProgress(status: RouteProgressStatus.ambiguous);
  }

  void _clearDeviation() {
    _offSince = null;
    _offSamples = 0;
    _recoverySamples = 0;
    _confirmedOffRoute = false;
  }
}
