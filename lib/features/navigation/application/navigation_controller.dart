import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/presentation/journey_controller.dart';
import '../../location/application/location_controller.dart';
import '../../location/domain/location_gateway.dart';
import '../data/backend_navigation_gateway.dart';
import '../domain/navigation_gateway.dart';

enum NavigationPhase {
  idle,
  searching,
  choosePlace,
  waitingForLocation,
  planning,
  ready,
  unavailable,
}

class NavigationState {
  const NavigationState({
    this.phase = NavigationPhase.idle,
    this.places = const [],
    this.selected,
    this.route,
    this.message,
  });
  final NavigationPhase phase;
  final List<DestinationPlace> places;
  final DestinationPlace? selected;
  final JourneyRoute? route;
  final String? message;
}

final navigationControllerProvider =
    NotifierProvider.autoDispose<NavigationController, NavigationState>(
      NavigationController.new,
    );

class NavigationController extends Notifier<NavigationState> {
  int _generation = 0;
  Timer? _expiry;
  bool _disposed = false;

  @override
  NavigationState build() {
    // Keep the auto-disposed HTTP adapter alive throughout this controller's
    // requests without rebuilding the controller when configuration resolves.
    ref.listen(navigationGatewayProvider, (_, _) {});
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _expiry?.cancel();
    });
    ref.listen(journeyDraftProvider.select((draft) => draft.destination), (
      _,
      _,
    ) {
      unawaited(search());
    });
    ref.listen(journeyDraftProvider.select((draft) => draft.travelMode), (
      _,
      _,
    ) {
      if (state.selected != null) unawaited(plan());
    });
    ref.listen(locationControllerProvider, (_, location) {
      if (state.selected == null) return;
      if (state.phase == NavigationPhase.waitingForLocation &&
          location.quality == FixQuality.usable &&
          location.hasCurrentFix) {
        unawaited(plan());
      } else if (state.route != null && location.fix != null) {
        final point = GeoPoint(location.fix!.latitude, location.fix!.longitude);
        if (point.distanceTo(state.route!.origin) > 150) {
          _invalidateRoute('Your starting point changed. Refresh the route.');
        }
      }
    });
    Future.microtask(() {
      if (!_disposed) unawaited(search());
    });
    return const NavigationState();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> search() async {
    final generation = ++_generation;
    _expiry?.cancel();
    final query = ref.read(journeyDraftProvider).destination.trim();
    if (query.isEmpty) {
      state = const NavigationState();
      return;
    }
    state = const NavigationState(phase: NavigationPhase.searching);
    try {
      final gateway = await ref.read(navigationGatewayProvider.future);
      if (!_current(generation)) return;
      if (gateway == null) throw const NavigationFailure('not_configured');
      final places = await gateway.search(query);
      if (!_current(generation)) return;
      state = NavigationState(
        phase: NavigationPhase.choosePlace,
        places: places,
        message: places.isEmpty
            ? 'No matching Lagos place was found. Try a more specific destination.'
            : 'Choose the exact place to confirm your destination.',
      );
    } catch (error) {
      if (_current(generation)) {
        state = NavigationState(
          phase: NavigationPhase.unavailable,
          message: error is NavigationFailure
              ? error.message
              : const NavigationFailure('unavailable').message,
        );
      }
    }
  }

  Future<void> select(DestinationPlace place) async {
    if (!state.places.any((candidate) => candidate.id == place.id)) return;
    _generation++;
    _expiry?.cancel();
    state = NavigationState(
      selected: place,
      phase: NavigationPhase.waitingForLocation,
    );
    await plan();
  }

  Future<void> plan() async {
    final destination = state.selected;
    if (destination == null) return;
    final generation = ++_generation;
    _expiry?.cancel();
    final location = ref.read(locationControllerProvider);
    if (!location.hasCurrentFix ||
        location.quality != FixQuality.usable ||
        location.fix == null) {
      state = NavigationState(
        phase: NavigationPhase.waitingForLocation,
        selected: destination,
        message:
            'Waiting for a reliable starting position before finding a route.',
      );
      return;
    }
    final origin = GeoPoint(location.fix!.latitude, location.fix!.longitude);
    final mode = ref.read(journeyDraftProvider).travelMode;
    state = NavigationState(
      phase: NavigationPhase.planning,
      selected: destination,
    );
    try {
      final gateway = await ref.read(navigationGatewayProvider.future);
      if (!_current(generation)) return;
      if (gateway == null) throw const NavigationFailure('not_configured');
      final route = await gateway.plan(
        origin: origin,
        destination: destination,
        mode: mode,
      );
      if (!_current(generation)) return;
      final current = ref.read(locationControllerProvider);
      if (current.fix != null &&
          origin.distanceTo(
                GeoPoint(current.fix!.latitude, current.fix!.longitude),
              ) >
              150) {
        _invalidateRoute('Your starting point changed. Refresh the route.');
        return;
      }
      state = NavigationState(
        phase: NavigationPhase.ready,
        selected: destination,
        route: route,
      );
      _expiry = Timer(route.expiresAt.difference(DateTime.now()), () {
        if (_current(generation)) {
          _invalidateRoute('This route needs refreshing.');
        }
      });
    } catch (error) {
      if (_current(generation)) {
        state = NavigationState(
          phase: NavigationPhase.unavailable,
          selected: destination,
          message: error is NavigationFailure
              ? error.message
              : const NavigationFailure('unavailable').message,
        );
      }
    }
  }

  void _invalidateRoute(String message) {
    _generation++;
    _expiry?.cancel();
    state = NavigationState(
      phase: NavigationPhase.unavailable,
      selected: state.selected,
      message: message,
    );
  }
}
