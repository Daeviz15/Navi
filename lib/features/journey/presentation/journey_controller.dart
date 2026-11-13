import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/journey_draft.dart';
import '../domain/journey_identity.dart';

/// Canonical owner of trip intent, preparation and planning/active lifecycle.
final journeyDraftProvider = NotifierProvider<JourneyController, JourneyDraft>(
  JourneyController.new,
);

class JourneyController extends Notifier<JourneyDraft> {
  int _tripSequence = 0;

  @override
  JourneyDraft build() => const JourneyDraft();

  void setDestination(String value) {
    final normalized = value.trim();
    if (state.destination.toLowerCase() == normalized.toLowerCase() &&
        normalized.isNotEmpty) {
      state = state.copyWith(destination: normalized);
      return;
    }
    state = JourneyDraft(
      identity: state.isActive
          ? JourneyIdentity(tripId: ++_tripSequence)
          : state.identity.nextIntent(),
      destination: normalized,
      travelMode: state.travelMode,
    );
  }

  void startTrip() {
    if (state.destination.trim().isEmpty || state.status == TripStatus.active) {
      return;
    }
    state = state.copyWith(status: TripStatus.active);
  }

  void switchTripDestination(
    String value, {
    String? purposeSummary,
    bool isCasual = false,
    List<String> checklist = const <String>[],
  }) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    final cleanPurposeSummary = purposeSummary?.trim() ?? '';
    final nextPurpose = isCasual
        ? JourneyPurpose.visit
        : (checklist.isNotEmpty
              ? JourneyPurpose.errand
              : JourneyPurpose.unspecified);
    state = JourneyDraft(
      identity: state.destination.toLowerCase() == normalized.toLowerCase()
          ? state.identity
          : state.identity.nextIntent(),
      destination: normalized,
      purpose: nextPurpose,
      travelMode: state.travelMode,
      purposeSummary: cleanPurposeSummary,
      isCasual: isCasual,
      checklist: List<String>.unmodifiable(checklist),
      checkedItems: const <String>{},
      status: TripStatus.active,
    );
  }

  void setPurpose(JourneyPurpose purpose) {
    state = state.copyWith(purpose: purpose);
  }

  void setCompanionPrep({
    String? destination,
    String? purposeSummary,
    required bool isCasual,
    required List<String> checklist,
  }) {
    final sameDestination =
        destination == null ||
        destination.trim().isEmpty ||
        destination.trim().toLowerCase() == state.destination.toLowerCase();
    final nextPurpose = isCasual
        ? JourneyPurpose.visit
        : (checklist.isNotEmpty ? JourneyPurpose.errand : state.purpose);
    state = state.copyWith(
      identity: sameDestination ? state.identity : state.identity.nextIntent(),
      destination: destination != null && destination.trim().isNotEmpty
          ? destination.trim()
          : state.destination,
      purpose: nextPurpose,
      purposeSummary:
          purposeSummary?.trim() ??
          (sameDestination ? state.purposeSummary : ''),
      isCasual: isCasual,
      checklist: List<String>.unmodifiable(checklist),
      checkedItems: sameDestination && !isCasual
          ? Set<String>.unmodifiable(
              state.checkedItems.where(checklist.contains),
            )
          : const <String>{},
    );
  }

  void toggleChecklistItem(String item) {
    final next = Set<String>.from(state.checkedItems);
    if (!next.remove(item)) {
      next.add(item);
    }
    state = state.copyWith(checkedItems: Set<String>.unmodifiable(next));
  }

  void setTravelMode(TravelMode mode) {
    if (mode == state.travelMode) return;
    state = state.copyWith(
      identity: state.identity.nextIntent(),
      travelMode: mode,
    );
  }

  void reset() =>
      state = JourneyDraft(identity: JourneyIdentity(tripId: ++_tripSequence));
}
