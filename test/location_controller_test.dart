import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';

class _Clock implements LocationClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => DateTime.utc(2026, 11, 12).add(elapsed);
}

class _Gateway implements LocationGateway {
  LocationAccess result = LocationAccess.precise;
  Completer<LocationAccess>? pending;
  final permissionRequests = <bool>[];
  int watchCalls = 0;
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;
  final positions = StreamController<LocationFix>.broadcast();
  final services = StreamController<bool>.broadcast();

  @override
  Future<LocationAccess> access({required bool requestPermission}) {
    permissionRequests.add(requestPermission);
    return pending?.future ?? Future.value(result);
  }

  @override
  Stream<LocationFix> watch() {
    watchCalls++;
    return positions.stream;
  }

  @override
  Stream<bool> serviceChanges() => services.stream;
  @override
  Future<void> openAppSettings() async => appSettingsCalls++;
  @override
  Future<void> openLocationSettings() async => locationSettingsCalls++;

  Future<void> close() async {
    await positions.close();
    await services.close();
  }
}

class _DelayedCancelGateway extends _Gateway {
  final cancellation = Completer<void>();
  final sessions = <StreamController<LocationFix>>[];
  @override
  Stream<LocationFix> watch() {
    watchCalls++;
    final session = StreamController<LocationFix>(
      onCancel: () => cancellation.future,
    );
    sessions.add(session);
    return session.stream;
  }

  @override
  Future<void> close() async {
    if (!cancellation.isCompleted) cancellation.complete();
    await super.close();
    for (final session in sessions) {
      await session.close();
    }
  }
}

LocationFix _fix({
  Duration received = Duration.zero,
  Duration age = Duration.zero,
  double accuracy = 8,
  double latitude = 6.5244,
}) => LocationFix(
  latitude: latitude,
  longitude: 3.3792,
  accuracyMeters: accuracy,
  receivedAt: received,
  ageAtReceipt: age,
);

