import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../location/application/location_controller.dart';
import '../../navigation/application/navigation_controller.dart';
import '../../navigation/data/reverse_geocoder.dart';
import '../../voice/application/voice_session_controller.dart';
import '../domain/journey_identity.dart';
import '../presentation/journey_controller.dart';

final activeTripCoordinatorProvider = Provider<ActiveTripCoordinator>(
  ActiveTripCoordinator.new,
);

/// Single coordinator managing active-trip lifecycle transitions across journey
/// draft, GPS tracking, route navigation, reverse geocoding, and voice context.
class ActiveTripCoordinator {
  ActiveTripCoordinator(this._ref);
  final Ref _ref;
  Future<void>? _ending;

  bool beginTransit({JourneyIdentity? expectedIdentity}) {
    if (expectedIdentity != null &&
        _ref.read(journeyDraftProvider).identity != expectedIdentity) {
      return false;
    }
    _ref.read(journeyDraftProvider.notifier).startTrip();
    return _ref.read(journeyDraftProvider).isActive;
  }

  Future<void> endTrip({JourneyIdentity? expectedIdentity}) {
    final draft = _ref.read(journeyDraftProvider);
    if (expectedIdentity != null && expectedIdentity != draft.identity) {
      return Future.value();
    }
    // Repeated commands during cleanup share the same operation. A new draft
    // can still be started immediately without waiting for platform teardown.
    if (draft.destination.trim().isEmpty) return _ending ?? Future.value();
    final navigation = _ref.read(navigationControllerProvider.notifier);
    final currentArea = _ref.read(currentAreaProvider.notifier);
    final journey = _ref.read(journeyDraftProvider.notifier);
    final location = _ref.read(locationControllerProvider.notifier);
    final voice = _ref.read(voiceSessionProvider.notifier);

    navigation.clear();
    currentArea.clear();
    journey.reset();
    // Start both invalidations in this stack, before any awaited cleanup can
    // yield to a new trip. Each owner cleans up only its captured resources.
    late final Future<void> cleanup;
    cleanup = Future.wait([location.reset(), voice.clearActiveTrip()])
        .then((_) {})
        .whenComplete(() {
          if (identical(_ending, cleanup)) _ending = null;
        });
    return _ending = cleanup;
  }
}
