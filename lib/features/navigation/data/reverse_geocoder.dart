import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/presentation/journey_controller.dart';
import '../../location/application/location_controller.dart';
import '../../voice/data/cloud_http_client.dart';
import '../domain/navigation_gateway.dart';
import '../domain/area_observation.dart';
import '../../location/domain/location_gateway.dart';
import 'direct_google_navigation_gateway.dart';

/// Lightweight reverse-geocoding helper that translates raw GPS fixes into
/// concise Lagos street/neighborhood labels while in active transit.
class ReverseGeocoder {
  ReverseGeocoder({
    required this.apiKey,
    required this.http,
    AppIdentityHeaderLoader? headerLoader,
  }) : _headerLoader = headerLoader ?? AndroidAppIdentity.resolveHeaders;

  final String apiKey;
  final GetCloudHttpTransport http;
  final AppIdentityHeaderLoader _headerLoader;

  Future<String?> lookupArea(GeoPoint point) async {
    if (apiKey.trim().isEmpty || !point.isValid) return null;
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${point.latitude},${point.longitude}',
        'result_type': 'street_address|route|neighborhood|sublocality|locality',
        'language': 'en',
        'key': apiKey,
      });
      final response = await http.getJson(
        uri: uri,
        headers: await _headerLoader(),
        timeout: const Duration(seconds: 5),
      );
      if (!response.isSuccess) return null;
      final data = jsonDecode(response.body);
      if (data is! Map) return null;
      final results = data['results'];
      if (results is! List || results.isEmpty) return null;
      String? bestLabel;
      var bestScore = -1;
      for (final item in results) {
        if (item is! Map) continue;
        final candidate = _scoreReadableLabel(item);
        if (candidate == null) continue;
        if (candidate.$2 > bestScore) {
          bestScore = candidate.$2;
          bestLabel = candidate.$1;
          if (bestScore >= 3) break;
        }
      }
      return bestLabel;
    } catch (_) {
      return null;
    }
  }

  static (String, int)? _scoreReadableLabel(Map result) {
    final components = result['address_components'];
    String? route;
    String? neighborhood;
    String? locality;
    if (components is List) {
      for (final raw in components) {
        if (raw is! Map) continue;
        final types = raw['types'];
        if (types is! List) continue;
        final name = '${raw['long_name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        if (route == null &&
            types.contains('route') &&
            !RegExp(r'^unnamed road$', caseSensitive: false).hasMatch(name)) {
          route = name;
        } else if (neighborhood == null &&
            (types.contains('neighborhood') ||
                types.contains('sublocality_level_1') ||
                types.contains('sublocality'))) {
          neighborhood = name;
        } else if (locality == null && types.contains('locality')) {
          locality = name;
        }
      }
    }
    final area = neighborhood ?? locality;
    if (route != null &&
        area != null &&
        route.toLowerCase() != area.toLowerCase()) {
      return ('$route, $area', neighborhood != null ? 3 : 2);
    }
    if (route != null) return (route, 2);
    if (neighborhood != null) return (neighborhood, 2);
    if (locality != null) return (locality, 1);

    final formatted = result['formatted_address']?.toString().trim() ?? '';
    if (formatted.isEmpty) return null;
    final cleaned = formatted
        .replaceFirst(RegExp(r'^[A-Z0-9]{4}\+[A-Z0-9]{2,3},\s*'), '')
        .replaceAll(RegExp(r',?\s*Nigeria$', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty ||
        RegExp(r'^unnamed road\b', caseSensitive: false).hasMatch(cleaned)) {
      return null;
    }
    final shortened = cleaned.length > 64
        ? cleaned.substring(0, 64).trim()
        : cleaned;
    return (shortened, 1);
  }
}

final reverseGeocoderProvider = FutureProvider<ReverseGeocoder?>((ref) async {
  final key = await CloudEnvConfig.resolveFirst(
    const ['GOOGLE_MAPS_API_KEY', 'GOOGLE_MAPS_API'],
    current: const String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: String.fromEnvironment('GOOGLE_MAPS_API'),
    ),
  );
  if (key.isEmpty) return null;
  final http = DartIoCloudHttpTransport();
  ref.onDispose(http.close);
  return ReverseGeocoder(apiKey: key, http: http);
});

/// One typed owner; this projection is the only current label used by UI/voice.
final currentAreaProvider = Provider<String?>(
  (ref) => ref.watch(currentAreaObservationProvider).currentLabel,
);
final currentAreaObservationProvider =
    NotifierProvider<CurrentAreaController, CurrentAreaState>(
      CurrentAreaController.new,
    );

