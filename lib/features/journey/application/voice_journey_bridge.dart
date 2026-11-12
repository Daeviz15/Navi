import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice/application/voice_session_controller.dart';
import '../presentation/journey_controller.dart';

/// Conversation results belong to the journey, regardless of the visible page.
final voiceJourneyBridgeProvider = Provider<void>((ref) {
  ref.listen(voiceSessionProvider, (previous, next) {
    final destinationChanged =
        next.destinationRevision != previous?.destinationRevision &&
        next.destinationRevision > 0 &&
        next.destination != null;
    final preparationChanged =
        next.checklistRevision != previous?.checklistRevision &&
        next.checklistRevision > 0;
    final journey = ref.read(journeyDraftProvider.notifier);
    if (preparationChanged) {
      journey.setCompanionPrep(
        destination: next.destination,
        purposeSummary: next.purposeSummary,
        isCasual: next.isCasual,
        checklist: next.checklist,
      );
    } else if (destinationChanged) {
      journey.setDestination(next.destination!);
    }
  });
});
