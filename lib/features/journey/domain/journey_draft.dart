enum JourneyPurpose { unspecified, visit, errand, directionsOnly }

enum TravelMode { bus, walking }

/// Immutable local draft. This is NOT a routed or geocoded journey yet.
class JourneyDraft {
  const JourneyDraft({
    this.destination = '',
    this.purpose = JourneyPurpose.unspecified,
    this.travelMode = TravelMode.bus,
    this.purposeSummary = '',
    this.isCasual = false,
    this.checklist = const <String>[],
    this.checkedItems = const <String>{},
  });

  final String destination;
  final JourneyPurpose purpose;
  final TravelMode travelMode;
  final String purposeSummary;
  final bool isCasual;
  final List<String> checklist;
  final Set<String> checkedItems;

  JourneyDraft copyWith({
    String? destination,
    JourneyPurpose? purpose,
    TravelMode? travelMode,
    String? purposeSummary,
    bool? isCasual,
    List<String>? checklist,
    Set<String>? checkedItems,
  }) => JourneyDraft(
    destination: destination ?? this.destination,
    purpose: purpose ?? this.purpose,
    travelMode: travelMode ?? this.travelMode,
    purposeSummary: purposeSummary ?? this.purposeSummary,
    isCasual: isCasual ?? this.isCasual,
    checklist: checklist ?? this.checklist,
    checkedItems: checkedItems ?? this.checkedItems,
  );
}