class CurrentAreaController extends Notifier<CurrentAreaState> {
  static const _policy = AreaConfidencePolicy();
  Duration? _lastAttemptAt;
  GeoPoint? _lastLookupPoint;
  Timer? _ticker;
  bool _inFlight = false;
  bool _disposed = false;
  int _generation = 0;
  Duration get _now => ref.read(locationClockProvider).elapsed;

  @override
  CurrentAreaState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _ticker?.cancel();
    });
    ref.listen(
      journeyDraftProvider.select((draft) => (draft.identity, draft.isActive)),
      (_, _) {
        clear();
        _maybeRefresh(ref.read(locationControllerProvider));
      },
    );
    ref.listen(locationControllerProvider, (_, next) => _maybeRefresh(next));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _maybeRefresh(ref.read(locationControllerProvider));
    });
    Future.microtask(() {
      if (!_disposed) _maybeRefresh(ref.read(locationControllerProvider));
    });
    return const CurrentAreaState(AreaStatus.unavailable);
  }

  void clear() {
    _generation++;
    _lastLookupPoint = null;
    _lastAttemptAt = null;
    _inFlight = false;
    state = const CurrentAreaState(AreaStatus.unavailable);
  }

  bool _eligibleFix(LocationState location) =>
      location.phase == LocationPhase.tracking &&
      location.quality == FixQuality.usable &&
      _policy.acceptsFix(location.fix, _now, approximate: location.approximate);

  void _withdraw(AreaStatus status) {
    if (state.status != status) {
      state = CurrentAreaState(status, observation: state.observation);
    }
  }

  void _maybeRefresh(LocationState location) {
    if (_disposed || !ref.read(journeyDraftProvider).isActive) return;
    if (!_eligibleFix(location)) {
      _withdraw(
        location.phase == LocationPhase.tracking
            ? AreaStatus.uncertain
            : AreaStatus.unavailable,
      );
      return;
    }
    final fix = location.fix!;
    final observation = state.observation;
    if (observation != null &&
        state.status != AreaStatus.lookupFailed &&
        _policy.acceptsObservation(observation, fix, _now)) {
      _withdraw(AreaStatus.current);
      return;
    }
    if (state.status != AreaStatus.lookupFailed) {
      _withdraw(
        observation == null ? AreaStatus.unavailable : AreaStatus.stale,
      );
    }
    if (_inFlight) return;
    final previousAttempt = _lastAttemptAt;
    if (previousAttempt != null &&
        _now - previousAttempt < const Duration(seconds: 15))
      return;
    final point = GeoPoint(fix.latitude, fix.longitude);
    // Failed enrichment backs off. A genuinely new area can retry sooner.
    if (previousAttempt != null &&
        (state.status == AreaStatus.unavailable ||
            state.status == AreaStatus.lookupFailed) &&
        _lastLookupPoint != null &&
        _lastLookupPoint!.distanceTo(point) < 50 &&
        _now - previousAttempt < const Duration(seconds: 30))
      return;
    _inFlight = true;
    _lastAttemptAt = _now;
    _lastLookupPoint = point;
    final generation = _generation;
    unawaited(_performLookup(fix, _now, generation));
  }

  Future<void> _performLookup(
    LocationFix sourceFix,
    Duration timestamp,
    int generation,
  ) async {
    try {
      final geocoder = await ref.read(reverseGeocoderProvider.future);
      if (_disposed || generation != _generation) return;
      final label = await geocoder?.lookupArea(
        GeoPoint(sourceFix.latitude, sourceFix.longitude),
      );
      if (_disposed || generation != _generation) return;
      if (label == null || label.trim().isEmpty) {
        state = const CurrentAreaState(AreaStatus.lookupFailed);
        return;
      }
      final observation = AreaObservation(
        label: label.trim(),
        sourceFix: sourceFix,
        lookedUpAt: timestamp,
      );
      final location = ref.read(locationControllerProvider);
      final eligible =
          _eligibleFix(location) &&
          _policy.acceptsObservation(observation, location.fix!, _now);
      state = CurrentAreaState(
        eligible ? AreaStatus.current : AreaStatus.stale,
        observation: observation,
      );
    } catch (_) {
      if (!_disposed && generation == _generation) {
        state = const CurrentAreaState(AreaStatus.lookupFailed);
      }
    } finally {
      if (!_disposed && generation == _generation) _inFlight = false;
    }
  }
}
