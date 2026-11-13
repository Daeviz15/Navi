import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/presentation/journey_controller.dart';
import '../../journey/domain/journey_identity.dart';
import '../../location/application/location_controller.dart';
import '../../location/domain/location_gateway.dart';
import '../data/backend_navigation_gateway.dart';
import '../domain/navigation_gateway.dart';
import '../domain/destination_selection.dart';
import '../domain/route_progress.dart';
import 'navigation_reliability_policy.dart';

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
    this.identity,
    this.phase = NavigationPhase.idle,
    this.suggestions,
    this.confirmation,
    this.route,
    this.message,
    this.failureCode,
    this.progress = const RouteProgress(),
    this.refreshing = false,
    this.refreshAllowed = true,
    this.estimatesStale = false,
    this.routeRevision = 0,
  });
  final JourneyIdentity? identity;
  final NavigationPhase phase;
  final DestinationSuggestions? suggestions;
  final ConfirmedDestination? confirmation;
  List<DestinationPlace> get places => suggestions?.places ?? const [];
  DestinationPlace? get selected => confirmation?.place;
  final JourneyRoute? route;
  final String? message;
  final String? failureCode;
  final RouteProgress progress;
  final bool refreshing, refreshAllowed, estimatesStale;
  final int routeRevision;
  String? get routeSummary => route == null ? null : progress.caption;

  NavigationState copyWith({
    RouteProgress? progress,
    bool? refreshing,
    bool? refreshAllowed,
    bool? estimatesStale,
    String? message,
    String? failureCode,
    bool clearNotice = false,
  }) => NavigationState(
    identity: identity,
    phase: phase,
    suggestions: suggestions,
    confirmation: confirmation,
    route: route,
    routeRevision: routeRevision,
    progress: progress ?? this.progress,
    refreshing: refreshing ?? this.refreshing,
    refreshAllowed: refreshAllowed ?? this.refreshAllowed,
    estimatesStale: estimatesStale ?? this.estimatesStale,
    message: clearNotice ? null : message ?? this.message,
    failureCode: clearNotice ? null : failureCode ?? this.failureCode,
  );

  bool get needsSetup =>
      failureCode == 'not_configured' ||
      failureCode == 'provider_not_configured';
}

final navigationControllerProvider =
    NotifierProvider<NavigationController, NavigationState>(
      NavigationController.new,
    );

