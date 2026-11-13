import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/presentation/journey_controller.dart';
import '../../location/application/location_controller.dart';
import '../../voice/data/cloud_http_client.dart';
import '../domain/navigation_gateway.dart';
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

final currentAreaProvider = NotifierProvider<CurrentAreaController, String?>(
  CurrentAreaController.new,
);

/// Maintains a throttled human-readable area label for the user's current fix
/// while an active trip is running.
class CurrentAreaController extends Notifier<String?> {
  GeoPoint? _lastLookupPoint;
  DateTime? _lastLookupAt;
  bool _inFlight = false;
  bool _disposed = false;
  int _generation = 0;

  @override
  String? build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    ref.listen(
      journeyDraftProvider.select((draft) => (draft.identity, draft.isActive)),
      (_, _) {
        clear();
        _maybeRefresh(ref.read(locationControllerProvider));
      },
    );
    ref.listen(locationControllerProvider, (_, next) {
      _maybeRefresh(next);
    });
    Future.microtask(() {
      if (!_disposed) _maybeRefresh(ref.read(locationControllerProvider));
    });
    return null;
  }

  void clear() {
    _generation++;
    _lastLookupPoint = null;
    _lastLookupAt = null;
    _inFlight = false;
    state = null;
  }

  void _maybeRefresh(LocationState location) {
    if (_disposed || !ref.read(journeyDraftProvider).isActive) return;
    if (!location.hasCurrentFix || location.fix == null) return;
    final point = GeoPoint(location.fix!.latitude, location.fix!.longitude);
    if (!point.isValid) return;

    final now = DateTime.now();
    final previous = _lastLookupPoint;
    if (previous != null) {
      final moved = previous.distanceTo(point);
      final stale =
          _lastLookupAt == null ||
          now.difference(_lastLookupAt!) > const Duration(seconds: 90);
      if (moved < 150 && !(stale && moved >= 50)) return;
    }
    if (_inFlight) return;
    _inFlight = true;
    final generation = _generation;
    unawaited(_performLookup(point, now, generation));
  }

  Future<void> _performLookup(
    GeoPoint point,
    DateTime timestamp,
    int generation,
  ) async {
    try {
      final geocoder = await ref.read(reverseGeocoderProvider.future);
      if (_disposed || generation != _generation || geocoder == null) return;
      final label = await geocoder.lookupArea(point);
      if (_disposed || generation != _generation) return;
      _lastLookupPoint = point;
      _lastLookupAt = timestamp;
      if (label != null && label.isNotEmpty) {
        state = label;
      }
    } catch (_) {
      // Reverse geocoding enrichment must never surface errors or break UX.
    } finally {
      // An old trip's lookup must not unlock a newer trip's in-flight request.
      if (!_disposed && generation == _generation) _inFlight = false;
    }
  }
}
