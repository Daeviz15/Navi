import 'package:geolocator/geolocator.dart';

import '../domain/location_gateway.dart';

class MonotonicLocationClock implements LocationClock {
  final _watch = Stopwatch()..start();
  final _anchor = DateTime.now().toUtc();

  @override
  Duration get elapsed => _watch.elapsed;

  @override
  DateTime get utcNow => _anchor.add(elapsed);
}

class GeolocatorLocationGateway implements LocationGateway {
  const GeolocatorLocationGateway(this.clock);
  final LocationClock clock;

  @override
  Future<LocationAccess> access({required bool requestPermission}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.servicesOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationAccess.deniedForever;
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return LocationAccess.denied;
    }
    final accuracy = await Geolocator.getLocationAccuracy();
    return accuracy == LocationAccuracyStatus.reduced
        ? LocationAccess.approximate
        : LocationAccess.precise;
  }

  @override
  Stream<LocationFix> watch() {
    // No background service or cached last-known position in this milestone.
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 2),
    );
    return Geolocator.getPositionStream(locationSettings: settings).map((p) {
      var age = clock.utcNow.difference(p.timestamp.toUtc());
      // Permit small timestamp/dispatch jitter, but reject future-dated samples.
      if (age.isNegative && age >= const Duration(seconds: -2)) {
        age = Duration.zero;
      }
      return LocationFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        receivedAt: clock.elapsed,
        ageAtReceipt: age,
      );
    });
  }

  @override
  Stream<bool> serviceChanges() => Geolocator.getServiceStatusStream().map(
    (status) => status == ServiceStatus.enabled,
  );

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
