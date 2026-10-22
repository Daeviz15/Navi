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
    state = JourneyDraft(destination: normalized);
  }

  void setPurpose(JourneyPurpose purpose) {
    state = state.copyWith(purpose: purpose);
  }

  void setTravelMode(TravelMode mode) {
    state = state.copyWith(travelMode: mode);
  }

  void reset() => state = const JourneyDraft();
}
