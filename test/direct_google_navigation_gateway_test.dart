import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/domain/journey_draft.dart';
import 'package:navi/features/navigation/data/direct_google_navigation_gateway.dart';
import 'package:navi/features/navigation/data/reverse_geocoder.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/voice/data/cloud_http_client.dart';

void main() {
  const androidHeaders = {
    'X-Android-Package': 'com.example.navi',
    'X-Android-Cert': 'abcdef123456',
  };

  group('DirectGoogleNavigationGateway', () {
    test(
      'search sends Android identity headers and filters Lagos places',
      () async {
        final http = _StubHttp(
          postResponses: [
            CloudHttpResponse(
              200,
              jsonEncode({
                'places': [
                  {
                    'id': 'lagos-mtn',
                    'displayName': {'text': 'MTN Office Ikeja'},
                    'formattedAddress': 'Opebi Rd, Ikeja, Lagos, Nigeria',
                    'location': {'latitude': 6.596, 'longitude': 3.356},
                    'addressComponents': [
                      {
                        'shortText': 'NG',
                        'types': ['country'],
                      },
                      {
                        'longText': 'Lagos',
                        'types': ['administrative_area_level_1'],
                      },
                    ],
                  },
                  {
                    'id': 'abuja-place',
                    'displayName': {'text': 'Abuja Office'},
                    'formattedAddress': 'Wuse, Abuja, Nigeria',
                    'location': {'latitude': 9.076, 'longitude': 7.495},
                    'addressComponents': [
                      {
                        'shortText': 'NG',
                        'types': ['country'],
                      },
                      {
                        'longText': 'Federal Capital Territory',
                        'types': ['administrative_area_level_1'],
                      },
                    ],
                  },
                ],
              }),
            ),
          ],
        );
        final gateway = DirectGoogleNavigationGateway(
          apiKey: 'test-maps-key',
          http: http,
          headerLoader: () async => androidHeaders,
        );

        final places = await gateway.search('MTN office, Ikeja');
        expect(places, hasLength(1));
        expect(places.single.id, 'lagos-mtn');
        expect(places.single.name, 'MTN Office Ikeja');
        expect(http.lastHeaders?['X-Goog-Api-Key'], 'test-maps-key');
        expect(http.lastHeaders?['X-Android-Package'], 'com.example.navi');
        expect(http.lastHeaders?['X-Android-Cert'], 'abcdef123456');
      },
    );

    test(
      'bus mode falls back to road corridor when GTFS transit routes are empty',
      () async {
        final http = _StubHttp(
          postResponses: [
            const CloudHttpResponse(200, '{"routes": []}'),
            CloudHttpResponse(
              200,
              jsonEncode({
                'routes': [
                  {
                    'distanceMeters': 4200,
                    'duration': '720s',
                    'polyline': {'encodedPolyline': 'ki~e@}|xSq`@y`@'},
                    'legs': [
                      {
                        'steps': [
                          {
                            'travelMode': 'DRIVE',
                            'navigationInstruction': {
                              'instructions': 'Head north toward Admiralty Way',
                            },
                          },
                        ],
                      },
                    ],
                  },
                ],
              }),
            ),
          ],
        );
        final gateway = DirectGoogleNavigationGateway(
          apiKey: 'test-maps-key',
          http: http,
          headerLoader: () async => androidHeaders,
        );
        const dest = DestinationPlace(
          id: 'ChIJ_valid_id',
          name: 'Lekki Phase 1',
          address: 'Lekki, Lagos',
          point: GeoPoint(6.45, 3.47),
        );

        final route = await gateway.plan(
          origin: const GeoPoint(6.44, 3.46),
          destination: dest,
          mode: TravelMode.bus,
        );
        expect(http.postedBodies, hasLength(2));
        expect(http.postedBodies.first['travelMode'], 'TRANSIT');
        expect(http.postedBodies.last['travelMode'], 'DRIVE');
        expect(route.mode, TravelMode.bus);
        expect(route.isRoadFallback, isTrue);
        expect(route.kind, RouteKind.roadCorridor);
        expect(route.durationSeconds, isNull);
        expect(route.stepHints, isEmpty);
      },
    );

    test(
      'maps auth and quota failures to typed NavigationFailure codes',
      () async {
        final http = _StubHttp(
          postResponses: [
            const CloudHttpResponse(
              403,
              '{"error":{"status":"PERMISSION_DENIED"}}',
            ),
            const CloudHttpResponse(
              429,
              '{"error":{"status":"RESOURCE_EXHAUSTED"}}',
            ),
          ],
        );
        final gateway = DirectGoogleNavigationGateway(
          apiKey: 'test-maps-key',
          http: http,
          headerLoader: () async => androidHeaders,
        );

        await expectLater(
          gateway.search('Lekki'),
          throwsA(
            isA<NavigationFailure>().having(
              (e) => e.code,
              'code',
              'unauthorized',
            ),
          ),
        );
        await expectLater(
          gateway.search('Lekki'),
          throwsA(
            isA<NavigationFailure>().having(
              (e) => e.code,
              'code',
              'provider_rate_limited',
            ),
          ),
        );
      },
    );
  });

  group('FallbackNavigationGateway', () {
    test(
      'falls back to direct gateway only when primary backend is unavailable',
      () async {
        final fallback = DirectGoogleNavigationGateway(
          apiKey: 'test-maps-key',
          http: _StubHttp(
            postResponses: [
              CloudHttpResponse(
                200,
                jsonEncode({
                  'places': [
                    {
                      'id': 'p1',
                      'displayName': {'text': 'Ologolo'},
                      'formattedAddress': 'Ologolo, Lekki, Lagos, Nigeria',
                      'location': {'latitude': 6.44, 'longitude': 3.51},
                      'addressComponents': [
                        {
                          'shortText': 'NG',
                          'types': ['country'],
                        },
                        {
                          'longText': 'Lagos',
                          'types': ['administrative_area_level_1'],
                        },
                      ],
                    },
                  ],
                }),
              ),
            ],
          ),
          headerLoader: () async => androidHeaders,
        );
        final gateway = FallbackNavigationGateway(
          primary: _ThrowingGateway('unavailable'),
          fallback: fallback,
        );

        final places = await gateway.search('Ologolo');
        expect(places.single.name, 'Ologolo');

        const strict = FallbackNavigationGateway(
          primary: _ThrowingGateway('outside_service_area'),
          fallback: _ThrowingGateway('unavailable'),
        );
        await expectLater(
          strict.search('Abuja'),
          throwsA(
            isA<NavigationFailure>().having(
              (e) => e.code,
              'code',
              'outside_service_area',
            ),
          ),
        );
      },
    );
  });

  group('ReverseGeocoder & JourneyRoute progress', () {
    test(
      'extracts concise street + neighborhood label while ignoring unnamed roads',
      () async {
        final http = _StubHttp(
          getResponses: [
            CloudHttpResponse(
              200,
              jsonEncode({
                'results': [
                  {
                    'formatted_address': 'Unnamed Road, Lagos, Nigeria',
                    'address_components': [
                      {
                        'long_name': 'Unnamed Road',
                        'types': ['route'],
                      },
                      {
                        'long_name': 'Lagos',
                        'types': ['locality'],
                      },
                    ],
                  },
                  {
                    'formatted_address':
                        'Admiralty Way, Lekki Phase I, Lagos, Nigeria',
                    'address_components': [
                      {
                        'long_name': 'Admiralty Way',
                        'types': ['route'],
                      },
                      {
                        'long_name': 'Lekki Phase I',
                        'types': ['neighborhood'],
                      },
                    ],
                  },
                ],
              }),
            ),
          ],
        );
        final geocoder = ReverseGeocoder(
          apiKey: 'test-key',
          http: http,
          headerLoader: () async => androidHeaders,
        );

        final label = await geocoder.lookupArea(const GeoPoint(6.4474, 3.4731));
        expect(label, 'Admiralty Way, Lekki Phase I');
        expect(http.lastHeaders?['X-Android-Package'], 'com.example.navi');
      },
    );

    test(
      'precomputes immutable route geometry without a proportional live ETA',
      () {
        final route = JourneyRoute(
          points: const [
            GeoPoint(6.4400, 3.4600),
            GeoPoint(6.4400, 3.4700),
            GeoPoint(6.4400, 3.4800),
          ],
          origin: const GeoPoint(6.4400, 3.4600),
          mode: TravelMode.bus,
          kind: RouteKind.busTransit,
          distanceMeters: 2210,
          durationSeconds: 600,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        expect(route.geometry.isUsable, isTrue);
        expect(route.geometry.lengthMeters, closeTo(2210, 30));
        expect(identical(route.geometry, route.geometry), isTrue);
      },
    );
  });
}

class _ThrowingGateway implements NavigationGateway {
  const _ThrowingGateway(this.code);
  final String code;

  @override
  Future<List<DestinationPlace>> search(String query) =>
      Future.error(NavigationFailure(code));

  @override
  Future<JourneyRoute> plan({
    required GeoPoint origin,
    required DestinationPlace destination,
    required TravelMode mode,
  }) => Future.error(NavigationFailure(code));
}

class _StubHttp implements CloudHttpTransport, GetCloudHttpTransport {
  _StubHttp({
    List<CloudHttpResponse> postResponses = const [],
    List<CloudHttpResponse> getResponses = const [],
  }) : _postQueue = List.of(postResponses),
       _getQueue = List.of(getResponses);

  final List<CloudHttpResponse> _postQueue;
  final List<CloudHttpResponse> _getQueue;
  final postedBodies = <Map<String, Object?>>[];
  Map<String, String>? lastHeaders;

  @override
  Future<CloudHttpResponse> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    lastHeaders = headers;
    postedBodies.add(body);
    return _postQueue.removeAt(0);
  }

  @override
  Future<CloudHttpResponse> getJson({
    required Uri uri,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 8),
  }) async {
    lastHeaders = headers;
    return _getQueue.removeAt(0);
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
  Future<CloudHttpBytesResponse> postJsonBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
    int maxBytes = 4194304,
  }) => throw UnimplementedError();

  @override
  void close() {}
}
