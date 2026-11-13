import 'dart:math' as math;

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
