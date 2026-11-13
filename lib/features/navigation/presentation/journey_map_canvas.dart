import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../location/application/location_controller.dart';
import '../../location/domain/location_gateway.dart';
import '../application/navigation_controller.dart';
import '../domain/navigation_gateway.dart';
import 'navi_map_style.dart';
import 'route_preview_trace.dart';

class JourneyMapCanvas extends StatefulWidget {
  const JourneyMapCanvas({
    super.key,
    required this.location,
    required this.navigation,
  });
  final LocationState location;
  final NavigationState navigation;

  @override
  State<JourneyMapCanvas> createState() => _JourneyMapCanvasState();
}

class _JourneyMapCanvasState extends State<JourneyMapCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _map;
  BitmapDescriptor? _yellowCloud, _blueCloud;
  late final AnimationController _motion;
  Path? _screenPath;
  int _projectionGeneration = 0;
  int? _failedProjection;
  bool _projecting = false, _projectionQueued = false, _cameraMoving = false;
  Size _mapSize = Size.zero;
  List<LatLng> _routePoints = const [];
  bool _visible = true;
  bool _foreground = true,
      _reduceMotion = false,
      _userMovedMap = false,
      _centred = false;
  static const _blue = Color(0xFF4B9FFF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _updateRoute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    _syncFlow();
    _scheduleProjection();
  }

  @override
  void didUpdateWidget(JourneyMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation.selected?.id != widget.navigation.selected?.id) {
      // An explicit new destination starts a new overview. A pan on the previous
      // destination must not hide the newly accepted cloud/route off screen.
      _userMovedMap = false;
      if (widget.navigation.selected != null &&
          widget.navigation.route == null) {
        unawaited(_fitDestination());
      }
    }
    if (oldWidget.navigation.route != widget.navigation.route) {
      _updateRoute();
      if (!_userMovedMap &&
          widget.navigation.route != null &&
          (oldWidget.navigation.route == null ||
              oldWidget.navigation.selected?.id !=
                  widget.navigation.selected?.id ||
              oldWidget.navigation.identity != widget.navigation.identity)) {
        unawaited(_fitRoute());
      }
    }
    if (widget.navigation.route == null &&
        !_centred &&
        !_userMovedMap &&
        widget.location.hasCurrentFix &&
        _map != null) {
      _centred = true;
      unawaited(_centre());
    }
    _syncFlow();
    _scheduleProjection();
  }

  void _updateRoute() {
    final points = widget.navigation.route?.points;
    _invalidateProjection();
    _routePoints = points == null
        ? const []
        : List.unmodifiable(
            points.map((point) => LatLng(point.latitude, point.longitude)),
          );
    _motion.value = 0;
  }

  bool get _canFlow =>
      _screenPath != null &&
      widget.navigation.selected != null &&
      !widget.navigation.estimatesStale &&
      !widget.navigation.progress.isOffRoute &&
      !_cameraMoving &&
      _foreground &&
      _visible &&
      !_reduceMotion;

  void _syncFlow() {
    if (_canFlow) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop(canceled: false);
    }
  }

  void _invalidateProjection() {
    _projectionGeneration++;
    _screenPath = null;
  }

  void _cameraStarted() {
    setState(() {
      _cameraMoving = true;
      _invalidateProjection();
      _syncFlow();
    });
  }

  void _cameraIdle() {
    _cameraMoving = false;
    _scheduleProjection();
  }

  void _scheduleProjection() {
    if (_map == null ||
        widget.navigation.route == null ||
        _cameraMoving ||
        !_foreground ||
        !_visible ||
        _reduceMotion ||
        _failedProjection == _projectionGeneration ||
        _screenPath != null) {
      return;
    }
    if (_projecting) {
      _projectionQueued = true;
      return;
    }
    unawaited(_projectTrace());
  }

  Future<void> _projectTrace() async {
    final map = _map;
    final route = widget.navigation.route;
    if (map == null || route == null) return;
    _projecting = true;
    final generation = _projectionGeneration;
    final scale = defaultTargetPlatform == TargetPlatform.android
        ? MediaQuery.devicePixelRatioOf(context)
        : 1.0;
    final samples = previewProjectionPoints(route.points);
    final offsets = <Offset>[];
    try {
      // Bounded parallel batches, only after camera settling, never per frame.
      for (var start = 0; start < samples.length; start += 8) {
        if (!mounted || generation != _projectionGeneration) return;
        final batch = samples.skip(start).take(8);
        final coordinates = await Future.wait([
          for (final point in batch)
            map
                .getScreenCoordinate(LatLng(point.latitude, point.longitude))
                .timeout(const Duration(seconds: 2)),
        ]);
        offsets.addAll(
          coordinates.map((p) => Offset(p.x / scale, p.y / scale)),
        );
      }
      if (!mounted || generation != _projectionGeneration || _cameraMoving) {
        return;
      }
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final point in offsets.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      setState(() {
        _screenPath = path;
        _syncFlow();
      });
    } catch (_) {
      // Native route stays visible if this optional effect cannot be projected.
      if (mounted && generation == _projectionGeneration) {
        _failedProjection = generation;
      }
    } finally {
      _projecting = false;
      if (_projectionQueued && mounted) {
        _projectionQueued = false;
        _scheduleProjection();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _syncFlow();
    });
    if (_foreground) _scheduleProjection();
  }

  Future<void> _centre() async {
    final fix = widget.location.fix;
    if (_map == null || fix == null || !widget.location.hasCurrentFix) return;
    try {
      await _camera(
        CameraUpdate.newLatLngZoom(
          LatLng(fix.latitude, fix.longitude),
          widget.location.quality == FixQuality.usable ? 16 : 13,
        ),
      );
    } on PlatformException {
      /* View detached during animation. */
    }
  }

  Future<void> _fitRoute() async {
    final route = widget.navigation.route;
    if (_map == null || route == null) return;
    await _fitPoints(route.points);
  }

  Future<void> _fitDestination() async {
    final destination = widget.navigation.selected;
    final fix = widget.location.fix;
    if (destination == null) return;
    await _fitPoints([
      destination.point,
      if (fix != null && widget.location.hasCurrentFix)
        GeoPoint(fix.latitude, fix.longitude),
    ]);
  }

  Future<void> _fitPoints(List<GeoPoint> points) async {
    if (_map == null || points.isEmpty) return;
    _centred = true;
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }
    if (maxLat - minLat < .0001) {
      minLat -= .0001;
      maxLat += .0001;
    }
    if (maxLng - minLng < .0001) {
      minLng -= .0001;
      maxLng += .0001;
    }
    try {
      await _camera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          36,
        ),
      );
    } on PlatformException {
      /* Map layout or attachment changed. */
    }
  }

  Future<void> _camera(CameraUpdate update) {
    final map = _map;
    if (map == null) return Future.value();
    return _reduceMotion ? map.moveCamera(update) : map.animateCamera(update);
  }

  Future<BitmapDescriptor> _cloud(Color colour) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(3);
    final path = Path()
      ..moveTo(9, 29)
      ..cubicTo(0, 29, 0, 16, 9, 15)
      ..cubicTo(9, 6, 21, 3, 26, 12)
      ..cubicTo(33, 8, 41, 15, 37, 21)
      ..cubicTo(44, 29, 35, 34, 28, 31)
      ..lineTo(10, 31)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF151515)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8,
    );
    canvas.drawPath(path, Paint()..color = colour);
    canvas.drawCircle(
      const Offset(18, 22),
      1.3,
      Paint()..color = const Color(0xFF151515),
    );
    canvas.drawCircle(
      const Offset(25, 22),
      1.3,
      Paint()..color = const Color(0xFF151515),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(132, 114);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: 3,
    );
  }

  Future<void> _icons(Color gold) async {
    final icons = await Future.wait([_cloud(gold), _cloud(_blue)]);
    if (mounted) {
      setState(() {
        _yellowCloud = icons[0];
        _blueCloud = icons[1];
      });
    }
  }

  @override
  void dispose() {
    _projectionGeneration++;
    _motion.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _map = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fix = widget.location.fix;
    final selected = widget.navigation.selected;
    final route = widget.navigation.route;
    final scheme = Theme.of(context).colorScheme;
    final precise =
        widget.location.hasCurrentFix &&
        widget.location.quality == FixQuality.usable;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_mapSize != constraints.biggest) {
          _mapSize = constraints.biggest;
          _invalidateProjection();
          _syncFlow();
          Future.microtask(_scheduleProjection);
        }
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) => _userMovedMap = true,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: fix != null && widget.location.hasCurrentFix
                        ? LatLng(fix.latitude, fix.longitude)
                        : const LatLng(6.5244, 3.3792),
                    zoom: precise ? 15 : 11,
                  ),
                  style: Theme.of(context).brightness == Brightness.dark
                      ? naviDarkMapStyle
                      : naviLightMapStyle,
                  onMapCreated: (map) {
                    if (!mounted) return;
                    _map = map;
                    unawaited(_icons(scheme.primary));
                    _scheduleProjection();
                    if (route != null) {
                      unawaited(_fitRoute());
                    } else if (selected != null) {
                      unawaited(_fitDestination());
                    } else if (widget.location.hasCurrentFix) {
                      _centred = true;
                      unawaited(_centre());
                    }
                  },
                  onCameraMoveStarted: _cameraStarted,
                  onCameraIdle: _cameraIdle,
                  buildingsEnabled: false,
                  trafficEnabled: false,
                  indoorViewEnabled: false,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: false,
                  tiltGesturesEnabled: false,
                  markers: {
                    if (fix != null && precise && _yellowCloud != null)
                      Marker(
                        markerId: const MarkerId('you'),
                        position: LatLng(fix.latitude, fix.longitude),
                        icon: _yellowCloud!,
                        anchor: const Offset(.5, .5),
                        infoWindow: InfoWindow.noText,
                      ),
                    if (selected != null && _blueCloud != null)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: LatLng(
                          selected.point.latitude,
                          selected.point.longitude,
                        ),
                        icon: _blueCloud!,
                        anchor: const Offset(.5, .5),
                        infoWindow: InfoWindow.noText,
                      ),
                  },
                  circles: {
                    if (fix != null)
                      Circle(
                        circleId: const CircleId('uncertainty'),
                        center: LatLng(fix.latitude, fix.longitude),
                        radius: fix.accuracyMeters,
                        strokeWidth: 1,
                        strokeColor:
                            (precise ? scheme.primary : scheme.onSurfaceVariant)
                                .withValues(alpha: .5),
                        fillColor:
                            (precise ? scheme.primary : scheme.onSurfaceVariant)
                                .withValues(alpha: .08),
                      ),
                  },
                  polylines: {
                    if (route != null)
                      Polyline(
                        polylineId: const PolylineId('route-casing'),
                        points: _routePoints,
                        width: 10,
                        color: const Color(0xFF070809),
                        zIndex: 0,
                      ),
                    if (route != null)
                      Polyline(
                        polylineId: const PolylineId('verified-route'),
                        points: _routePoints,
                        width: 4,
                        color: scheme.primary,
                        jointType: JointType.round,
                        startCap: Cap.roundCap,
                        endCap: Cap.roundCap,
                        zIndex: 1,
                      ),
                  },
                ),
              ),
            ),
            if (_screenPath != null && _canFlow)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('route-preview-trace'),
                      painter: RoutePreviewTrace(
                        path: _screenPath!,
                        phase: _motion,
                        gold: scheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 14,
              left: 14,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101214),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFF34302A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.near_me_rounded,
                        size: 11,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        route == null ? 'NAVI MAP' : 'ROUTE PREVIEW',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 8,
                          letterSpacing: 1.2,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Column(
                children: [
                  if (route != null)
                    IconButton.filledTonal(
                      style: _controlStyle(scheme.primary),
                      tooltip: 'Show route',
                      onPressed: _fitRoute,
                      icon: const Icon(Icons.route_outlined, size: 19),
                    ),
                  if (widget.location.hasCurrentFix)
                    IconButton.filledTonal(
                      style: _controlStyle(scheme.primary),
                      tooltip: 'Re-centre',
                      onPressed: _centre,
                      icon: const Icon(Icons.my_location_rounded, size: 19),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  ButtonStyle _controlStyle(Color gold) => IconButton.styleFrom(
    foregroundColor: gold,
    backgroundColor: const Color(0xFF151719),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFF38352B)),
    ),
  );
}
