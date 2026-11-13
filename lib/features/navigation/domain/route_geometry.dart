import 'dart:math' as math;
import 'geo_point.dart';

class RouteProjection {
  const RouteProjection({
    required this.segment,
    required this.fraction,
    required this.offsetMeters,
    required this.distanceMeters,
  });
  final int segment;
  final double fraction, offsetMeters, distanceMeters;
}

/// Precomputed once per route. Local tangent-plane projection estimates route
/// progress; it does not verify the road/lane or a bus stop.
class RouteGeometry {
  RouteGeometry(List<GeoPoint> points) : points = List.unmodifiable(points) {
    for (var i = 1; i < points.length; i++) {
      _offsets.add(_offsets.last + points[i - 1].distanceTo(points[i]));
    }
  }
  final List<GeoPoint> points;
  final _offsets = <double>[0];
  double get lengthMeters => _offsets.last;
  late final bool isUsable =
      points.length >= 2 &&
      points.every((p) => p.isValid) &&
      lengthMeters.isFinite &&
      lengthMeters > 1;
  List<RouteProjection> project(GeoPoint point) {
    if (!isUsable || !point.isValid) return const [];
    const metersPerDegree = 6371000 * math.pi / 180;
    final cosLat = math.cos(point.latitude * math.pi / 180);
    final result = <RouteProjection>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final x = (b.longitude - a.longitude) * cosLat;
      final y = b.latitude - a.latitude;
      final px = (point.longitude - a.longitude) * cosLat;
      final py = point.latitude - a.latitude;
      final lengthSquared = x * x + y * y;
      if (lengthSquared <= 0) continue;
      final t = ((px * x + py * y) / lengthSquared).clamp(0.0, 1.0);
      final dx = px - x * t, dy = py - y * t;
      result.add(
        RouteProjection(
          segment: i,
          fraction: t,
          offsetMeters: _offsets[i] + (_offsets[i + 1] - _offsets[i]) * t,
          distanceMeters: math.sqrt(dx * dx + dy * dy) * metersPerDegree,
        ),
      );
    }
    return result;
  }
}

String formatRouteDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
