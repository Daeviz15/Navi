import 'dart:convert';

import '../../journey/domain/journey_draft.dart';
import '../../voice/data/cloud_http_client.dart';
import '../domain/navigation_gateway.dart';

typedef AppIdentityHeaderLoader = Future<Map<String, String>> Function();

/// Calls Google Places (New) and Google Routes APIs directly from the client
/// using an Android-restricted Google Maps Platform key (`X-Android-Package`
/// and `X-Android-Cert`), matching the backend service's Lagos bounds and
/// schema without requiring a hosted backend during local/device runs.
class DirectGoogleNavigationGateway implements NavigationGateway {
  DirectGoogleNavigationGateway({
    required this.apiKey,
    required this.http,
    AppIdentityHeaderLoader? headerLoader,
  }) : _headerLoader = headerLoader ?? AndroidAppIdentity.resolveHeaders;

  static final _placesSearchEndpoint = Uri.parse(
    'https://places.googleapis.com/v1/places:searchText',
  );
  static final _routesEndpoint = Uri.parse(
    'https://routes.googleapis.com/directions/v2:computeRoutes',
  );

  final String apiKey;
  final CloudHttpTransport http;
  final AppIdentityHeaderLoader _headerLoader;

  Future<Map<String, String>> _headers(String fieldMask) async {
    final identity = await _headerLoader();
    return {
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': fieldMask,
      ...identity,
    };
  }

