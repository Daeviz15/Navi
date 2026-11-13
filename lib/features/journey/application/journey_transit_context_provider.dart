import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../location/application/location_controller.dart';
import '../../navigation/application/navigation_controller.dart';
import '../../navigation/data/reverse_geocoder.dart';
import '../../voice/domain/voice_gateway.dart';
import '../domain/journey_draft.dart';
import '../presentation/journey_controller.dart';

/// Immediate intent-only context while dependent navigation providers refresh.
JourneyTransitContext journeyIntentContext(JourneyDraft draft) =>
    JourneyTransitContext(
      identity: draft.identity,
      isActive: draft.isActive,
      destination: draft.destination,
      purposeSummary: draft.purposeSummary,
      isCasual: draft.isCasual,
      checklist: draft.checklist,
      checkedItems: draft.checkedItems,
      travelModeLabel: draft.travelMode == TravelMode.bus
          ? 'By bus'
          : 'On foot',
    );

/// One derived view of journey facts for the voice adapter. This provider owns
/// no independent trip state. Progress/estimate confidence is refined in the
/// next reliability packages; identity prevents mixing facts from different trips.
final journeyTransitContextProvider = Provider<JourneyTransitContext>((ref) {
  final draft = ref.watch(journeyDraftProvider);
  if (!draft.isActive) {
    return journeyIntentContext(draft);
  }

  final navigation = ref.watch(navigationControllerProvider);
  final nav = navigation.identity == draft.identity
      ? navigation
      : const NavigationState();
  final loc = ref.watch(locationControllerProvider);
  final area = ref.watch(currentAreaProvider);
  final progress = nav.progress;
  final route = nav.route;

  return JourneyTransitContext(
    identity: draft.identity,
    isActive: true,
    destination: draft.destination,
    confirmedPlaceName: nav.selected?.name,
    confirmedAddress: nav.selected?.address,
    destinationSuggestions: nav.confirmation == null ? nav.suggestions : null,
    travelModeLabel: draft.travelMode == TravelMode.bus ? 'By bus' : 'On foot',
    purposeSummary: draft.purposeSummary.isEmpty ? null : draft.purposeSummary,
    isCasual: draft.isCasual,
    checklist: draft.checklist,
    checkedItems: draft.checkedItems,
    currentArea: area,
    remainingDistanceMeters: progress.canReportRemaining
        ? progress.remainingMeters
        : null,
    // Provider duration is a planning estimate from its origin, not a live ETA.
    remainingDurationSeconds: null,
    routeProgressStatus: progress.status,
    routeEstimatesStale: nav.estimatesStale,
    routeRefreshing: nav.refreshing,
    gpsQualityLabel: loc.quality.name,
    isOffRoute: progress.isOffRoute,
    isRoadFallback: route?.isRoadFallback ?? false,
    // Overview hints lack step anchors/progression. Do not speak them as next turns.
    nextGuidanceSteps: const <String>[],
  );
});
