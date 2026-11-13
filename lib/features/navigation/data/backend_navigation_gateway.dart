import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/domain/journey_draft.dart';
import '../../voice/data/cloud_http_client.dart';
import '../domain/navigation_gateway.dart';
import 'direct_google_navigation_gateway.dart';

final navigationGatewayProvider =
    FutureProvider.autoDispose<NavigationGateway?>((ref) async {
      final url = await CloudEnvConfig.resolveKey(
        'NAVI_BACKEND_URL',
        const String.fromEnvironment('NAVI_BACKEND_URL'),
      );
      final googleKey = await CloudEnvConfig.resolveFirst(
        const ['GOOGLE_MAPS_API_KEY', 'GOOGLE_MAPS_API'],
        current: const String.fromEnvironment(
          'GOOGLE_MAPS_API_KEY',
          defaultValue: String.fromEnvironment('GOOGLE_MAPS_API'),
        ),
      );

      if (url.isEmpty) {
        if (googleKey.isEmpty) return null;
        final http = DartIoCloudHttpTransport();
        ref.onDispose(http.close);
        return DirectGoogleNavigationGateway(apiKey: googleKey, http: http);
      }

      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        if (googleKey.isNotEmpty) {
          final http = DartIoCloudHttpTransport();
          ref.onDispose(http.close);
          return DirectGoogleNavigationGateway(apiKey: googleKey, http: http);
        }
        throw const NavigationFailure('not_configured');
      }
      final local =
          kDebugMode &&
          uri.scheme == 'http' &&
          const ['127.0.0.1', 'localhost', '::1'].contains(uri.host);
      if (uri.scheme != 'https' && !local) {
        if (googleKey.isNotEmpty) {
          final http = DartIoCloudHttpTransport();
          ref.onDispose(http.close);
          return DirectGoogleNavigationGateway(apiKey: googleKey, http: http);
        }
        throw const NavigationFailure('not_configured');
      }
      final http = DartIoCloudHttpTransport();
      ref.onDispose(http.close);
      final firebaseKey = await CloudEnvConfig.resolveKey(
        'NAVI_FIREBASE_API_KEY',
        const String.fromEnvironment('NAVI_FIREBASE_API_KEY'),
      );
      final backend = BackendNavigationGateway(
        base: uri,
        http: http,
        token: local ? null : FirebaseGuestToken(http, firebaseKey),
      );
      if (local && googleKey.isNotEmpty) {
        return FallbackNavigationGateway(
          primary: backend,
          fallback: DirectGoogleNavigationGateway(apiKey: googleKey, http: http),
        );
      }
      return backend;
    });

/// Guest-first authentication. Provider secrets never enter this client. Tokens
/// stay in memory and are refreshed in-session; no location history is stored.
class FirebaseGuestToken {
  FirebaseGuestToken(this.http, this.apiKey);
  final CloudHttpTransport http;
  final String apiKey;
  String? _token, _refreshToken;
  DateTime? _expires;
  Future<String>? _pending;

  Future<String> get() async {
    if (_token != null && DateTime.now().isBefore(_expires!)) return _token!;
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  Future<String> _fetch() async {
    if (apiKey.isEmpty) throw const NavigationFailure('not_configured');
    if (_refreshToken != null && http is! FormCloudHttpTransport) {
      throw const NavigationFailure('unauthorized');
    }
    // Firebase refresh uses form encoding; sign-up obtains a fresh anonymous
    // token when this app process has no identity yet.
    final response = _refreshToken == null
        ? await http.postJson(
            uri: Uri.https(
              'identitytoolkit.googleapis.com',
              '/v1/accounts:signUp',
              {'key': apiKey},
            ),
            headers: const {},
            body: const {'returnSecureToken': true},
          )
        : await (http as FormCloudHttpTransport).postForm(
            uri: Uri.https('securetoken.googleapis.com', '/v1/token', {
              'key': apiKey,
            }),
            fields: {
              'grant_type': 'refresh_token',
              'refresh_token': _refreshToken!,
            },
          );
    if (!response.isSuccess) throw const NavigationFailure('unauthorized');
    final data = jsonDecode(response.body);
    if (data is! Map) throw const NavigationFailure('unauthorized');
    final token = data['idToken'] ?? data['id_token'];
    final refresh = data['refreshToken'] ?? data['refresh_token'];
    final ttl = int.tryParse('${data['expiresIn'] ?? data['expires_in']}');
    if (token is! String ||
        token.isEmpty ||
        refresh is! String ||
        ttl == null ||
        ttl < 120) {
      throw const NavigationFailure('unauthorized');
    }
    _token = token;
    _refreshToken = refresh;
    _expires = DateTime.now().add(Duration(seconds: ttl - 60));
    return token;
  }
}

class BackendNavigationGateway implements NavigationGateway {
  BackendNavigationGateway({
    required this.base,
    required this.http,
    this.token,
  });
  final Uri base;
  final CloudHttpTransport http;
  final FirebaseGuestToken? token;

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final bearer = await token?.get();
      final response = await http.postJson(
        uri: base.replace(
          path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
        ),
        headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
        body: body,
        timeout: const Duration(seconds: 20),
      );
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const NavigationFailure('invalid_response');
      }
      if (!response.isSuccess) {
        final error = data['error'];
        throw NavigationFailure(
          error is Map && error['code'] is String
              ? error['code'] as String
              : 'unavailable',
        );
      }
      return data;
    } on NavigationFailure {
      rethrow;
    } catch (_) {
      throw const NavigationFailure('unavailable');
    }
  }

  @override
  Future<List<DestinationPlace>> search(String query) async {
    final data = await _post('/v1/places/search', {'query': query});
    final raw = data['places'];
    if (raw is! List || raw.length > 5) {
      throw const NavigationFailure('invalid_response');
    }
    final places = <DestinationPlace>[];
    for (final item in raw) {
      if (item is! Map ||
          item['id'] is! String ||
          item['name'] is! String ||
          item['address'] is! String ||
          item['latitude'] is! num ||
          item['longitude'] is! num) {
        throw const NavigationFailure('invalid_response');
      }
      final point = GeoPoint(
        (item['latitude'] as num).toDouble(),
        (item['longitude'] as num).toDouble(),
      );
      if (!point.isValid) throw const NavigationFailure('invalid_response');
      places.add(
        DestinationPlace(
          id: item['id'] as String,
          name: item['name'] as String,
          address: item['address'] as String,
          point: point,
        ),
      );
    }
    return List.unmodifiable(places);
  }

  @override
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  }) async {
    final data = await _post('/v1/routes/plan', {
      'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
      'placeId': destination.id,
      'mode': mode.name,
    });
    final encoded = data['encodedPolyline'];
    final distance = data['distanceMeters'];
    final duration = data['durationSeconds'];
    final expires = DateTime.tryParse('${data['expiresAt']}');
    if (encoded is! String ||
        distance is! num ||
        duration is! num ||
        !distance.isFinite ||
        distance < 0 ||
        !duration.isFinite ||
        duration < 0 ||
        data['mode'] != mode.name ||
        expires == null ||
        !expires.isAfter(DateTime.now())) {
      throw const NavigationFailure('invalid_response');
    }
    return JourneyRoute(
      points: decodeRoutePolyline(encoded),
      origin: origin,
      mode: mode,
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
      expiresAt: expires,
    );
  }
}
