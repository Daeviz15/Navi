import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/journey/domain/journey_identity.dart';
import 'package:navi/features/location/application/location_controller.dart';
import 'package:navi/features/location/domain/location_gateway.dart';
import 'package:navi/features/navigation/application/navigation_controller.dart';
import 'package:navi/features/navigation/domain/destination_selection.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/navigation/domain/route_progress.dart';
import 'package:navi/features/navigation/presentation/journey_map_canvas.dart';
import 'package:navi/features/navigation/presentation/route_preview_trace.dart';

void main() {
  late GoogleMapsFlutterPlatform previousPlatform;
  late NavigationState navigation;
  late LocationState location;
  setUp(() {
    previousPlatform = GoogleMapsFlutterPlatform.instance;
    GoogleMapsFlutterPlatform.instance = _MapPlatform(connect: true);
    location = const LocationState();
    const identity = JourneyIdentity(tripId: 1);
    const place = DestinationPlace(
      id: 'destination',
      name: 'Destination',
      address: 'Lagos',
      point: GeoPoint(6.53, 3.38),
    );
    navigation = NavigationState(
      identity: identity,
      phase: NavigationPhase.ready,
      confirmation: ConfirmedDestination(
        place: place,
        evidence: DestinationSelectionRequest(
          token: DestinationSearchToken(identity, 1),
          placeId: place.id,
          source: DestinationConfirmationSource.tap,
        ),
      ),
      route: JourneyRoute(
        points: [
          const GeoPoint(6.52, 3.37),
          const GeoPoint(6.52, 3.38),
          place.point,
        ],
        origin: const GeoPoint(6.52, 3.37),
        mode: TravelMode.walking,
        kind: RouteKind.walking,
        distanceMeters: 2200,
        durationSeconds: 1500,
        expiresAt: DateTime(2026, 11, 13, 12),
      ),
    );
  });
  tearDown(() => GoogleMapsFlutterPlatform.instance = previousPlatform);

  Future<void> mount(
    WidgetTester tester, {
    bool reduced = false,
    bool visible = true,
    double density = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduced,
            devicePixelRatio: density,
          ),
          child: TickerMode(
            enabled: visible,
            child: JourneyMapCanvas(location: location, navigation: navigation),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  Set<Polyline> lines(WidgetTester tester) =>
      tester.widget<GoogleMap>(find.byType(GoogleMap)).polylines;
  RoutePreviewTrace trace(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('route-preview-trace')),
              )
              .painter!
          as RoutePreviewTrace;

  testWidgets(
    'Flutter trace animates without native map rebuilds or invented progress',
    (tester) async {
      await mount(tester);
      final platform = GoogleMapsFlutterPlatform.instance as _MapPlatform;
      expect(navigation.progress.canReportRemaining, isFalse);
      expect(
        lines(tester).map((p) => p.polylineId.value),
        contains('verified-route'),
      );
      final phase = trace(tester).phase.value;
      final projections = platform.projections;
      final builds = platform.builds;
      await tester.pump(const Duration(milliseconds: 250));
      expect(trace(tester).phase.value, isNot(phase));
      expect(platform.projections, projections);
      expect(platform.builds, builds);
      expect(navigation.progress.remainingMeters, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'camera movement hides the trace until freshly projected; Android density is respected',
    (tester) async {
      await mount(tester, density: 2);
      final initial = trace(tester).path.getBounds();
      expect(initial.right, closeTo(55, 1));
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.onCameraMoveStarted!();
      await tester.pump();
      expect(find.byKey(const ValueKey('route-preview-trace')), findsNothing);
      map.onCameraIdle!();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(trace(tester).path.getBounds(), initial);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'route overview keeps the blue cloud in view across GPS updates',
    (tester) async {
      final platform = _MapPlatform(connect: true);
      GoogleMapsFlutterPlatform.instance = platform;
      location = const LocationState(
        phase: LocationPhase.tracking,
        quality: FixQuality.usable,
        fix: LocationFix(
          latitude: 6.52,
          longitude: 3.37,
          accuracyMeters: 8,
          receivedAt: Duration.zero,
          ageAtReceipt: Duration.zero,
        ),
      );
      await mount(tester, reduced: true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(platform.cameraUpdates, hasLength(1));
      expect(
        (platform.cameraUpdates.single.toJson() as List<Object>).first,
        'newLatLngBounds',
      );
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(
        map.markers.map((m) => m.markerId.value),
        containsAll(['you', 'destination']),
      );
      await mount(tester, reduced: true);
      expect(platform.cameraUpdates, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'confirmed endpoints remain visible when route lookup is still pending',
    (tester) async {
      final platform = _MapPlatform(connect: true);
      GoogleMapsFlutterPlatform.instance = platform;
      navigation = NavigationState(
        identity: navigation.identity,
        phase: NavigationPhase.planning,
        confirmation: navigation.confirmation,
      );
      location = const LocationState(
        phase: LocationPhase.tracking,
        quality: FixQuality.usable,
        fix: LocationFix(
          latitude: 6.52,
          longitude: 3.37,
          accuracyMeters: 8,
          receivedAt: Duration.zero,
          ageAtReceipt: Duration.zero,
        ),
      );
      await mount(tester, reduced: true);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(
        (platform.cameraUpdates.single.toJson() as List<Object>).first,
        'newLatLngBounds',
      );
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(
        map.markers.map((m) => m.markerId.value),
        containsAll(['you', 'destination']),
      );
      expect(map.polylines, isEmpty);
      expect(platform.animatedCameraUpdates, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'reduced motion and hidden surfaces retain only the static route',
    (tester) async {
      await mount(tester, reduced: true);
      expect(lines(tester), hasLength(2));
      expect(find.byKey(const ValueKey('route-preview-trace')), findsNothing);
      await mount(tester);
      expect(find.byKey(const ValueKey('route-preview-trace')), findsOneWidget);
      await mount(tester, visible: false);
      expect(lines(tester), hasLength(2));
      expect(find.byKey(const ValueKey('route-preview-trace')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background, stale route, and confirmed deviation pause the preview',
    (tester) async {
      await mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(lines(tester), hasLength(2));
      expect(find.byKey(const ValueKey('route-preview-trace')), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.byKey(const ValueKey('route-preview-trace')), findsOneWidget);
      navigation = navigation.copyWith(estimatesStale: true);
      await mount(tester);
      expect(lines(tester), hasLength(2));
      expect(find.byKey(const ValueKey('route-preview-trace')), findsNothing);
      navigation = navigation.copyWith(
        estimatesStale: false,
        progress: const RouteProgress(status: RouteProgressStatus.offRoute),
      );
      await mount(tester);
      expect(lines(tester), hasLength(2));
      expect(find.byKey(const ValueKey('route-preview-trace')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

/// Inspect the exact objects sent to the map widget without a native view or
/// Google requests. Device rendering and frame timing still need a phone check.
class _MapPlatform extends MethodChannelGoogleMapsFlutter {
  _MapPlatform({this.connect = false});
  final bool connect;
  final _created = <int>{};
  int projections = 0, builds = 0;
  final cameraUpdates = <CameraUpdate>[];
  final animatedCameraUpdates = <CameraUpdate>[];

  @override
  Future<ScreenCoordinate> getScreenCoordinate(
    LatLng point, {
    required int mapId,
  }) async {
    projections++;
    return ScreenCoordinate(
      x: (10 + (point.longitude - 3.37) * 10000).round(),
      y: (10 + (point.latitude - 6.52) * 10000).round(),
    );
  }

  @override
  Future<void> init(int mapId) async {
    ensureChannelInitialized(mapId);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel(mapId), (_) async => null);
  }

  @override
  Future<void> animateCamera(CameraUpdate update, {required int mapId}) async {
    cameraUpdates.add(update);
    animatedCameraUpdates.add(update);
  }

  @override
  Future<void> moveCamera(CameraUpdate update, {required int mapId}) async {
    cameraUpdates.add(update);
  }

  @override
  Future<void> updateGroundOverlays(
    GroundOverlayUpdates updates, {
    required int mapId,
  }) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    builds++;
    if (connect && _created.add(creationId)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onPlatformViewCreated(creationId),
      );
    }
    return const SizedBox.expand();
  }
}
