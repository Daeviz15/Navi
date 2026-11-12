import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/journey_draft.dart';

/// A simple view model for the draft before routing/permissions are added.
final journeyDraftProvider = NotifierProvider<JourneyController, JourneyDraft>(
  JourneyController.new,
);

class JourneyController extends Notifier<JourneyDraft> {
  @override
  JourneyDraft build() => const JourneyDraft();

  void setDestination(String value) {
    final normalized = value.trim();
    if (state.destination.toLowerCase() == normalized.toLowerCase() &&
        normalized.isNotEmpty) {
      state = state.copyWith(destination: normalized);
      return;
    }
    state = JourneyDraft(destination: normalized);
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
        destination.trim().toLowerCase() == state.destination.toLowerCase();
    final nextPurpose = isCasual
        ? JourneyPurpose.visit
        : (checklist.isNotEmpty ? JourneyPurpose.errand : state.purpose);
    state = state.copyWith(
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
    state = state.copyWith(travelMode: mode);
  }

  void reset() => state = const JourneyDraft();
}
