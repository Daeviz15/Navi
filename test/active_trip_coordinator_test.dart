import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/application/active_trip_coordinator.dart';
import 'package:navi/features/journey/application/voice_journey_bridge.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/navigation/data/backend_navigation_gateway.dart';
import 'package:navi/features/navigation/data/reverse_geocoder.dart';
import 'package:navi/features/voice/application/voice_dependencies.dart';
import 'package:navi/features/voice/application/voice_session_controller.dart';
import 'package:navi/features/voice/domain/local_command_router.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

import 'support/voice_harness.dart';

void main() {
  late ProviderContainer container;
  late Completer<void> gpsCleanup;
  late ActiveTripCoordinator coordinator;
  setUp(() {
    gpsCleanup = Completer<void>();
    container = ProviderContainer(
      overrides: [
        locationControllerProvider.overrideWith(
          () => _DelayedLocation(gpsCleanup),
        ),
        navigationGatewayProvider.overrideWith((ref) async => null),
        reverseGeocoderProvider.overrideWith((ref) async => null),
        voiceServicesProvider.overrideWithValue(
          VoiceServices(
            microphone: () => TestMicrophone(true, null, null),
            speech: () => TestSpeech(null),
            output: () => TestVoiceOutput(null),
            reasoner: const LocalCommandRouter(),
          ),
        ),
      ],
    );
    container.listen(voiceJourneyBridgeProvider, (_, _) {});
    coordinator = container.read(activeTripCoordinatorProvider);
  });
  tearDown(() async {
    if (!gpsCleanup.isCompleted) gpsCleanup.complete();
    await flushVoice();
    container.dispose();
  });

  test(
    'old GPS cleanup cannot clear a new trip or its tapped conversation',
    () async {
      final journey = container.read(journeyDraftProvider.notifier);
      final voice = container.read(voiceSessionProvider.notifier);
      journey.setDestination('Ikeja');
      coordinator.beginTransit();
      voice.setHomeVisible(true);
      await flushVoice();
      await voice.toggleConversation();
      expect(container.read(voiceSessionProvider).phase, VoicePhase.listening);
      final oldIdentity = container.read(journeyDraftProvider).identity;
      final ending = coordinator.endTrip(expectedIdentity: oldIdentity);
      expect(container.read(journeyDraftProvider).destination, isEmpty);
      expect(container.read(voiceSessionProvider).enabled, isFalse);
      expect(identical(coordinator.endTrip(), ending), isTrue);

      journey.setDestination('Yaba');
      coordinator.beginTransit();
      final newIdentity = container.read(journeyDraftProvider).identity;
      await voice.toggleConversation();
      expect(container.read(voiceSessionProvider).phase, VoicePhase.listening);
      gpsCleanup.complete();
      await ending;
      expect(container.read(journeyDraftProvider).identity, newIdentity);
      expect(container.read(journeyDraftProvider).isActive, isTrue);
      expect(container.read(voiceSessionProvider).enabled, isTrue);
      expect(container.read(voiceSessionProvider).journeyIdentity, newIdentity);
      expect(container.read(voiceSessionProvider).destination, 'Yaba');
    },
  );

  test('stale start/end commands cannot affect a newer draft', () async {
    final journey = container.read(journeyDraftProvider.notifier);
    expect(coordinator.beginTransit(), isFalse);
    journey.setDestination('Ikeja');
    final old = container.read(journeyDraftProvider).identity;
    journey.reset();
    journey.setDestination('Ikeja');
    final current = container.read(journeyDraftProvider).identity;
    expect(coordinator.beginTransit(expectedIdentity: old), isFalse);
    await coordinator.endTrip(expectedIdentity: old);
    expect(container.read(journeyDraftProvider).identity, current);
    expect(container.read(journeyDraftProvider).destination, 'Ikeja');
    expect(coordinator.beginTransit(expectedIdentity: current), isTrue);
  });
}

class _DelayedLocation extends LocationController {
  _DelayedLocation(this.cleanup);
  final Completer<void> cleanup;
  @override
  LocationState build() => const LocationState();
  @override
  Future<void> reset() async {
    state = const LocationState();
    await cleanup.future;
  }
}
