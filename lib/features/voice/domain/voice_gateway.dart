import 'dart:typed_data';

import '../../journey/domain/journey_identity.dart';
import '../../navigation/domain/destination_selection.dart';
import '../../navigation/domain/route_progress.dart';
import '../../navigation/domain/navigation_gateway.dart';
import 'local_command_router.dart';
import 'voice_types.dart';

abstract interface class MicrophoneInput {
  Future<bool> hasPermission({required bool request});
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class SpeechEngine {
  Stream<SpeechEvent> get events;
  Future<void> initialize();
  void setMode(SpeechMode mode);
  void addAudio(Uint8List bytes);
  Future<void> dispose();
}

abstract interface class VoiceReasoner {
  Future<LocalReply> resolve(String utterance, {required bool wakeDetected});
}

/// Playback events carry utterance IDs so late native callbacks are harmless.
abstract interface class VoiceGateway {
  Stream<OutputEvent> get events;
  Future<void> initialize();
  Future<void> speak(String message, {required int id});
  Future<void> stopSpeaking();
  Future<void> dispose();
}

/// Live snapshot of an active trip so Navi answers strictly within the ongoing
/// route until the user ends or explicitly changes the trip.
class JourneyTransitContext {
  const JourneyTransitContext({
    this.identity,
    this.isActive = false,
    this.destination,
    this.confirmedPlaceName,
    this.confirmedAddress,
    this.destinationSuggestions,
    this.travelModeLabel,
    this.purposeSummary,
    this.isCasual = false,
    this.checklist = const <String>[],
    this.checkedItems = const <String>{},
    this.currentArea,
    this.remainingDistanceMeters,
    this.remainingDurationSeconds,
    this.gpsQualityLabel,
    this.isOffRoute = false,
    this.routeKind,
    this.nextGuidanceSteps = const <String>[],
    this.routeProgressStatus,
    this.routeEstimatesStale = false,
    this.routeRefreshing = false,
  });

  final JourneyIdentity? identity;
  final bool isActive;
  final String? destination;
  final String? confirmedPlaceName;
  final String? confirmedAddress;
  final DestinationSuggestions? destinationSuggestions;
  final String? travelModeLabel;
  final String? purposeSummary;
  final bool isCasual;
  final List<String> checklist;
  final Set<String> checkedItems;
  final String? currentArea;
  final double? remainingDistanceMeters;
  final int? remainingDurationSeconds;
  final String? gpsQualityLabel;
  final bool isOffRoute;
  final RouteKind? routeKind;
  bool get isRoadFallback => routeKind == RouteKind.roadCorridor;
  final List<String> nextGuidanceSteps;
  final RouteProgressStatus? routeProgressStatus;
  final bool routeEstimatesStale, routeRefreshing;
}

/// Allows voice reasoning to track Home selection vs. active transit context.
abstract interface class ConversationAwareReasoner {
  void setDestinationContext(String destination);
  void updateTransitContext(
    JourneyTransitContext context, {
    bool resetPendingSwitch = false,
  });
  void clearTripContext();
  void cancelPendingReply();
}
