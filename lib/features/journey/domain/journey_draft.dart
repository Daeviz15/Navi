import 'journey_identity.dart';

enum JourneyPurpose { unspecified, visit, errand, directionsOnly }

enum TravelMode { bus, walking }

enum TripStatus { planning, active }

/// Immutable journey state: planning draft -> active transit until ended.
class JourneyDraft {
  const JourneyDraft({
    this.identity = const JourneyIdentity(tripId: 0),
    this.destination = '',
    this.purpose = JourneyPurpose.unspecified,
    this.travelMode = TravelMode.bus,
    this.purposeSummary = '',
    this.isCasual = false,
    this.checklist = const <String>[],
    this.checkedItems = const <String>{},
    this.status = TripStatus.planning,
  });

  final JourneyIdentity identity;
  final String destination;
  final JourneyPurpose purpose;
  final TravelMode travelMode;
  final String purposeSummary;
  final bool isCasual;
  final List<String> checklist;
  final Set<String> checkedItems;
  final TripStatus status;

  bool get isActive =>
      status == TripStatus.active && destination.trim().isNotEmpty;

  JourneyDraft copyWith({
    JourneyIdentity? identity,
    String? destination,
    JourneyPurpose? purpose,
    TravelMode? travelMode,
    String? purposeSummary,
    bool? isCasual,
    List<String>? checklist,
    Set<String>? checkedItems,
    TripStatus? status,
  }) => JourneyDraft(
    identity: identity ?? this.identity,
    destination: destination ?? this.destination,
    purpose: purpose ?? this.purpose,
    travelMode: travelMode ?? this.travelMode,
    purposeSummary: purposeSummary ?? this.purposeSummary,
    isCasual: isCasual ?? this.isCasual,
    checklist: checklist ?? this.checklist,
    checkedItems: checkedItems ?? this.checkedItems,
    status: status ?? this.status,
  );
}
