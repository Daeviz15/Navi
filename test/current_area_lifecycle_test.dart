import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/data/reverse_geocoder.dart';
import 'package:navi/features/navigation/domain/area_observation.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/voice/data/cloud_http_client.dart';

Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final scenario in ['weak', 'approximate', 'suspended', 'missing']) {
    test('an area label is withdrawn immediately for $scenario GPS', () async {
      final geocoder = _Geocoder();
      final container = ProviderContainer(
        overrides: [
          reverseGeocoderProvider.overrideWith((ref) async => geocoder),
          locationControllerProvider.overrideWith(_Location.new),
        ],
      );
      addTearDown(() {
        container.dispose();
        geocoder.close();
      });
      final journey = container.read(journeyDraftProvider.notifier);
      journey.setDestination('Ikeja');
      journey.startTrip();
      container.listen(currentAreaProvider, (_, _) {});
      await flush();
      geocoder.requests.single.complete('Ikeja');
      await flush();
      expect(container.read(currentAreaProvider), 'Ikeja');
      final location =
          container.read(locationControllerProvider.notifier) as _Location;
      location.replace(switch (scenario) {
        'suspended' => const LocationState(phase: LocationPhase.suspended),
        'missing' => const LocationState(phase: LocationPhase.tracking),
        _ => LocationState(
          phase: LocationPhase.tracking,
          quality: scenario == 'weak'
              ? FixQuality.uncertain
              : FixQuality.usable,
          approximate: scenario == 'approximate',
          fix: LocationFix(
            latitude: 6.52,
            longitude: 3.37,
            accuracyMeters: scenario == 'weak' ? 100 : 8,
            receivedAt: Duration.zero,
            ageAtReceipt: Duration.zero,
          ),
        ),
      });
      expect(container.read(currentAreaProvider), isNull);
      expect(geocoder.requests, hasLength(1));
    });
  }

  test(
    'a result from an area left during lookup never becomes current',
    () async {
      final geocoder = _Geocoder();
      final container = ProviderContainer(
        overrides: [
          reverseGeocoderProvider.overrideWith((ref) async => geocoder),
          locationControllerProvider.overrideWith(_Location.new),
        ],
      );
      addTearDown(() {
        container.dispose();
        geocoder.close();
      });
      final journey = container.read(journeyDraftProvider.notifier);
      journey.setDestination('Ikeja');
      journey.startTrip();
      container.listen(currentAreaProvider, (_, _) {});
      await flush();
      (container.read(locationControllerProvider.notifier) as _Location)
          .replace(
            const LocationState(
              phase: LocationPhase.tracking,
              quality: FixQuality.usable,
              fix: LocationFix(
                latitude: 6.55,
                longitude: 3.37,
                accuracyMeters: 8,
                receivedAt: Duration.zero,
                ageAtReceipt: Duration.zero,
              ),
            ),
          );
      geocoder.requests.single.complete('Old street');
      await flush();
      expect(container.read(currentAreaProvider), isNull);
      expect(
        container.read(currentAreaObservationProvider).status,
        AreaStatus.stale,
      );
    },
  );

  testWidgets(
    'freshness expires without location events; failed refresh cannot keep the old label',
    (tester) async {
      final clock = _Clock();
      final geocoder = _Geocoder();
      final container = ProviderContainer(
        overrides: [
          locationClockProvider.overrideWithValue(clock),
          reverseGeocoderProvider.overrideWith((ref) async => geocoder),
          locationControllerProvider.overrideWith(_Location.new),
        ],
      );
      final journey = container.read(journeyDraftProvider.notifier);
      journey.setDestination('Ikeja');
      journey.startTrip();
      container.listen(currentAreaProvider, (_, _) {});
      await tester.pump();
      geocoder.requests.single.complete('Old street');
      await tester.pump();
      expect(container.read(currentAreaProvider), 'Old street');
      clock.elapsed = const Duration(seconds: 11);
      await tester.pump(const Duration(seconds: 11));
      expect(container.read(currentAreaProvider), isNull);
      expect(geocoder.requests, hasLength(1));
      // A fresh fix in the same area can reuse the still-applicable observation.
      final location =
          container.read(locationControllerProvider.notifier) as _Location;
      void renew() => location.replace(
        LocationState(
          phase: LocationPhase.tracking,
          quality: FixQuality.usable,
          fix: LocationFix(
            latitude: 6.52,
            longitude: 3.37,
            accuracyMeters: 8,
            receivedAt: clock.elapsed,
            ageAtReceipt: Duration.zero,
          ),
        ),
      );
      renew();
      expect(container.read(currentAreaProvider), 'Old street');
      clock.elapsed = const Duration(seconds: 91);
      renew();
      await tester.pump();
      expect(container.read(currentAreaProvider), isNull);
      expect(geocoder.requests, hasLength(2));
      geocoder.requests.last.complete(null);
      await tester.pump();
      expect(
        container.read(currentAreaObservationProvider).status,
        AreaStatus.lookupFailed,
      );
      expect(container.read(currentAreaProvider), isNull);
      clock.elapsed += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
      expect(geocoder.requests, hasLength(2));
      container.dispose();
      geocoder.close();
    },
  );

  test('old area lookup cannot publish or unlock a new trip lookup', () async {
    final geocoder = _Geocoder();
    final container = ProviderContainer(
      overrides: [
        reverseGeocoderProvider.overrideWith((ref) async => geocoder),
        locationControllerProvider.overrideWith(_Location.new),
      ],
    );
    addTearDown(() {
      container.dispose();
      geocoder.close();
    });
    final journey = container.read(journeyDraftProvider.notifier);
    journey.setDestination('Ikeja');
    journey.startTrip();
    container.listen(currentAreaProvider, (_, _) {});
    await flush();
    expect(geocoder.requests, hasLength(1));
    journey.reset();
    journey.setDestination('Yaba');
    journey.startTrip();
    await flush();
    expect(geocoder.requests, hasLength(2));
    geocoder.requests.first.complete('Old area');
    await flush();
    expect(container.read(currentAreaProvider), isNull);
    final location =
        container.read(locationControllerProvider.notifier) as _Location;
    location.move();
    await flush();
    // The old finally block must not release this newer request's lock.
    expect(geocoder.requests, hasLength(2));
    geocoder.requests.last.complete('New area');
    await flush();
    expect(container.read(currentAreaProvider), 'New area');
  });

  test(
    'switching active destination invalidates an in-flight area result',
    () async {
      final geocoder = _Geocoder();
      final container = ProviderContainer(
        overrides: [
          reverseGeocoderProvider.overrideWith((ref) async => geocoder),
          locationControllerProvider.overrideWith(_Location.new),
        ],
      );
      addTearDown(() {
        container.dispose();
        geocoder.close();
      });
      final journey = container.read(journeyDraftProvider.notifier);
      journey.setDestination('Ikeja');
      journey.startTrip();
      container.listen(currentAreaProvider, (_, _) {});
      await flush();
      journey.switchTripDestination('Yaba');
      await flush();
      geocoder.requests.first.complete('Old area');
      await flush();
      expect(container.read(currentAreaProvider), isNull);
      geocoder.requests.last.complete('Current area');
      await flush();
      expect(container.read(currentAreaProvider), 'Current area');
    },
  );
}

class _Geocoder extends ReverseGeocoder {
  _Geocoder() : super(apiKey: 'test', http: DartIoCloudHttpTransport());
  final requests = <Completer<String?>>[];
  void close() => (http as DartIoCloudHttpTransport).close();
  @override
  Future<String?> lookupArea(GeoPoint point) {
    final request = Completer<String?>();
    requests.add(request);
    return request.future;
  }
}

class _Location extends LocationController {
  void replace(LocationState next) => state = next;
  @override
  LocationState build() => _fix(6.52);
  void move() => state = _fix(6.5201);
  LocationState _fix(double latitude) => LocationState(
    phase: LocationPhase.tracking,
    quality: FixQuality.usable,
    fix: LocationFix(
      latitude: latitude,
      longitude: 3.37,
      accuracyMeters: 8,
      receivedAt: Duration.zero,
      ageAtReceipt: Duration.zero,
    ),
  );
}

class _Clock implements LocationClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => DateTime.utc(2026, 11, 13).add(elapsed);
}
