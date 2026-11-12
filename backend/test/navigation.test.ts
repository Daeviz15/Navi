import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp, validateConfig, type ServerConfig } from '../src/app.js';
import { GoogleNavigationService, type NavigationService } from '../src/navigation.js';

const config: ServerConfig = { host: '127.0.0.1', production: false, authMode: 'local',
  projectId: '', googleKey: '', requestsPerMinute: 20 };
const place = {
  id: 'lagos_place', displayName: { text: 'Computer Village' },
  formattedAddress: 'Ikeja, Lagos, Nigeria', location: { latitude: 6.6, longitude: 3.34 },
  addressComponents: [
    { longText: 'Lagos', shortText: 'LA', types: ['administrative_area_level_1'] },
    { longText: 'Nigeria', shortText: 'NG', types: ['country'] },
  ],
};

function fetchQueue(bodies: unknown[]) {
  const requests: { url: string; init?: RequestInit }[] = [];
  const fetcher: typeof fetch = async (input, init) => {
    requests.push({ url: String(input), ...(init ? { init } : {}) });
    return new Response(JSON.stringify(bodies.shift()), { status: 200 });
  };
  return { fetcher, requests };
}

test('local mode is refused on public interfaces and in production', () => {
  assert.throws(() => validateConfig({ ...config, host: '0.0.0.0' }));
  assert.throws(() => validateConfig({ ...config, production: true }));
  assert.throws(() => validateConfig({ ...config, authMode: 'firebase' }));
});

test('health check does not need a provider key; provider requests fail closed', async () => {
  const app = await createApp(config);
  try {
    assert.equal((await app.inject('/healthz')).statusCode, 200);
    const result = await app.inject({ method: 'POST', url: '/v1/places/search', payload: { query: 'Lekki' } });
    assert.equal(result.statusCode, 503);
    assert.deepEqual(result.json(), { error: { code: 'provider_not_configured' } });
    assert.equal(result.headers['cache-control'], 'no-store');
  } finally { await app.close(); }
});

test('invalid, oversized and unexpected request fields never reach the provider', async () => {
  let calls = 0;
  const service: NavigationService = {
    search: async () => { calls++; return []; },
    route: async () => { calls++; throw new Error('should not run'); },
  };
  const app = await createApp(config, { navigation: service });
  try {
    for (const payload of [{ query: '' }, { query: 'a'.repeat(121) }, { query: 'Ikeja', apiKey: 'bad' }]) {
      assert.equal((await app.inject({ method: 'POST', url: '/v1/places/search', payload })).statusCode, 400);
    }
    assert.equal((await app.inject({ method: 'POST', url: '/v1/places/search', payload: { query: 'a'.repeat(5000) } })).statusCode, 413);
    assert.equal((await app.inject({ method: 'POST', url: '/v1/routes/plan', payload: {
      origin: { latitude: 200, longitude: 3 }, placeId: 'some_place', mode: 'walking',
    } })).statusCode, 400);
    assert.equal(calls, 0);
  } finally { await app.close(); }
});

test('deployed mode rejects missing or invalid tokens and accepts verified guest IDs', async () => {
  const app = await createApp({ ...config, authMode: 'firebase', projectId: 'test-project' }, {
    navigation: { search: async () => [], route: async () => { throw new Error(); } },
    verifyToken: async (token) => { if (token !== 'verified') throw new Error('bad'); return 'guest1'; },
  });
  try {
    for (const token of ['', 'Bearer invalid']) {
      const result = await app.inject({ method: 'POST', url: '/v1/places/search',
        headers: { authorization: token }, payload: { query: 'Lekki' } });
      assert.equal(result.statusCode, 401);
    }
    assert.equal((await app.inject({ method: 'POST', url: '/v1/places/search',
      headers: { authorization: 'Bearer verified' }, payload: { query: 'Lekki' } })).statusCode, 200);
  } finally { await app.close(); }
});

test('untrusted internal/provider errors do not escape the API response', async () => {
  const app = await createApp(config, {
    navigation: { search: async () => { throw new Error('secret-private-provider-data'); }, route: async () => { throw new Error(); } },
  });
  try {
    const result = await app.inject({ method: 'POST', url: '/v1/places/search', payload: { query: 'Ikeja' } });
    assert.equal(result.statusCode, 503);
    assert.equal(result.body.includes('secret-private'), false);
  } finally { await app.close(); }
});

test('provider search returns only places with Lagos/Nigeria address metadata', async () => {
  const queue = fetchQueue([{ places: [place, { ...place, id: 'other', addressComponents: [] }] }]);
  const service = new GoogleNavigationService('server-key-fixture', queue.fetcher);
  const places = await service.search('Computer Village');
  assert.equal(places.length, 1);
  assert.equal(places[0]?.id, 'lagos_place');
  assert.equal(queue.requests[0]?.url, 'https://places.googleapis.com/v1/places:searchText');
});

function routeResponse(vehicle?: string) {
  return { routes: [{ distanceMeters: 2000, duration: '600s',
    polyline: { encodedPolyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@' },
    legs: [{ steps: vehicle ? [{ travelMode: 'TRANSIT', transitDetails: { transitLine: { vehicle: { type: vehicle } } } }]
      : [{ travelMode: 'WALK' }] }],
  }] };
}

test('walking requests use WALK and return provider geometry without invented data', async () => {
  const queue = fetchQueue([place, routeResponse()]);
  const service = new GoogleNavigationService('fixture', queue.fetcher);
  const route = await service.route({ origin: { latitude: 6.5, longitude: 3.3 }, placeId: 'lagos_place', mode: 'walking' });
  const request = JSON.parse(String(queue.requests[1]?.init?.body));
  assert.equal(request.travelMode, 'WALK');
  assert.equal(route.distanceMeters, 2000);
  assert.equal(route.durationSeconds, 600);
  assert.equal(route.encodedPolyline, '_p~iF~ps|U_ulLnnqC_mqNvxq`@');
});

test('bus mode rejects rail-only and walking-only provider results', async () => {
  for (const vehicle of [undefined, 'SUBWAY']) {
    const queue = fetchQueue([place, routeResponse(vehicle)]);
    const service = new GoogleNavigationService('fixture', queue.fetcher);
    await assert.rejects(service.route({ origin: { latitude: 6.5, longitude: 3.3 }, placeId: 'lagos_place', mode: 'bus' }),
      { code: 'bus_route_unavailable' });
  }
  const queue = fetchQueue([place, routeResponse('BUS')]);
  const service = new GoogleNavigationService('fixture', queue.fetcher);
  assert.equal((await service.route({ origin: { latitude: 6.5, longitude: 3.3 }, placeId: 'lagos_place', mode: 'bus' })).mode, 'bus');
});

test('invalid JSON, timeout and rate limits become bounded provider failures', async () => {
  const invalid: typeof fetch = async () => new Response('invalid json');
  await assert.rejects(new GoogleNavigationService('fixture', invalid).search('Lekki'), { code: 'provider_unavailable' });
  const timeout: typeof fetch = async () => { throw new DOMException('timeout', 'TimeoutError'); };
  await assert.rejects(new GoogleNavigationService('fixture', timeout).search('Lekki'), { code: 'provider_unavailable' });
  const limited: typeof fetch = async () => new Response('{}', { status: 429 });
  await assert.rejects(new GoogleNavigationService('fixture', limited).search('Lekki'), { code: 'provider_rate_limited' });
});
