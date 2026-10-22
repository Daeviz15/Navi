enum JourneyPurpose { unspecified, visit, errand, directionsOnly }

enum TravelMode { bus, walking }

/// Immutable local draft. This is NOT a routed or geocoded journey yet.
class JourneyDraft {
  const JourneyDraft({
    this.destination = '',
    this.purpose = JourneyPurpose.unspecified,
    this.travelMode = TravelMode.bus,
  });

  final String destination;
  final JourneyPurpose purpose;
  final TravelMode travelMode;

  JourneyDraft copyWith({
    String? destination,
    JourneyPurpose? purpose,
    TravelMode? travelMode,
  }) => JourneyDraft(
    destination: destination ?? this.destination,
    purpose: purpose ?? this.purpose,
    travelMode: travelMode ?? this.travelMode,
  );
}
