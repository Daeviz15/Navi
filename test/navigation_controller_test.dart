import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/application/navigation_controller.dart';
import 'package:navi/features/navigation/data/backend_navigation_gateway.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/navigation/domain/destination_selection.dart';

const place = DestinationPlace(
  id: 'provider-id',
  name: 'Lekki',
  address: 'Lagos, Nigeria',
  point: GeoPoint(6.45, 3.47),
);

const secondPlace = DestinationPlace(
  id: 'provider-id-2',
  name: 'Lekki Phase 1 Gate',
  address: 'Lekki Phase 1, Lagos, Nigeria',
  point: GeoPoint(6.451, 3.472),
);

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

DestinationSelectionRequest requestFor(
  ProviderContainer container,
  DestinationPlace place, {
  DestinationConfirmationSource source = DestinationConfirmationSource.tap,
}) => DestinationSelectionRequest(
  token: container.read(navigationControllerProvider).suggestions!.token,
  placeId: place.id,
  source: source,
);

bool confirm(ProviderContainer container, DestinationPlace place) => container
    .read(navigationControllerProvider.notifier)
    .confirm(requestFor(container, place));

void main() {
  late ProviderContainer container;
  late _Gateway gateway;
  setUp(() {
    gateway = _Gateway();
    container = ProviderContainer(
      overrides: [
        navigationGatewayProvider.overrideWith((ref) async => gateway),
        locationControllerProvider.overrideWith(_Location.new),
      ],
    );
    container.read(journeyDraftProvider.notifier).setDestination('Lekki');
    container.listen(navigationControllerProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test(
    'search requires confirmation, rejects invented IDs and allows explicit switching',
    () async {
      await flush();
      gateway.searches.single.complete([place, secondPlace]);
      await flush();
      final stateAfterSearch = container.read(navigationControllerProvider);
      expect(stateAfterSearch.selected, isNull);
      expect(stateAfterSearch.places, hasLength(2));
      expect(gateway.routes, isEmpty);

      final controller = container.read(navigationControllerProvider.notifier);
      // Unsearched invented place IDs are ignored.
      expect(
        controller.confirm(
          requestFor(
            container,
            const DestinationPlace(
              id: 'invented',
              name: '',
              address: '',
              point: GeoPoint(0, 0),
            ),
          ),
        ),
        isFalse,
      );
      expect(container.read(navigationControllerProvider).selected, isNull);
      expect(confirm(container, place), isTrue);
      await flush();
      expect(gateway.routes, hasLength(1));
      gateway.routes.single.complete(_route(TravelMode.bus));
      await flush();
      expect(container.read(navigationControllerProvider).route, isNotNull);

      // Switching between verified candidate places requests a route for the newly picked candidate.
      expect(confirm(container, secondPlace), isTrue);
      expect(container.read(navigationControllerProvider).route, isNull);
      await flush();
      expect(gateway.routes, hasLength(2));
      gateway.routes.last.complete(_route(TravelMode.bus));
      await flush();
      expect(
        container.read(navigationControllerProvider).selected?.id,
        secondPlace.id,
      );
    },
  );

  test(
    'destination edits discard stale search completions and old routes',
    () async {
      await flush();
      container.read(journeyDraftProvider.notifier).setDestination('Yaba');
      await flush();
      expect(gateway.searches, hasLength(2));
      gateway.searches.first.complete([place]);
      await flush();
      expect(
        container.read(navigationControllerProvider).phase,
        NavigationPhase.searching,
      );
      gateway.searches.last.complete([]);
      await flush();
      expect(container.read(navigationControllerProvider).places, isEmpty);
      expect(container.read(navigationControllerProvider).selected, isNull);
    },
  );

  test(
    'duplicate provider IDs and malformed addresses cannot be confirmed',
    () async {
      await flush();
      gateway.searches.single.complete([
        place,
        place,
        secondPlace,
        const DestinationPlace(
          id: 'empty',
          name: '',
          address: 'Lagos',
          point: GeoPoint(6.5, 3.4),
        ),
        const DestinationPlace(
          id: 'invalid',
          name: 'Invalid',
          address: 'Lagos',
          point: GeoPoint(99, 3.4),
        ),
      ]);
      await flush();
      expect(container.read(navigationControllerProvider).places, [
        secondPlace,
      ]);
      expect(confirm(container, place), isFalse);
      expect(gateway.routes, isEmpty);
    },
  );

  test(
    'a single result needs confirmation; repeated confirmation routes once',
    () async {
      await flush();
      gateway.searches.single.complete([place]);
      await flush();
      final controller = container.read(navigationControllerProvider.notifier);
      await controller.plan();
      (container.read(locationControllerProvider.notifier) as _Location)
          .setFix();
      await flush();
      expect(container.read(navigationControllerProvider).selected, isNull);
      expect(gateway.routes, isEmpty);
      final request = requestFor(
        container,
        place,
        source: DestinationConfirmationSource.voice,
      );
      expect(controller.confirm(request), isTrue);
      expect(controller.confirm(request), isTrue);
      await flush();
      expect(gateway.routes, hasLength(1));
      expect(
        container
            .read(navigationControllerProvider)
            .confirmation!
            .evidence
            .source,
        DestinationConfirmationSource.voice,
      );
      gateway.routes.single.complete(_route(TravelMode.bus));
      await flush();
    },
  );

  test(
    'refresh invalidates old controls even when provider place IDs match',
    () async {
      await flush();
      gateway.searches.single.complete([place]);
      await flush();
      final old = requestFor(container, place);
      final controller = container.read(navigationControllerProvider.notifier);
      final searching = controller.search();
      await flush();
      gateway.searches.last.complete([place]);
      await searching;
      expect(controller.confirm(old), isFalse);
      expect(controller.reject(old), isFalse);
      final forgedToken = DestinationSearchToken(
        old.token.journey,
        container
            .read(navigationControllerProvider)
            .suggestions!
            .token
            .revision,
      );
      expect(
        controller.confirm(
          DestinationSelectionRequest(
            token: forgedToken,
            placeId: place.id,
            source: DestinationConfirmationSource.tap,
          ),
        ),
        isFalse,
      );
      expect(gateway.routes, isEmpty);
      expect(confirm(container, place), isTrue);
      await flush();
      gateway.routes.single.complete(_route(TravelMode.bus));
      await flush();
    },
  );

  test('rejecting a readback never confirms another candidate', () async {
    await flush();
    gateway.searches.single.complete([place, secondPlace]);
    await flush();
    final controller = container.read(navigationControllerProvider.notifier);
    final rejected = requestFor(container, place);
    expect(controller.reject(rejected), isTrue);
    expect(controller.confirm(rejected), isFalse);
    expect(controller.confirm(requestFor(container, place)), isFalse);
    expect(container.read(navigationControllerProvider).places, [secondPlace]);
    expect(container.read(navigationControllerProvider).selected, isNull);
    expect(gateway.routes, isEmpty);
    expect(controller.reject(requestFor(container, secondPlace)), isTrue);
    expect(container.read(navigationControllerProvider).places, isEmpty);
    expect(
      container.read(navigationControllerProvider).message,
      contains('No matches left'),
    );
  });

  test(
    'pending mode change keeps candidates but invalidates old confirmation controls',
    () async {
      await flush();
      gateway.searches.single.complete([place]);
      await flush();
      final old = requestFor(container, place);
      container
          .read(journeyDraftProvider.notifier)
          .setTravelMode(TravelMode.walking);
      await flush();
      expect(container.read(navigationControllerProvider).places, [place]);
      expect(container.read(navigationControllerProvider).selected, isNull);
      expect(
        container.read(navigationControllerProvider.notifier).confirm(old),
        isFalse,
      );
      expect(gateway.searches, hasLength(1));
      expect(gateway.routes, isEmpty);
      confirm(container, place);
      await flush();
      expect(gateway.modes, [TravelMode.walking]);
      gateway.routes.single.complete(_route(TravelMode.walking));
      await flush();
    },
  );

  test(
    'a late old-place route cannot overwrite a newly confirmed candidate',
    () async {
      await flush();
      gateway.searches.single.complete([place, secondPlace]);
      await flush();
      confirm(container, place);
      await flush();
      confirm(container, secondPlace);
      await flush();
      gateway.routes.first.complete(_route(TravelMode.bus));
      await flush();
      expect(container.read(navigationControllerProvider).route, isNull);
      expect(
        container.read(navigationControllerProvider).selected!.id,
        secondPlace.id,
      );
      gateway.routes.last.complete(_route(TravelMode.bus));
      await flush();
      expect(container.read(navigationControllerProvider).route, isNotNull);
    },
  );

  test(
    'a delayed voice choice cannot replace a newer tap confirmation',
    () async {
      await flush();
      gateway.searches.single.complete([place, secondPlace]);
      await flush();
      final oldVoice = requestFor(
        container,
        place,
        source: DestinationConfirmationSource.voice,
      );
      final controller = container.read(navigationControllerProvider.notifier);
      expect(confirm(container, secondPlace), isTrue);
      expect(controller.confirm(oldVoice), isFalse);
      expect(controller.reject(oldVoice), isFalse);
      expect(
        container.read(navigationControllerProvider).selected!.id,
        secondPlace.id,
      );
      await flush();
      expect(gateway.routes, hasLength(1));
      gateway.routes.single.complete(_route(TravelMode.bus));
      await flush();
    },
  );

  test(
    'uncertain GPS waits, and a fresh precise fix starts planning once',
    () async {
      await flush();
      final location =
          container.read(locationControllerProvider.notifier) as _Location;
      location.setFix(quality: FixQuality.uncertain);
      gateway.searches.single.complete([place]);
      await flush();
      confirm(container, place);
      expect(
        container.read(navigationControllerProvider).phase,
        NavigationPhase.waitingForLocation,
      );
      expect(gateway.routes, isEmpty);
      location.setFix();
      await flush();
      expect(gateway.routes, hasLength(1));
      gateway.routes.single.complete(_route(TravelMode.bus));
      await flush();
      location.setFix(latitude: 6.54);
      expect(container.read(navigationControllerProvider).route, isNull);
      expect(
        container.read(navigationControllerProvider).message,
        contains('starting point changed'),
      );
      expect(
        gateway.routes,
        hasLength(1),
      ); // No automatic billable request flood.
    },
  );

  test(
    'changing mode cannot display a late route for the previous mode',
    () async {
      await flush();
      gateway.searches.single.complete([place]);
      await flush();
      confirm(container, place);
      await flush();
      container
          .read(journeyDraftProvider.notifier)
          .setTravelMode(TravelMode.walking);
      await flush();
      expect(gateway.modes, [TravelMode.bus, TravelMode.walking]);
      gateway.routes.first.complete(_route(TravelMode.bus));
      await flush();
      expect(container.read(navigationControllerProvider).route, isNull);
      gateway.routes.last.complete(_route(TravelMode.walking));
      await flush();
      expect(
        container.read(navigationControllerProvider).route!.mode,
        TravelMode.walking,
      );
    },
  );

  test(
    'reset rejects an old route even when the next trip uses the same query',
    () async {
      await flush();
      gateway.searches.single.complete([place]);
      await flush();
      confirm(container, place);
      await flush();
      final oldIdentity = container.read(journeyDraftProvider).identity;
      final journey = container.read(journeyDraftProvider.notifier);
      journey.reset();
      journey.setDestination('Lekki');
      await flush();
      gateway.routes.first.complete(_route(TravelMode.bus));
      await flush();
      expect(container.read(navigationControllerProvider).route, isNull);
      gateway.searches.last.complete([place]);
      await flush();
      expect(container.read(navigationControllerProvider).selected, isNull);
      confirm(container, place);
      await flush();
      gateway.routes.last.complete(_route(TravelMode.bus));
      await flush();
      final navigation = container.read(navigationControllerProvider);
      expect(navigation.route, isNotNull);
      expect(
        navigation.identity,
        container.read(journeyDraftProvider).identity,
      );
      expect(navigation.identity!.tripId, isNot(oldIdentity.tripId));
    },
  );

  test('mode change during search cannot strand the current request', () async {
    await flush();
    container
        .read(journeyDraftProvider.notifier)
        .setTravelMode(TravelMode.walking);
    await flush();
    gateway.searches.first.complete([place]);
    await flush();
    expect(gateway.routes, isEmpty);
    gateway.searches.last.complete([place]);
    await flush();
    confirm(container, place);
    await flush();
    expect(gateway.modes, [TravelMode.walking]);
    gateway.routes.single.complete(_route(TravelMode.walking));
    await flush();
    expect(
      container.read(navigationControllerProvider).identity,
      container.read(journeyDraftProvider).identity,
    );
  });

  test(
    'missing backend has an explicit setup state rather than a silent retry',
    () async {
      final missing = ProviderContainer(
        overrides: [
          navigationGatewayProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(missing.dispose);
      missing.read(journeyDraftProvider.notifier).setDestination('Lekki');
      missing.listen(navigationControllerProvider, (_, _) {});
      await flush();
      final state = missing.read(navigationControllerProvider);
      expect(state.needsSetup, isTrue);
      expect(state.route, isNull);
      expect(state.message, contains('not connected'));
    },
  );

  test(
    'polyline decoding rejects malformed data; highlight follows real bends',
    () {
      final points = decodeRoutePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points, hasLength(3));
      expect(points.first.latitude, closeTo(38.5, .00001));
      for (final encoded in ['', '_', '??', '\u0000\u0000']) {
        expect(
          () => decodeRoutePolyline(encoded),
          throwsA(isA<NavigationFailure>()),
        );
      }
      final sampler = RouteFlowSampler(const [
        GeoPoint(0, 0),
        GeoPoint(0, 1),
        GeoPoint(1, 1),
      ]);
      final highlight = sampler.highlight(.5);
      expect(highlight.first.latitude, closeTo(0, .0001));
      expect(highlight.first.longitude, closeTo(1, .0001));
      expect(highlight.last.latitude, greaterThan(0));
      expect(highlight.last.longitude, closeTo(1, .0001));
    },
  );
}

JourneyRoute _route(TravelMode mode) => JourneyRoute(
  points: const [GeoPoint(6.52, 3.37), GeoPoint(6.45, 3.47)],
  origin: const GeoPoint(6.52, 3.37),
  mode: mode,
  kind: mode == TravelMode.bus ? RouteKind.busTransit : RouteKind.walking,
  distanceMeters: 10000,
  durationSeconds: 1800,
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
);

class _Gateway implements NavigationGateway {
  final searches = <Completer<List<DestinationPlace>>>[];
  final routes = <Completer<JourneyRoute>>[];
  final modes = <TravelMode>[];
  @override
  Future<List<DestinationPlace>> search(String query) {
    final pending = Completer<List<DestinationPlace>>();
    searches.add(pending);
    return pending.future;
  }

  @override
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  }) {
    modes.add(mode);
    final pending = Completer<JourneyRoute>();
    routes.add(pending);
    return pending.future;
  }
}

class _Location extends LocationController {
  @override
  LocationState build() => _state();
  void setFix({
    double latitude = 6.52,
    FixQuality quality = FixQuality.usable,
  }) => state = _state(latitude: latitude, quality: quality);
  LocationState _state({
    double latitude = 6.52,
    FixQuality quality = FixQuality.usable,
  }) => LocationState(
    phase: LocationPhase.tracking,
    quality: quality,
    fix: LocationFix(
      latitude: latitude,
      longitude: 3.37,
      accuracyMeters: quality == FixQuality.usable ? 8 : 100,
      receivedAt: Duration.zero,
      ageAtReceipt: Duration.zero,
    ),
  );
}
