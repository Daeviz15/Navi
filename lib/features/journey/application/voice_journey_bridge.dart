import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../voice/application/voice_session_controller.dart';
import '../presentation/journey_controller.dart';
import 'active_trip_coordinator.dart';
import 'journey_transit_context_provider.dart';

/// Synchronizes voice turns, active trip telemetry, and automatic route actions
/// regardless of which screen is visible.
final voiceJourneyBridgeProvider = Provider<void>((ref) {
  var applyingVoiceAction = false;
  final voice = ref.read(voiceSessionProvider.notifier);
  ref.listen(journeyTransitContextProvider, (_, context) {
    if (context.identity != ref.read(journeyDraftProvider).identity) return;
    voice.updateTransitContext(
      context,
      preserveConversation: applyingVoiceAction,
    );
  }, fireImmediately: true);
  // Derived providers can otherwise refresh at the end of this event loop.
  // Intent changes must cancel/acknowledge voice work in the same command stack.
  ref.listen(journeyDraftProvider.select((draft) => draft.identity), (_, _) {
    voice.updateTransitContext(
      journeyIntentContext(ref.read(journeyDraftProvider)),
      preserveConversation: applyingVoiceAction,
    );
  });

  ref.listen(voiceSessionProvider, (previous, next) {
    final tripSwitched =
        next.tripChangeRevision != previous?.tripChangeRevision &&
        next.tripChangeRevision > 0 &&
        next.destination != null;
    final destinationChanged =
        next.destinationRevision != previous?.destinationRevision &&
        next.destinationRevision > 0 &&
        next.destination != null;
    final preparationChanged =
        next.checklistRevision != previous?.checklistRevision &&
        next.checklistRevision > 0;
    final endTripRequested =
        next.endTripRevision != previous?.endTripRevision &&
        next.endTripRevision > 0;
    final routeLaunchRequested =
        next.routeLaunchRevision != previous?.routeLaunchRevision &&
        next.routeLaunchRevision > 0;

    // Events carry the trip intent against which they were produced. A delayed
    // end/change/launch event cannot apply to an unrelated newer journey.
    final identity = ref.read(journeyDraftProvider).identity;
    if (next.journeyIdentity != null && next.journeyIdentity != identity) {
      return;
    }
    final journey = ref.read(journeyDraftProvider.notifier);
    if (endTripRequested) {
      unawaited(() async {
        final cleanup = ref
            .read(activeTripCoordinatorProvider)
            .endTrip(expectedIdentity: identity);
        final clearedIdentity = ref.read(journeyDraftProvider).identity;
        await cleanup;
        if (!ref.mounted ||
            ref.read(journeyDraftProvider).identity != clearedIdentity) {
          return;
        }
        final currentPath = naviRouter.routeInformationProvider.value.uri.path;
        if (currentPath == '/preview' || currentPath == '/initialize') {
          naviRouter.go('/');
        }
      }());
      return;
    }

    applyingVoiceAction = true;
    try {
      if (tripSwitched) {
        journey.switchTripDestination(
          next.destination!,
          purposeSummary: next.purposeSummary,
          isCasual: next.isCasual,
          checklist: next.checklist,
        );
      } else if (preparationChanged) {
        journey.setCompanionPrep(
          destination: next.destination,
          purposeSummary: next.purposeSummary,
          isCasual: next.isCasual,
          checklist: next.checklist,
        );
      } else if (destinationChanged) {
        journey.setDestination(next.destination!);
      }
    } finally {
      // A dependent provider may still contain its previous cached value during
      // the notification stack. Acknowledge the actual accepted intent now.
      if (identity != ref.read(journeyDraftProvider).identity) {
        voice.updateTransitContext(
          journeyIntentContext(ref.read(journeyDraftProvider)),
          preserveConversation: true,
        );
      }
      applyingVoiceAction = false;
    }

    if (routeLaunchRequested &&
        ref.read(journeyDraftProvider).destination.trim().isNotEmpty) {
      ref.read(voiceSessionProvider.notifier).suspendForNavigation();
      naviRouter.go('/initialize');
    }
  });
});
