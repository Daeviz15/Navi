import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/geolocator_location_gateway.dart';
import '../domain/location_gateway.dart';

final locationClockProvider = Provider<LocationClock>(
  (ref) => MonotonicLocationClock(),
);
final locationGatewayProvider = Provider<LocationGateway>(
  (ref) => GeolocatorLocationGateway(ref.watch(locationClockProvider)),
);

enum LocationPhase {
  idle,
  requesting,
  acquiring,
  tracking,
  denied,
  deniedForever,
  servicesOff,
  unavailable,
  suspended,
}

class LocationState {
  const LocationState({
    this.phase = LocationPhase.idle,
    this.fix,
    this.quality = FixQuality.unavailable,
    this.approximate = false,
  });

  final LocationPhase phase;
  final LocationFix? fix;
  final FixQuality quality;
  final bool approximate;

  bool get hasCurrentFix =>
      phase == LocationPhase.tracking &&
      (quality == FixQuality.usable || quality == FixQuality.uncertain);

  String get caption => switch (phase) {
    LocationPhase.idle => 'See where you are',
    LocationPhase.requesting => 'Checking location access…',
    LocationPhase.acquiring => 'Finding your position…',
    LocationPhase.denied => 'Location access is off',
    LocationPhase.deniedForever => 'Allow location in app settings',
    LocationPhase.servicesOff => 'Turn on your phone’s location',
    LocationPhase.unavailable => 'Your location is unavailable',
    LocationPhase.suspended => 'Location paused',
    LocationPhase.tracking => switch (quality) {
      FixQuality.usable => 'Your current position',
      FixQuality.uncertain =>
        approximate
            ? 'Showing your approximate area'
            : 'Location signal is uncertain',
      FixQuality.stale => 'Waiting for a fresh position…',
      FixQuality.unavailable => 'Finding your position…',
    },
  };
}

final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);

class LocationController extends Notifier<LocationState> {
  static const _policy = LocationQualityPolicy();
  StreamSubscription<LocationFix>? _positions;
  StreamSubscription<bool>? _services;
  Timer? _ticker;
  Timer? _acquisitionDeadline;
  int _generation = 0;
  bool _disposed = false;
  bool _wanted = false;
  bool _visible = true;

  LocationGateway get _gateway => ref.read(locationGatewayProvider);
  Duration get _now => ref.read(locationClockProvider).elapsed;

  @override
  LocationState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _cancelStreams();
    });
    return const LocationState();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> enable() async {
    if (_disposed || state.phase == LocationPhase.requesting) {
      return;
    }
    _visible = true;
    if (_wanted &&
        (state.phase == LocationPhase.tracking ||
            state.phase == LocationPhase.acquiring)) {
      return;
    }
    _wanted = true;
    await _start(requestPermission: true);
  }

  Future<void> _start({required bool requestPermission}) async {
    final generation = ++_generation;
    await _cancelStreams();
    if (!_current(generation) || !_visible) return;
    state = const LocationState(phase: LocationPhase.requesting);
    try {
      final access = await _gateway.access(
        requestPermission: requestPermission,
      );
      if (!_current(generation) || !_visible) return;
      final blocked = switch (access) {
        LocationAccess.denied => LocationPhase.denied,
        LocationAccess.deniedForever => LocationPhase.deniedForever,
        LocationAccess.servicesOff => LocationPhase.servicesOff,
        _ => null,
      };
      if (blocked != null) {
        state = LocationState(phase: blocked);
        return;
      }
      final approximate = access == LocationAccess.approximate;
      state = LocationState(
        phase: LocationPhase.acquiring,
        approximate: approximate,
      );
      _positions = _gateway.watch().listen(
        (fix) {
          if (!_current(generation) || !fix.isValid) return;
          final previous = state.fix;
          if (previous != null && fix.measuredAt <= previous.measuredAt) return;
          final quality = _policy.evaluate(fix, _now, approximate: approximate);
          if (quality == FixQuality.unavailable ||
              quality == FixQuality.stale) {
            return;
          }
          _acquisitionDeadline?.cancel();
          state = LocationState(
            phase: LocationPhase.tracking,
            fix: fix,
            quality: quality,
            approximate: approximate,
          );
        },
        onError: (Object _) => _unavailable(generation),
        onDone: () => _unavailable(generation),
      );
      _services = _gateway.serviceChanges().listen((enabled) {
        if (_current(generation) && !enabled) {
          _generation++;
          unawaited(_cancelStreams());
          state = const LocationState(phase: LocationPhase.servicesOff);
        }
      }, onError: (Object _) => _unavailable(generation));
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_current(generation) || state.fix == null) return;
        final quality = _policy.evaluate(
          state.fix,
          _now,
          approximate: approximate,
        );
        if (quality != state.quality) {
          state = LocationState(
            phase: LocationPhase.tracking,
            fix: state.fix,
            quality: quality,
            approximate: approximate,
          );
        }
      });
      _acquisitionDeadline = Timer(const Duration(seconds: 20), () {
        if (_current(generation) && state.fix == null) {
          _unavailable(generation);
        }
      });
    } catch (_) {
      _unavailable(generation);
    }
  }

  void _unavailable(int generation) {
    if (!_current(generation)) return;
    _generation++;
    unawaited(_cancelStreams());
    state = const LocationState(phase: LocationPhase.unavailable);
  }

  /// Start only from explicit user action; resume checks never prompt permission.
  Future<void> setVisible(bool visible) async {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    if (!visible) {
      final generation = ++_generation;
      await _cancelStreams();
      if (_current(generation) && !_visible && _wanted) {
        state = const LocationState(phase: LocationPhase.suspended);
      }
    } else if (_wanted) {
      await _start(requestPermission: false);
    }
  }

  /// Stops active location streams and clears position state when ending a trip.
  Future<void> reset() async {
    _wanted = false;
    _generation++;
    // Detach the old handles before publishing idle. Cancellation can finish
    // after a new enable(); it must never publish over that newer acquisition.
    final cleanup = _cancelStreams();
    _visible = true;
    if (!_disposed) state = const LocationState();
    await cleanup;
  }

  Future<void> openSettings() async {
    if (state.phase == LocationPhase.servicesOff) {
      await _gateway.openLocationSettings();
    } else {
      await _gateway.openAppSettings();
    }
  }

  Future<void> _cancelStreams() async {
    _ticker?.cancel();
    _ticker = null;
    _acquisitionDeadline?.cancel();
    _acquisitionDeadline = null;
    final positions = _positions;
    final services = _services;
    _positions = null;
    _services = null;
    await Future.wait([
      if (positions != null) positions.cancel(),
      if (services != null) services.cancel(),
    ]);
  }
}
