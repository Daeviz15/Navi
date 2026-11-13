import '../../location/domain/location_gateway.dart';
import 'geo_point.dart';

enum AreaStatus {
  unavailable,
  locating,
  current,
  stale,
  uncertain,
  lookupFailed,
}

class AreaObservation {
  const AreaObservation({
    required this.label,
    required this.sourceFix,
    required this.lookedUpAt,
  });
  final String label;
  final LocationFix sourceFix;
  final Duration lookedUpAt;
}

class CurrentAreaState {
  const CurrentAreaState(this.status, {this.observation});
  final AreaStatus status;
  final AreaObservation? observation;
  String? get currentLabel =>
      status == AreaStatus.current ? observation?.label : null;
}

/// Street labels need stronger evidence than the map's approximate-position dot.
/// These pilot limits do not establish a bus stop, a turn, or arrival.
class AreaConfidencePolicy {
  const AreaConfidencePolicy();
  static const maxObservationAge = Duration(seconds: 90);
  static const maxFixAge = Duration(seconds: 10);

  bool acceptsFix(
    LocationFix? fix,
    Duration now, {
    required bool approximate,
  }) =>
      fix != null &&
      fix.isValid &&
      !approximate &&
      fix.accuracyMeters <= 30 &&
      now >= fix.receivedAt &&
      fix.ageAt(now) <= maxFixAge;

  bool acceptsObservation(
    AreaObservation observation,
    LocationFix fix,
    Duration now,
  ) =>
      now >= observation.lookedUpAt &&
      now - observation.lookedUpAt <= maxObservationAge &&
      GeoPoint(fix.latitude, fix.longitude).distanceTo(
                GeoPoint(
                  observation.sourceFix.latitude,
                  observation.sourceFix.longitude,
                ),
              ) +
              fix.accuracyMeters +
              observation.sourceFix.accuracyMeters <=
          100;
}
