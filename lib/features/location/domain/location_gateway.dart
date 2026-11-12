/// Platform-independent samples. Map SDK types stay in presentation adapters.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.receivedAt,
    required this.ageAtReceipt,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final Duration receivedAt;
  final Duration ageAtReceipt;

  Duration ageAt(Duration now) => ageAtReceipt + (now - receivedAt);
  Duration get measuredAt => receivedAt - ageAtReceipt;

  bool get isValid =>
      latitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude.isFinite &&
      longitude >= -180 &&
      longitude <= 180 &&
      accuracyMeters.isFinite &&
      accuracyMeters > 0 &&
      ageAtReceipt >= Duration.zero;
}

enum LocationAccess { precise, approximate, denied, deniedForever, servicesOff }

enum FixQuality { unavailable, usable, uncertain, stale }

/// Foreground display policy, not a navigation/arrival confidence decision.
class LocationQualityPolicy {
  const LocationQualityPolicy({
    this.maxAge = const Duration(seconds: 10),
    this.maxUncertaintyMeters = 50,
  });

  final Duration maxAge;
  final double maxUncertaintyMeters;

  FixQuality evaluate(
    LocationFix? fix,
    Duration now, {
    required bool approximate,
  }) {
    if (fix == null || !fix.isValid || now < fix.receivedAt) {
      return FixQuality.unavailable;
    }
    if (fix.ageAt(now) > maxAge) return FixQuality.stale;
    if (approximate || fix.accuracyMeters > maxUncertaintyMeters) {
      return FixQuality.uncertain;
    }
    return FixQuality.usable;
  }
}

abstract interface class LocationClock {
  Duration get elapsed;
  DateTime get utcNow;
}

abstract interface class LocationGateway {
  Future<LocationAccess> access({required bool requestPermission});
  Stream<LocationFix> watch();
  Stream<bool> serviceChanges();
  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}
