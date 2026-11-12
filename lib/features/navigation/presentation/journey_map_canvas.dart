import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../location/application/location_controller.dart';
import '../../location/domain/location_gateway.dart';
import '../application/navigation_controller.dart';
import '../domain/navigation_gateway.dart';
import 'navi_map_style.dart';

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
    with WidgetsBindingObserver {
  GoogleMapController? _map;
  BitmapDescriptor? _yellowCloud, _blueCloud;
  RouteFlowSampler? _sampler;
  Timer? _flowTimer;
  double _progress = 0;
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
    _updateRoute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    _syncFlow();
  }

  @override
  void didUpdateWidget(JourneyMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigation.route != widget.navigation.route) {
      _updateRoute();
      if (!_userMovedMap && widget.navigation.route != null) {
        unawaited(_fitRoute());
      }
    }
    if (!_centred &&
        !_userMovedMap &&
        widget.location.hasCurrentFix &&
        _map != null) {
      _centred = true;
      unawaited(_centre());
    }
    _syncFlow();
  }

  void _updateRoute() {
    final points = widget.navigation.route?.points;
    _sampler = points == null ? null : RouteFlowSampler(points);
    _routePoints = points == null
        ? const []
        : List.unmodifiable(
            points.map((point) => LatLng(point.latitude, point.longitude)),
          );
    _progress = 0;
  }

  void _syncFlow() {
    final shouldFlow =
        _sampler != null &&
        widget.location.hasCurrentFix &&
        widget.location.quality == FixQuality.usable &&
        _foreground &&
        _visible &&
        !_reduceMotion;
    if (!shouldFlow) {
      _flowTimer?.cancel();
      _flowTimer = null;
      return;
    }
    _flowTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _progress = (_progress + 0.017) % 1);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncFlow();
  }

  Future<void> _centre() async {
    final fix = widget.location.fix;
    if (_map == null || fix == null || !widget.location.hasCurrentFix) return;
    try {
      await _map!.animateCamera(
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
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final point in route.points) {
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
      await _map!.animateCamera(
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
    _flowTimer?.cancel();
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
                if (route != null) {
                  unawaited(_fitRoute());
                } else if (widget.location.hasCurrentFix) {
                  _centred = true;
                  unawaited(_centre());
                }
              },
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
                    polylineId: const PolylineId('verified-route'),
                    points: _routePoints,
                    width: 4,
                    color: scheme.primary.withValues(alpha: .65),
                  ),
                if (_sampler != null && _flowTimer != null)
                  Polyline(
                    polylineId: const PolylineId('route-flow'),
                    points: [
                      for (final point in _sampler!.highlight(_progress * .92))
                        LatLng(point.latitude, point.longitude),
                    ],
                    width: 5,
                    color: _blue,
                    zIndex: 1,
                  ),
              },
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
                  tooltip: 'Show route',
                  onPressed: _fitRoute,
                  icon: const Icon(Icons.route_outlined, size: 19),
                ),
              if (widget.location.hasCurrentFix)
                IconButton.filledTonal(
                  tooltip: 'Re-centre',
                  onPressed: _centre,
                  icon: const Icon(Icons.my_location_rounded, size: 19),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