void main() {
  test('late stream cancellation cannot reset newer GPS acquisition', () async {
    final gateway = _DelayedCancelGateway();
    final container = ProviderContainer(
      overrides: [
        locationGatewayProvider.overrideWithValue(gateway),
        locationClockProvider.overrideWithValue(_Clock()),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await gateway.close();
    });
    final controller = container.read(locationControllerProvider.notifier);
    await controller.enable();
    final resetting = controller.reset();
    await controller.enable();
    expect(gateway.sessions, hasLength(2));
    gateway.sessions.last.add(_fix());
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(locationControllerProvider).phase,
      LocationPhase.tracking,
    );
    gateway.cancellation.complete();
    await resetting;
    expect(
      container.read(locationControllerProvider).phase,
      LocationPhase.tracking,
    );
    expect(gateway.sessions.last.hasListener, isTrue);
  });

  test(
    'quality separates validity, uncertainty, approximate access and age',
    () {
      const policy = LocationQualityPolicy();
      expect(
        policy.evaluate(_fix(), Duration.zero, approximate: false),
        FixQuality.usable,
      );
      expect(
        policy.evaluate(_fix(accuracy: 90), Duration.zero, approximate: false),
        FixQuality.uncertain,
      );
      expect(
        policy.evaluate(_fix(), Duration.zero, approximate: true),
        FixQuality.uncertain,
      );
      expect(
        policy.evaluate(
          _fix(),
          const Duration(seconds: 11),
          approximate: false,
        ),
        FixQuality.stale,
      );
      for (final invalid in [
        _fix(latitude: double.nan),
        _fix(latitude: 91),
        _fix(accuracy: double.infinity),
        _fix(accuracy: 0),
        _fix(age: const Duration(seconds: -5)),
      ]) {
        expect(
          policy.evaluate(invalid, Duration.zero, approximate: false),
          FixQuality.unavailable,
        );
      }
    },
  );

  late ProviderContainer container;
  late _Gateway gateway;
  late _Clock clock;
  late LocationController controller;

  setUp(() {
    gateway = _Gateway();
    clock = _Clock();
    container = ProviderContainer(
      overrides: [
        locationGatewayProvider.overrideWithValue(gateway),
        locationClockProvider.overrideWithValue(clock),
      ],
    );
    container.listen(locationControllerProvider, (_, _) {});
    controller = container.read(locationControllerProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    await gateway.close();
  });

  test(
    'does not request permission or track until the user enables it',
    () async {
      expect(gateway.permissionRequests, isEmpty);
      expect(gateway.watchCalls, 0);
      await controller.enable();
      expect(gateway.permissionRequests, [true]);
      expect(gateway.positions.hasListener, isTrue);
      expect(
        container.read(locationControllerProvider).phase,
        LocationPhase.acquiring,
      );
    },
  );

  test('denial and disabled services have distinct recovery actions', () async {
    gateway.result = LocationAccess.deniedForever;
    await controller.enable();
    expect(
      container.read(locationControllerProvider).phase,
      LocationPhase.deniedForever,
    );
    await controller.openSettings();
    expect(gateway.appSettingsCalls, 1);
    expect(gateway.watchCalls, 0);

    gateway.result = LocationAccess.servicesOff;
    await controller.enable();
    await controller.openSettings();
    expect(gateway.locationSettingsCalls, 1);
    expect(
      container.read(locationControllerProvider).phase,
      LocationPhase.servicesOff,
    );
  });

  test(
    'rejects cached, invalid and out-of-order fixes without replacing current position',
    () async {
      clock.elapsed = const Duration(seconds: 20);
      await controller.enable();
      gateway.positions.add(
        _fix(received: clock.elapsed, age: const Duration(seconds: 15)),
      );
      gateway.positions.add(_fix(received: clock.elapsed, latitude: 100));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(locationControllerProvider).fix, isNull);

      final current = _fix(received: clock.elapsed);
      gateway.positions.add(current);
      await Future<void>.delayed(Duration.zero);
      gateway.positions.add(
        _fix(received: clock.elapsed, age: const Duration(seconds: 2)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(locationControllerProvider).fix, same(current));
      expect(container.read(locationControllerProvider).hasCurrentFix, isTrue);
    },
  );

  test('approximate permission is never presented as a precise fix', () async {
    gateway.result = LocationAccess.approximate;
    await controller.enable();
    gateway.positions.add(_fix());
    await Future<void>.delayed(Duration.zero);
    final state = container.read(locationControllerProvider);
    expect(state.quality, FixQuality.uncertain);
    expect(state.caption, contains('approximate'));
  });

  test('a stationary fix becomes stale and a fresh fix recovers', () async {
    await controller.enable();
    gateway.positions.add(_fix());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(locationControllerProvider).hasCurrentFix, isTrue);
    clock.elapsed = const Duration(seconds: 11);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(
      container.read(locationControllerProvider).quality,
      FixQuality.stale,
    );
    expect(container.read(locationControllerProvider).hasCurrentFix, isFalse);
    gateway.positions.add(_fix(received: clock.elapsed));
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(locationControllerProvider).quality,
      FixQuality.usable,
    );
    await controller.setVisible(false);
  });

  test(
    'background releases both streams; resume rechecks without prompting',
    () async {
      await controller.enable();
      await controller.setVisible(false);
      expect(gateway.positions.hasListener, isFalse);
      expect(gateway.services.hasListener, isFalse);
      expect(
        container.read(locationControllerProvider).phase,
        LocationPhase.suspended,
      );
      gateway.result = LocationAccess.denied;
      await controller.setVisible(true);
      expect(gateway.permissionRequests, [true, false]);
      expect(
        container.read(locationControllerProvider).phase,
        LocationPhase.denied,
      );
      expect(gateway.watchCalls, 1);
    },
  );

  test(
    'backgrounding during permission prevents late microphone-style startup race',
    () async {
      gateway.pending = Completer<LocationAccess>();
      final enabling = controller.enable();
      await Future<void>.delayed(Duration.zero);
      await controller.setVisible(false);
      gateway.pending!.complete(LocationAccess.precise);
      await enabling;
      expect(gateway.watchCalls, 0);
      expect(
        container.read(locationControllerProvider).phase,
        LocationPhase.suspended,
      );
    },
  );

  test(
    'turning GPS off releases subscriptions and supports an explicit retry',
    () async {
      await controller.enable();
      gateway.services.add(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(locationControllerProvider).phase,
        LocationPhase.servicesOff,
      );
      expect(gateway.positions.hasListener, isFalse);
      await controller.enable();
      expect(gateway.watchCalls, 2);
      expect(gateway.positions.hasListener, isTrue);
    },
  );

  test(
    'stream failure releases resources and does not masquerade as a live fix',
    () async {
      await controller.enable();
      gateway.positions.addError(StateError('GPS disconnected'));
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(locationControllerProvider).phase,
        LocationPhase.unavailable,
      );
      expect(container.read(locationControllerProvider).hasCurrentFix, isFalse);
      expect(gateway.positions.hasListener, isFalse);
    },
  );
}