  @override
  Future<List<DestinationPlace>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    if (apiKey.trim().isEmpty) {
      throw const NavigationFailure('not_configured');
    }
    try {
      final response = await http.postJson(
        uri: _placesSearchEndpoint,
        headers: await _headers(
          'places.id,places.displayName,places.formattedAddress,places.location,places.addressComponents',
        ),
        body: {
          'textQuery': '$trimmed Lagos Nigeria',
          'regionCode': 'NG',
          'languageCode': 'en',
          'pageSize': 5,
          'locationBias': const {
            'circle': {
              'center': {'latitude': 6.5244, 'longitude': 3.3792},
              'radius': 50000.0,
            },
          },
        },
        timeout: const Duration(seconds: 12),
      );
      _throwForHttpFailure(response);
      final data = jsonDecode(response.body);
      if (data is! Map) throw const NavigationFailure('invalid_response');
      final rawPlaces = data['places'];
      if (rawPlaces == null) return const [];
      if (rawPlaces is! List) {
        throw const NavigationFailure('invalid_response');
      }
      final results = <DestinationPlace>[];
      for (final item in rawPlaces.take(5)) {
        final parsed = _parsePlace(item);
        if (parsed != null) results.add(parsed);
      }
      return List<DestinationPlace>.unmodifiable(results);
    } on NavigationFailure {
      rethrow;
    } catch (_) {
      throw const NavigationFailure('unavailable');
    }
  }

  @override
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const NavigationFailure('not_configured');
    }
    if (!_withinLagosWindow(origin)) {
      throw const NavigationFailure('outside_service_area');
    }
    if (mode == TravelMode.walking) {
      final walkRoute = await _computeRoute(
        origin: origin,
        destination: destination,
        googleTravelMode: 'WALK',
        appMode: mode,
        isRoadFallback: false,
      );
      if (walkRoute == null) throw const NavigationFailure('no_route');
      return walkRoute;
    }
    // Prefer scheduled bus transit first; if Google lacks GTFS bus coverage in
    // parts of Lagos, transparently fall back to the real traffic-aware road
    // corridor so map directions, ETA, and blue route animation still work.
    final busTransit = await _computeRoute(
      origin: origin,
      destination: destination,
      googleTravelMode: 'TRANSIT',
      appMode: mode,
      isRoadFallback: false,
    );
    if (busTransit != null) return busTransit;
    final roadCorridor = await _computeRoute(
      origin: origin,
      destination: destination,
      googleTravelMode: 'DRIVE',
      appMode: mode,
      isRoadFallback: true,
    );
    if (roadCorridor == null) throw const NavigationFailure('no_route');
    return roadCorridor;
  }

  Future<JourneyRoute?> _computeRoute({
    required GeoPoint origin,
    required DestinationPlace destination,
    required String googleTravelMode,
    required TravelMode appMode,
    required bool isRoadFallback,
  }) async {
    try {
      final response = await http.postJson(
        uri: _routesEndpoint,
        headers: await _headers(
          'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,'
          'routes.legs.steps.travelMode,routes.legs.steps.distanceMeters,'
          'routes.legs.steps.navigationInstruction,routes.legs.steps.transitDetails.stopDetails,'
          'routes.legs.steps.transitDetails.transitLine.vehicle.type',
        ),
        body: {
          'origin': {
            'location': {
              'latLng': {
                'latitude': origin.latitude,
                'longitude': origin.longitude,
              },
            },
          },
          'destination': _destinationTarget(destination),
          'travelMode': googleTravelMode,
          'languageCode': 'en',
          'units': 'METRIC',
          'computeAlternativeRoutes': false,
          if (googleTravelMode == 'TRANSIT')
            'transitPreferences': const {
              'allowedTravelModes': ['BUS'],
            },
          if (googleTravelMode == 'DRIVE')
            'routingPreference': 'TRAFFIC_AWARE',
        },
        timeout: const Duration(seconds: 14),
      );
      _throwForHttpFailure(response);
      final data = jsonDecode(response.body);
      if (data is! Map) throw const NavigationFailure('invalid_response');
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final first = routes.first;
      if (first is! Map) throw const NavigationFailure('invalid_response');

      if (googleTravelMode == 'TRANSIT' && !_hasValidBusTransit(first)) {
        return null;
      }

      final distance = first['distanceMeters'];
      final rawDuration = first['duration'];
      final polyline = first['polyline'];
      final encoded = polyline is Map ? polyline['encodedPolyline'] : null;
      final durationSeconds = _parseDurationSeconds(rawDuration);
      if (distance is! num ||
          !distance.isFinite ||
          distance < 0 ||
          durationSeconds == null ||
          encoded is! String) {
        throw const NavigationFailure('invalid_response');
      }

      return JourneyRoute(
        points: decodeRoutePolyline(encoded),
        origin: origin,
        mode: appMode,
        distanceMeters: distance.toDouble(),
        durationSeconds: durationSeconds,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        isRoadFallback: isRoadFallback,
        stepHints: _extractStepHints(first),
      );
    } on NavigationFailure {
      rethrow;
    } catch (_) {
      throw const NavigationFailure('unavailable');
    }
  }

  Map<String, Object?> _destinationTarget(DestinationPlace destination) {
    final validPlaceId = RegExp(
      r'^[a-zA-Z0-9_-]{4,}$',
    ).hasMatch(destination.id);
    if (validPlaceId) {
      return {'placeId': destination.id};
    }
    return {
      'location': {
        'latLng': {
          'latitude': destination.point.latitude,
          'longitude': destination.point.longitude,
        },
      },
    };
  }

  void _throwForHttpFailure(CloudHttpResponse response) {
    if (response.isSuccess) return;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const NavigationFailure('unauthorized');
    }
    if (response.statusCode == 429) {
      throw const NavigationFailure('provider_rate_limited');
    }
    throw const NavigationFailure('unavailable');
  }

  DestinationPlace? _parsePlace(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final display = raw['displayName'];
    final name = display is Map ? display['text'] : null;
    final address = raw['formattedAddress'];
    final location = raw['location'];
    final lat = location is Map ? location['latitude'] : null;
    final lng = location is Map ? location['longitude'] : null;
    if (id is! String ||
        name is! String ||
        address is! String ||
        lat is! num ||
        lng is! num) {
      return null;
    }
    final point = GeoPoint(lat.toDouble(), lng.toDouble());
    if (!point.isValid) return null;
    final components = raw['addressComponents'];
    if (!_isLagosPlace(components, address, point)) return null;
    return DestinationPlace(id: id, name: name, address: address, point: point);
  }

  bool _isLagosPlace(Object? components, String address, GeoPoint point) {
    if (components is List && components.isNotEmpty) {
      var hasCountryNg = false;
      var hasLagosState = false;
      for (final item in components) {
        if (item is! Map) continue;
        final types = item['types'];
        if (types is! List) continue;
        final shortText = '${item['shortText'] ?? ''}'.trim();
        final longText = '${item['longText'] ?? ''}'.trim();
        if (types.contains('country') && shortText == 'NG') {
          hasCountryNg = true;
        }
        if (types.contains('administrative_area_level_1') &&
            RegExp(
              r'^lagos(?:\s+state)?$',
              caseSensitive: false,
            ).hasMatch(longText.isNotEmpty ? longText : shortText)) {
          hasLagosState = true;
        }
      }
      if (hasCountryNg && hasLagosState) return true;
    }
    return _withinLagosWindow(point) &&
        RegExp(r'\blagos\b', caseSensitive: false).hasMatch(address);
  }

  static bool _withinLagosWindow(GeoPoint p) =>
      p.latitude >= 6.2 &&
      p.latitude <= 6.9 &&
      p.longitude >= 2.6 &&
      p.longitude <= 4.6;

  static double? _parseDurationSeconds(Object? raw) {
    if (raw is num) {
      return raw.isFinite && raw >= 0 ? raw.toDouble() : null;
    }
    if (raw is! String) return null;
    final match = RegExp(r'^(\d+(?:\.\d+)?)s$').firstMatch(raw.trim());
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  static bool _hasValidBusTransit(Map route) {
    final legs = route['legs'];
    if (legs is! List) return false;
    var hasBus = false;
    for (final leg in legs) {
      if (leg is! Map) continue;
      final steps = leg['steps'];
      if (steps is! List) continue;
      for (final step in steps) {
        if (step is! Map) continue;
        if (step['travelMode'] != 'TRANSIT') continue;
        final transit = step['transitDetails'];
        final line = transit is Map ? transit['transitLine'] : null;
        final vehicle = line is Map ? line['vehicle'] : null;
        final type = vehicle is Map ? vehicle['type'] : null;
        if (type != 'BUS') return false;
        hasBus = true;
      }
    }
    return hasBus;
  }

  static List<String> _extractStepHints(Map route) {
    final legs = route['legs'];
    if (legs is! List) return const <String>[];
    final hints = <String>[];
    for (final leg in legs) {
      if (leg is! Map) continue;
      final steps = leg['steps'];
      if (steps is! List) continue;
      for (final step in steps) {
        if (step is! Map) continue;
        final transit = step['transitDetails'];
        if (transit is Map) {
          final stopDetails = transit['stopDetails'];
          if (stopDetails is Map) {
            final dep = stopDetails['departureStop'];
            final arr = stopDetails['arrivalStop'];
            final depName = dep is Map ? dep['name']?.toString().trim() : null;
            final arrName = arr is Map ? arr['name']?.toString().trim() : null;
            if (depName != null &&
                depName.isNotEmpty &&
                arrName != null &&
                arrName.isNotEmpty) {
              hints.add('Take bus from $depName toward $arrName');
              if (hints.length >= 5) break;
              continue;
            }
          }
        }
        final nav = step['navigationInstruction'];
        final rawInstruction = nav is Map
            ? nav['instructions']?.toString().replaceAll(RegExp(r'\s+'), ' ').trim()
            : null;
        if (rawInstruction != null && rawInstruction.isNotEmpty) {
          hints.add(rawInstruction);
          if (hints.length >= 5) break;
        }
      }
      if (hints.length >= 5) break;
    }
    return List<String>.unmodifiable(hints);
  }
}

/// Tries the primary backend gateway first and falls back to direct Google
/// Maps APIs only when the primary backend connection is unreachable.
class FallbackNavigationGateway implements NavigationGateway {
  const FallbackNavigationGateway({
    required this.primary,
    required this.fallback,
  });

  final NavigationGateway primary;
  final NavigationGateway fallback;

  @override
  Future<List<DestinationPlace>> search(String query) async {
    try {
      return await primary.search(query);
    } on NavigationFailure catch (error) {
      if (error.code == 'unavailable') {
        return fallback.search(query);
      }
      rethrow;
    }
  }

  @override
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  }) async {
    try {
      return await primary.plan(
        origin: origin,
        destination: destination,
        mode: mode,
      );
    } on NavigationFailure catch (error) {
      if (error.code == 'unavailable') {
        return fallback.plan(
          origin: origin,
          destination: destination,
          mode: mode,
        );
      }
      rethrow;
    }
  }
}

