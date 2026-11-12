import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../location/application/location_controller.dart';
import '../../location/domain/location_gateway.dart';
import '../data/maps_configuration.dart';

/// Foreground location preview. No geocoding, route or arrival is implied.
class JourneyMapPreview extends ConsumerStatefulWidget {
  const JourneyMapPreview({super.key});

  @override
  ConsumerState<JourneyMapPreview> createState() => _JourneyMapPreviewState();
}

class _JourneyMapPreviewState extends ConsumerState<JourneyMapPreview>
    with WidgetsBindingObserver {
  static const _lagos = CameraPosition(
    target: LatLng(6.5244, 3.3792),
    zoom: 11,
  );
  GoogleMapController? _map;
  bool _centredOnce = false;
  bool _userMovedMap = false;
  bool _diagnostics = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's permission dialog temporarily makes the app inactive. Do not
    // invalidate the request before it returns; pause on actual backgrounding.
    if (state == AppLifecycleState.inactive) return;
    unawaited(
      ref
          .read(locationControllerProvider.notifier)
          .setVisible(state == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // GoogleMap owns and disposes its controller/platform view.
    _map = null;
    super.dispose();
  }

  Future<void> _centre(LocationState state) async {
    final map = _map;
    final fix = state.fix;
    if (map == null || fix == null || !state.hasCurrentFix) return;
    try {
      await map.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(fix.latitude, fix.longitude),
            zoom: state.quality == FixQuality.usable ? 16 : 13,
          ),
        ),
      );
    } on PlatformException {
      // A platform view may have been detached while camera animation completed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuration = ref.watch(mapsConfigurationProvider);
    final location = ref.watch(locationControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    ref.listen(locationControllerProvider, (_, next) {
      if (!_centredOnce &&
          !_userMovedMap &&
          next.hasCurrentFix &&
          _map != null) {
        _centredOnce = true;
        unawaited(_centre(next));
      }
    });

    return Container(
      key: const ValueKey('journey-map-preview'),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.map_outlined, size: 19, color: scheme.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Lagos, at a glance',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Navi',
                  ),
                  child: const Text('Map notices'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: configuration.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _mapUnavailable(),
              data: (value) => switch (value) {
                MapsConfiguration.ready => _buildMap(location, scheme),
                MapsConfiguration.missing => _mapUnavailable(),
                MapsConfiguration.unsupported => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Map preview is available on Android.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  location.caption,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  _explanation(location),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _locationAction(location),
                if (kDebugMode) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () =>
                        setState(() => _diagnostics = !_diagnostics),
                    child: Text(
                      _diagnostics
                          ? 'Hide location diagnostics'
                          : 'Location diagnostics',
                    ),
                  ),
                  if (_diagnostics) _LocationDiagnostics(state: location),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapUnavailable() => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'The map is unavailable right now.',
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _buildMap(LocationState location, ColorScheme scheme) {
    final fix = location.fix;
    final usable =
        location.hasCurrentFix && location.quality == FixQuality.usable;
    final colour = usable ? scheme.primary : scheme.onSurfaceVariant;
    return Listener(
      onPointerDown: (_) => _userMovedMap = true,
      child: GoogleMap(
        initialCameraPosition: _lagos,
        style: Theme.of(context).brightness == Brightness.dark
            ? _darkMapStyle
            : null,
        onMapCreated: (controller) {
          if (!mounted) return;
          _map = controller;
          final current = ref.read(locationControllerProvider);
          if (!_centredOnce && !_userMovedMap && current.hasCurrentFix) {
            _centredOnce = true;
            unawaited(_centre(current));
          }
        },
        // One location owner, so the SDK's independent blue-dot stream is off.
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: true,
        tiltGesturesEnabled: false,
        circles: {
          if (fix != null)
            Circle(
              circleId: const CircleId('position-uncertainty'),
              center: LatLng(fix.latitude, fix.longitude),
              radius: fix.accuracyMeters,
              fillColor: colour.withValues(alpha: 0.12),
              strokeColor: colour.withValues(alpha: 0.6),
              strokeWidth: 1,
            ),
        },
        markers: {
          if (fix != null && usable)
            Marker(
              markerId: const MarkerId('current-position'),
              position: LatLng(fix.latitude, fix.longitude),
              infoWindow: const InfoWindow(title: 'Estimated current position'),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow,
              ),
            ),
        },
      ),
    );
  }

  Widget _locationAction(LocationState location) {
    final controller = ref.read(locationControllerProvider.notifier);
    if (location.phase == LocationPhase.requesting ||
        location.phase == LocationPhase.acquiring) {
      return const LinearProgressIndicator();
    }
    if (location.phase == LocationPhase.deniedForever ||
        location.phase == LocationPhase.servicesOff ||
        location.approximate) {
      return OutlinedButton.icon(
        onPressed: controller.openSettings,
        icon: const Icon(Icons.settings_outlined, size: 17),
        label: const Text('Location settings'),
      );
    }
    if (location.hasCurrentFix) {
      return OutlinedButton.icon(
        onPressed: () => _centre(location),
        icon: const Icon(Icons.my_location_rounded, size: 17),
        label: const Text('Re-centre'),
      );
    }
    return OutlinedButton.icon(
      onPressed: location.phase == LocationPhase.suspended
          ? null
          : controller.enable,
      icon: const Icon(Icons.my_location_rounded, size: 17),
      label: Text(
        location.phase == LocationPhase.idle ? 'Use my location' : 'Try again',
      ),
    );
  }

  String _explanation(LocationState state) {
    if (state.phase == LocationPhase.denied ||
        state.phase == LocationPhase.deniedForever) {
      return 'You can still view the map. Location access lets Navi show your position.';
    }
    if (state.quality == FixQuality.stale) {
      return 'The last estimate is out of date. Navi cannot confirm your current position.';
    }
    if (state.quality == FixQuality.uncertain) {
      return 'The shaded area shows the reported uncertainty. An exact position is not confirmed.';
    }
    return 'Live position preview. Your destination and route still need to be confirmed.';
  }
}

class _LocationDiagnostics extends ConsumerWidget {
  const _LocationDiagnostics({required this.state});
  final LocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Refresh only the developer panel, including age while quality stays equal.
    return StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (value) => value),
      builder: (context, _) {
        final fix = state.fix;
        final age = fix?.ageAt(ref.read(locationClockProvider).elapsed);
        return Text(
          'State: ${state.phase.name} · quality: ${state.quality.name}\n'
          'Uncertainty: ${fix?.accuracyMeters.toStringAsFixed(0) ?? "—"} m · '
          'age: ${age == null ? "—" : (age.inMilliseconds / 1000).toStringAsFixed(1)} s',
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }
}

const _darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#151515"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#c8c4b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#151515"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38362f"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#756539"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#101e2a"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#20291e"}]}
]
''';