class NavigationController extends Notifier<NavigationState>
    implements DestinationSelectionCommands {
  int _generation = 0;
  Timer? _expiry;
  Timer? _refreshReady;
  RouteProgressTracker? _tracker;
  Future<void>? _planning;
  Duration? _nextRefresh;
  int _refreshFailures = 0, _routeRevision = 0;
  bool _disposed = false;
  JourneyIdentity? _requestIdentity;
  int _suggestionRevision = 0;
  NavigationReliabilityPolicy get _policy =>
      ref.read(navigationReliabilityPolicyProvider);
  LocationClock get _clock => ref.read(locationClockProvider);

  @override
  NavigationState build() {
    // Keep the auto-disposed HTTP adapter alive throughout this controller's
    // requests without rebuilding the controller when configuration resolves.
    ref.listen(navigationGatewayProvider, (_, _) {});
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _expiry?.cancel();
      _refreshReady?.cancel();
    });
    ref.listen(
      journeyDraftProvider.select(
        (draft) => (draft.identity.tripId, draft.destination),
      ),
      (_, _) {
        unawaited(search());
      },
    );
    ref.listen(journeyDraftProvider.select((draft) => draft.travelMode), (
      _,
      _,
    ) {
      _changeMode();
    });
    ref.listen(
      locationControllerProvider,
      (_, location) => _onLocation(location),
    );
    ref.listen(journeyDraftProvider.select((draft) => draft.isActive), (_, _) {
      _onLocation(ref.read(locationControllerProvider));
    });
    Future.microtask(() {
      if (!_disposed) unawaited(search());
    });
    return const NavigationState();
  }

  bool _current(int generation) =>
      !_disposed &&
      generation == _generation &&
      _requestIdentity == ref.read(journeyDraftProvider).identity;

  Future<void> search() async {
    _resetRouteWork();
    final generation = _generation;
    final draft = ref.read(journeyDraftProvider);
    _requestIdentity = draft.identity;
    _expiry?.cancel();
    final query = draft.destination.trim();
    if (query.isEmpty) {
      state = const NavigationState();
      return;
    }
    state = NavigationState(
      identity: draft.identity,
      phase: NavigationPhase.searching,
    );
    try {
      final gateway = await ref.read(navigationGatewayProvider.future);
      if (!_current(generation)) return;
      if (gateway == null) throw const NavigationFailure('not_configured');
      final results = await gateway.search(query);
      if (!_current(generation)) return;
      final counts = <String, int>{};
      for (final place in results) {
        counts.update(place.id, (count) => count + 1, ifAbsent: () => 1);
      }
      // One canonical address per ID is necessary for both visual and spoken
      // confirmation. Ambiguous/malformed provider records cannot be selected.
      final places = results
          .where(
            (place) =>
                counts[place.id] == 1 &&
                place.id.trim().isNotEmpty &&
                place.name.trim().isNotEmpty &&
                place.address.trim().isNotEmpty &&
                place.point.isValid,
          )
          .toList();
      state = NavigationState(
        identity: draft.identity,
        phase: NavigationPhase.choosePlace,
        suggestions: DestinationSuggestions(
          token: DestinationSearchToken(draft.identity, ++_suggestionRevision),
          places: places,
        ),
        message: places.isEmpty
            ? 'No matching Lagos place was found. Try a more specific destination.'
            : 'Confirm the name and address before we find your route.',
      );
    } catch (error) {
      if (_current(generation)) {
        state = NavigationState(
          identity: draft.identity,
          phase: NavigationPhase.unavailable,
          failureCode: error is NavigationFailure ? error.code : 'unavailable',
          message: error is NavigationFailure
              ? error.message
              : const NavigationFailure('unavailable').message,
        );
      }
    }
  }

  bool _accepts(DestinationSelectionRequest request) =>
      !_disposed &&
      state.identity == ref.read(journeyDraftProvider).identity &&
      request.token == state.suggestions?.token;

  @override
  bool confirm(DestinationSelectionRequest request) {
    if (!_accepts(request)) {
      // A duplicate of the accepted choice is harmless; a delayed choice for
      // another address must not undo a newer tap or voice confirmation.
      return !_disposed &&
          state.identity == ref.read(journeyDraftProvider).identity &&
          request.token.journey == state.identity &&
          request.token == state.confirmation?.evidence.token &&
          request.placeId == state.selected?.id;
    }
    DestinationPlace? place;
    for (final candidate in state.places) {
      if (candidate.id == request.placeId) place = candidate;
    }
    if (place == null) return false;
    // Double taps and repeated voice events must not create billable requests.
    if (state.selected?.id == place.id) return true;
    _resetRouteWork();
    state = NavigationState(
      identity: state.identity,
      suggestions: DestinationSuggestions(
        token: DestinationSearchToken(state.identity!, ++_suggestionRevision),
        places: state.places,
      ),
      confirmation: ConfirmedDestination(place: place, evidence: request),
      phase: NavigationPhase.waitingForLocation,
    );
    unawaited(plan());
    return true;
  }

  @override
  bool reject(DestinationSelectionRequest request) {
    if (!_accepts(request) ||
        !state.places.any((place) => place.id == request.placeId)) {
      return false;
    }
    _resetRouteWork();
    final remaining = state.places
        .where((place) => place.id != request.placeId)
        .toList();
    state = NavigationState(
      identity: state.identity,
      phase: NavigationPhase.choosePlace,
      suggestions: DestinationSuggestions(
        token: DestinationSearchToken(state.identity!, ++_suggestionRevision),
        places: remaining,
      ),
      message: remaining.isEmpty
          ? 'No matches left. Try a more specific destination.'
          : 'Choose another matching name and address.',
    );
    return true;
  }

  void _changeMode() {
    final identity = ref.read(journeyDraftProvider).identity;
    final suggestions = state.suggestions;
    if (suggestions == null || state.identity?.tripId != identity.tripId) {
      if (state.phase == NavigationPhase.searching) unawaited(search());
      return;
    }
    _resetRouteWork();
    // Changing bus/walking does not change a previously confirmed address.
    // Rebind pending controls so old callbacks cannot select against a new mode.
    final confirmation = state.confirmation;
    state = NavigationState(
      identity: identity,
      suggestions: DestinationSuggestions(
        token: DestinationSearchToken(identity, ++_suggestionRevision),
        places: suggestions.places,
      ),
      confirmation: confirmation,
      phase: confirmation == null
          ? NavigationPhase.choosePlace
          : NavigationPhase.waitingForLocation,
    );
    if (confirmation != null) unawaited(plan());
  }

  void clear() {
    _resetRouteWork();
    _requestIdentity = null;
    _expiry?.cancel();
    state = const NavigationState();
  }

  void _resetRouteWork() {
    _generation++;
    _planning = null;
    _tracker = null;
    _expiry?.cancel();
    _refreshReady?.cancel();
    _nextRefresh = null;
    _refreshFailures = 0;
  }

  bool _usable(LocationState location) => _policy.progress.accepts(
    location.fix,
    _clock.elapsed,
    usable:
        location.hasCurrentFix &&
        location.quality == FixQuality.usable &&
        !location.approximate,
  );

  RouteProgress _progress(LocationState location) =>
      _tracker?.update(
        location.fix,
        _clock.elapsed,
        usable: _usable(location),
      ) ??
      const RouteProgress();

  void _onLocation(LocationState location) {
    if (_disposed || state.selected == null) return;
    final route = state.route;
    if (route == null) {
      if (state.phase == NavigationPhase.waitingForLocation &&
          _usable(location)) {
        unawaited(plan());
      }
      return;
    }
    // The origin constraint belongs to an unstarted preview, not active travel.
    if (!ref.read(journeyDraftProvider).isActive &&
        _usable(location) &&
        GeoPoint(
              location.fix!.latitude,
              location.fix!.longitude,
            ).distanceTo(route.origin) >
            150) {
      _invalidateRoute(
        'Your preview starting point changed. Refresh the route.',
      );
      return;
    }
    final progress = _progress(location);
    if (!identical(state.progress, progress)) {
      state = state.copyWith(progress: progress);
    }
    _maybeAutoRefresh(location);
  }

  void _maybeAutoRefresh(LocationState location) {
    if (!ref.read(journeyDraftProvider).isActive ||
        !_usable(location) ||
        state.route == null ||
        _planning != null ||
        !state.refreshAllowed) {
      return;
    }
    if (state.estimatesStale || state.progress.isOffRoute) unawaited(plan());
  }

  Future<void> plan() {
    if (_disposed ||
        state.identity != ref.read(journeyDraftProvider).identity ||
        state.selected == null) {
      return Future.value();
    }
    if (_planning != null) return _planning!;
    if (_nextRefresh != null && _clock.elapsed < _nextRefresh!) {
      return Future.value();
    }
    final location = ref.read(locationControllerProvider);
    if (!_usable(location)) {
      state = NavigationState(
        identity: state.identity,
        suggestions: state.suggestions,
        confirmation: state.confirmation,
        route: state.route,
        routeRevision: state.routeRevision,
        phase: state.route == null
            ? NavigationPhase.waitingForLocation
            : NavigationPhase.ready,
        progress: const RouteProgress(),
        estimatesStale: state.estimatesStale,
        message: 'Waiting for a reliable position before refreshing the route.',
      );
      return Future.value();
    }
    final completion = Completer<void>();
    final pending = completion.future;
    _planning = pending;
    final generation = ++_generation;
    _requestIdentity = ref.read(journeyDraftProvider).identity;
    unawaited(
      _performPlan(generation, location).then(
        (_) {
          if (identical(_planning, pending)) _planning = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_planning, pending)) _planning = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return pending;
  }

  Future<void> _performPlan(int generation, LocationState location) async {
    final destination = state.selected!;
    final suggestions = state.suggestions;
    final confirmation = state.confirmation;
    final identity = state.identity!;
    final origin = GeoPoint(location.fix!.latitude, location.fix!.longitude);
    final mode = ref.read(journeyDraftProvider).travelMode;
    final retained = state.route;
    state = NavigationState(
      identity: identity,
      suggestions: suggestions,
      confirmation: confirmation,
      route: retained,
      routeRevision: state.routeRevision,
      progress: state.progress,
      phase: retained == null
          ? NavigationPhase.planning
          : NavigationPhase.ready,
      refreshing: true,
      refreshAllowed: false,
      estimatesStale:
          retained != null && !retained.expiresAt.isAfter(_clock.utcNow),
    );
    _setCooldown(_policy.refreshCooldown);
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
      if (!route.geometry.isUsable ||
          route.mode != mode ||
          !route.distanceMeters.isFinite ||
          route.distanceMeters <= 0 ||
          !route.kind.supports(mode) ||
          (route.kind != RouteKind.roadCorridor &&
              route.durationSeconds == null) ||
          (route.durationSeconds != null &&
              (!route.durationSeconds!.isFinite ||
                  route.durationSeconds! < 0)) ||
          route.origin.distanceTo(origin) > 1) {
        throw const NavigationFailure('invalid_response');
      }
      final current = ref.read(locationControllerProvider);
      if (!ref.read(journeyDraftProvider).isActive &&
          _usable(current) &&
          origin.distanceTo(
                GeoPoint(current.fix!.latitude, current.fix!.longitude),
              ) >
              150) {
        _invalidateRoute(
          'Your preview starting point changed. Refresh the route.',
        );
        return;
      }
      _tracker = RouteProgressTracker(
        geometry: route.geometry,
        routeDistanceMeters: route.distanceMeters,
        mode: mode,
        policy: _policy.progress,
      );
      _refreshFailures = 0;
      state = NavigationState(
        identity: identity,
        suggestions: suggestions,
        confirmation: confirmation,
        route: route,
        routeRevision: ++_routeRevision,
        progress: _progress(current),
        phase: NavigationPhase.ready,
        refreshAllowed: _nextRefresh == null,
        estimatesStale: !route.expiresAt.isAfter(_clock.utcNow),
      );
      _armExpiry(route, identity);
    } catch (error) {
      if (!_current(generation)) return;
      final failure = error is NavigationFailure
          ? error
          : const NavigationFailure('unavailable');
      _refreshFailures++;
      _setCooldown(_policy.delayAfterFailure(_refreshFailures));
      state = NavigationState(
        identity: identity,
        suggestions: suggestions,
        confirmation: confirmation,
        route: retained,
        routeRevision: state.routeRevision,
        progress: state.progress,
        phase: retained == null
            ? NavigationPhase.unavailable
            : NavigationPhase.ready,
        refreshAllowed: false,
        estimatesStale: state.estimatesStale,
        failureCode: failure.code,
        message: retained == null
            ? failure.message
            : 'Could not refresh. The previous route remains visible. ${failure.message}',
      );
    }
  }

  void _setCooldown(Duration delay) {
    _refreshReady?.cancel();
    final deadline = _nextRefresh = _clock.elapsed + delay;
    final identity = state.identity;
    _refreshReady = Timer(delay, () {
      if (_disposed || _nextRefresh != deadline || state.identity != identity) {
        return;
      }
      _nextRefresh = null;
      state = state.copyWith(refreshAllowed: true);
    });
  }

  void _armExpiry(JourneyRoute route, JourneyIdentity identity) {
    _expiry?.cancel();
    final remaining = route.expiresAt.difference(_clock.utcNow);
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (_disposed ||
          state.identity != identity ||
          !identical(state.route, route)) {
        return;
      }
      if (!ref.read(journeyDraftProvider).isActive) {
        _invalidateRoute('This route preview needs refreshing.');
        return;
      }
      final location = ref.read(locationControllerProvider);
      state = state.copyWith(
        estimatesStale: true,
        progress: _progress(location),
      );
      _maybeAutoRefresh(location);
    });
  }

  void _invalidateRoute(String message) {
    _resetRouteWork();
    state = NavigationState(
      identity: state.identity,
      phase: NavigationPhase.unavailable,
      suggestions: state.suggestions,
      confirmation: state.confirmation,
      message: message,
    );
  }
}
