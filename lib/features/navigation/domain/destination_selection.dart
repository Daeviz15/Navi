import '../../journey/domain/journey_identity.dart';
import 'navigation_gateway.dart';

enum DestinationConfirmationSource { tap, voice }

/// Binds a displayed/spoken set of suggestions to one search and trip intent.
class DestinationSearchToken {
  DestinationSearchToken(this.journey, this.revision);
  final JourneyIdentity journey;
  final int revision;

  // Opaque object identity also separates notifier recreations with matching
  // counters. UI/voice carry this token; callers cannot recreate it from fields.
}

class DestinationSuggestions {
  DestinationSuggestions({
    required this.token,
    required List<DestinationPlace> places,
  }) : places = List.unmodifiable(places);
  final DestinationSearchToken token;
  final List<DestinationPlace> places;
}

/// Carries an ID, never caller-supplied coordinates or a fabricated address.
class DestinationSelectionRequest {
  const DestinationSelectionRequest({
    required this.token,
    required this.placeId,
    required this.source,
  });
  final DestinationSearchToken token;
  final String placeId;
  final DestinationConfirmationSource source;
}

class ConfirmedDestination {
  const ConfirmedDestination({required this.place, required this.evidence});
  final DestinationPlace place;
  final DestinationSelectionRequest evidence;
}

/// Shared synchronous commands used by the map and voice adapters. Routing
/// continues asynchronously after confirmation; accepting a place is local.
abstract interface class DestinationSelectionCommands {
  bool confirm(DestinationSelectionRequest request);
  bool reject(DestinationSelectionRequest request);
}
