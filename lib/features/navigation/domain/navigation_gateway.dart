import 'dart:math' as math;

import '../../journey/domain/journey_draft.dart';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;

  double distanceTo(GeoPoint other) {
    const radians = math.pi / 180;
    final a =
        math.pow(math.sin((other.latitude - latitude) * radians / 2), 2) +
        math.cos(latitude * radians) *
            math.cos(other.latitude * radians) *
            math.pow(math.sin((other.longitude - longitude) * radians / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

class DestinationPlace {
  const DestinationPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.point,
  });
  final String id, name, address;
  final GeoPoint point;
}

class JourneyRoute {
  const JourneyRoute({
    required this.points,
    required this.origin,
    required this.mode,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.expiresAt,
  });
  final List<GeoPoint> points;
  final GeoPoint origin;
  final TravelMode mode;
  final double distanceMeters, durationSeconds;
  final DateTime expiresAt;
}

class NavigationFailure implements Exception {
  const NavigationFailure(this.code);
  final String code;

  String get message => switch (code) {
    'not_configured' ||
    'provider_not_configured' => 'Place search is not available yet.',
    'no_route' || 'bus_route_unavailable' =>
      'No verified route is available for this travel mode. You can try another mode.',
    'outside_service_area' =>
      'This journey is outside the supported Lagos area.',
    'unauthorized' => 'Map services could not connect. Please try again.',
    'rate_limited' || 'provider_rate_limited' =>
      'Too many map requests. Please try again shortly.',
    _ => 'Map services are unavailable right now. Please try again.',
  };
}

abstract interface class NavigationGateway {
  Future<List<DestinationPlace>> search(String query);
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  });
}

List<GeoPoint> decodeRoutePolyline(String encoded) {
  if (encoded.isEmpty || encoded.length > 150000) {
    throw const NavigationFailure('invalid_response');
  }
  int index = 0, latitude = 0, longitude = 0;
  int component() {
    int value = 0, shift = 0;
    while (true) {
      if (index >= encoded.length || shift > 30) {
        throw const NavigationFailure('invalid_response');
      }
      final byte = encoded.codeUnitAt(index++) - 63;
      if (byte < 0 || byte > 63) {
        throw const NavigationFailure('invalid_response');
      }
      value |= (byte & 31) << shift;
      if (byte < 32) break;
      shift += 5;
    }
    return (value & 1) != 0 ? ~(value >> 1) : value >> 1;
  }

  final points = <GeoPoint>[];
  while (index < encoded.length) {
    latitude += component();
    longitude += component();
    final point = GeoPoint(latitude / 1e5, longitude / 1e5);
    if (!point.isValid || points.length >= 20000) {
      throw const NavigationFailure('invalid_response');
    }
    points.add(point);
  }
  if (points.length < 2) throw const NavigationFailure('invalid_response');
  return List.unmodifiable(points);
}

/// Small moving overlay sampled by distance along actual provider geometry.
/// The static route stays unchanged; only this short highlight crosses the channel.
class RouteFlowSampler {
  RouteFlowSampler(this.points) {
    for (var i = 1; i < points.length; i++) {
      _distances.add(_distances.last + points[i - 1].distanceTo(points[i]));
    }
  }
  final List<GeoPoint> points;
  final _distances = <double>[0];

  GeoPoint _at(double fraction) {
    final target = fraction.clamp(0.0, 1.0) * _distances.last;
    int low = 0, high = _distances.length - 1;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (_distances[mid] <= target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final span = _distances[high] - _distances[low];
    final t = span <= 0 ? 0.0 : (target - _distances[low]) / span;
    return GeoPoint(
      points[low].latitude + (points[high].latitude - points[low].latitude) * t,
      points[low].longitude +
          (points[high].longitude - points[low].longitude) * t,
    );
  }

  List<GeoPoint> highlight(double progress) {
    final start = progress.clamp(0.0, 0.92);
    return [for (var i = 0; i <= 12; i++) _at(start + i * 0.08 / 12)];
  }
}
