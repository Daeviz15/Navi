import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/data/reverse_geocoder.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/voice/data/cloud_http_client.dart';

Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
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
  @override
  LocationState build() => _fix(6.52);
  void move() => state = _fix(6.53);
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
