import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/navigation/data/backend_navigation_gateway.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/voice/data/cloud_http_client.dart';

void main() {
  test(
    'route provenance is required, and driving previews cannot carry a bus ETA',
    () async {
      final http = _Http();
      final gateway = BackendNavigationGateway(
        base: Uri.parse('https://navi.example'),
        http: http,
      );
      const place = DestinationPlace(
        id: 'abc',
        name: 'Lekki',
        address: 'Lagos',
        point: GeoPoint(6.45, 3.47),
      );
      final valid = <String, Object?>{
        'encodedPolyline': '_p~iF~ps|U_ulLnnqC',
        'mode': 'bus',
        'distanceMeters': 1000,
        'durationSeconds': null,
        'kind': 'road_corridor',
        'source': 'google_routes',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      };
      for (final invalid in [
        {...valid, 'kind': null},
        {...valid, 'kind': 'walking'},
        {...valid, 'source': null},
        {...valid, 'source': 'unknown'},
        {...valid, 'kind': 'bus_transit'},
        {...valid, 'durationSeconds': 300},
      ]) {
        http.responses.add(CloudHttpResponse(200, jsonEncode(invalid)));
        await expectLater(
          gateway.plan(
            origin: const GeoPoint(6.52, 3.37),
            destination: place,
            mode: TravelMode.bus,
          ),
          throwsA(isA<NavigationFailure>()),
        );
      }
      http.responses.add(CloudHttpResponse(200, jsonEncode(valid)));
      final route = await gateway.plan(
        origin: const GeoPoint(6.52, 3.37),
        destination: place,
        mode: TravelMode.bus,
      );
      expect(route.kind, RouteKind.roadCorridor);
      expect(route.durationSeconds, isNull);
      http.responses.add(
        CloudHttpResponse(
          200,
          jsonEncode({...valid, 'kind': 'bus_transit', 'durationSeconds': 300}),
        ),
      );
      final bus = await gateway.plan(
        origin: const GeoPoint(6.52, 3.37),
        destination: place,
        mode: TravelMode.bus,
      );
      expect(bus.kind, RouteKind.busTransit);
      expect(bus.durationSeconds, 300);
    },
  );
  test(
    'loopback search sends no embedded provider key and preserves API path prefix',
    () async {
      final http = _Http()
        ..responses.add(
          const CloudHttpResponse(
            200,
            '{"places":[{"id":"abc","name":"Lekki","address":"Lagos","latitude":6.45,"longitude":3.47}]}',
          ),
        );
      final gateway = BackendNavigationGateway(
        base: Uri.parse('http://127.0.0.1:8080/api/'),
        http: http,
      );
      final places = await gateway.search('Lekki');
      expect(http.uri!.path, '/api/v1/places/search');
      expect(http.headers, isEmpty);
      expect(http.body, {'query': 'Lekki'});
      expect(places.single.point.longitude, 3.47);
    },
  );

  test(
    'guest authentication is single-flight, cached and attached as a bearer token',
    () async {
      final http = _Http();
      final pending = Completer<CloudHttpResponse>();
      http.pending = pending;
      final token = FirebaseGuestToken(http, 'public-project-key');
      final first = token.get();
      final second = token.get();
      expect(http.calls, 1);
      expect(http.uri!.host, 'identitytoolkit.googleapis.com');
      expect(http.body, {'returnSecureToken': true});
      pending.complete(
        const CloudHttpResponse(
          200,
          '{"idToken":"guest-token","refreshToken":"refresh","expiresIn":"3600"}',
        ),
      );
      expect(await first, 'guest-token');
      expect(await second, 'guest-token');
      http.pending = null;
      http.responses.add(const CloudHttpResponse(200, '{"places":[]}'));
      final gateway = BackendNavigationGateway(
        base: Uri.parse('https://navi.example'),
        http: http,
        token: token,
      );
      await gateway.search('Yaba');
      expect(http.calls, 2);
      expect(http.headers, {'Authorization': 'Bearer guest-token'});
    },
  );

  test(
    'invalid JSON, coordinates and server errors never become confirmed places',
    () async {
      final http = _Http();
      final gateway = BackendNavigationGateway(
        base: Uri.parse('https://navi.example'),
        http: http,
      );
      for (final response in [
        const CloudHttpResponse(200, '<html>offline</html>'),
        const CloudHttpResponse(
          200,
          '{"places":[{"id":"abc","name":"bad","address":"bad","latitude":1234,"longitude":3}]}',
        ),
        const CloudHttpResponse(
          503,
          '{"error":{"code":"provider_not_configured"}}',
        ),
      ]) {
        http.responses.add(response);
        await expectLater(
          gateway.search('Lekki'),
          throwsA(isA<NavigationFailure>()),
        );
      }
    },
  );

  test(
    'mismatched travel mode and expired routes never reach the map',
    () async {
      final http = _Http();
      final gateway = BackendNavigationGateway(
        base: Uri.parse('https://navi.example'),
        http: http,
      );
      const place = DestinationPlace(
        id: 'abc',
        name: 'Lekki',
        address: 'Lagos',
        point: GeoPoint(6.45, 3.47),
      );
      for (final mode in ['bus', 'walking']) {
        http.responses.add(
          CloudHttpResponse(
            200,
            jsonEncode({
              'encodedPolyline': '_p~iF~ps|U_ulLnnqC',
              'mode': mode,
              'distanceMeters': 1000,
              'durationSeconds': 300,
              'kind': 'walking',
              'source': 'google_routes',
              'expiresAt':
                  (mode == 'bus'
                          ? DateTime.now().add(const Duration(minutes: 5))
                          : DateTime.now().subtract(const Duration(minutes: 5)))
                      .toIso8601String(),
            }),
          ),
        );
        await expectLater(
          gateway.plan(
            origin: const GeoPoint(6.52, 3.37),
            destination: place,
            mode: TravelMode.walking,
          ),
          throwsA(isA<NavigationFailure>()),
        );
      }
    },
  );
}

class _Http implements CloudHttpTransport {
  final responses = Queue<CloudHttpResponse>();
  Completer<CloudHttpResponse>? pending;
  int calls = 0;
  Uri? uri;
  Map<String, String>? headers;
  Map<String, Object?>? body;
  @override
  Future<CloudHttpResponse> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
  }) {
    calls++;
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return pending?.future ?? Future.value(responses.removeFirst());
  }

  @override
  Future<CloudHttpResponse> postMultipart({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required String contentType,
    required Uint8List fileBytes,
    Duration timeout = const Duration(seconds: 10),
  }) => throw UnimplementedError();
  @override
  void close() {}

  @override
  Future<CloudHttpBytesResponse> postJsonBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
    int maxBytes = 4194304,
  }) => throw UnimplementedError();
}
