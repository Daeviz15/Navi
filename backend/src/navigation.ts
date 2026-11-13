import { z } from 'zod';

export class ApiError extends Error {
  constructor(public code: string, public status = 503) { super(code); }
}

export const coordinateSchema = z.object({
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
}).strict();
export const searchSchema = z.object({ query: z.string().trim().min(2).max(120) }).strict();
export const routeSchema = z.object({
  origin: coordinateSchema,
  placeId: z.string().min(2).max(250).regex(/^[a-zA-Z0-9_-]+$/),
  mode: z.enum(['walking', 'bus']),
}).strict();

export type RouteRequest = z.infer<typeof routeSchema>;
export type PlaceCandidate = {
  id: string; name: string; address: string;
  latitude: number; longitude: number;
};

const googlePlaceSchema = z.object({
  id: z.string(), displayName: z.object({ text: z.string() }),
  formattedAddress: z.string(), location: coordinateSchema,
  addressComponents: z.array(z.object({
    // Google's protobuf JSON can omit an empty repeated field. An untyped
    // component provides no service-area evidence, but is still valid data.
    longText: z.string().optional(), shortText: z.string().optional(), types: z.array(z.string()).default([]),
  })).default([]),
});

export interface NavigationService {
  search(query: string): Promise<PlaceCandidate[]>;
  route(input: RouteRequest): Promise<{
    encodedPolyline: string; distanceMeters: number; durationSeconds: number;
    mode: RouteRequest['mode']; expiresAt: string;
    source: 'google_routes'; kind: 'walking' | 'bus_transit';
  }>;
}

export class GoogleNavigationService implements NavigationService {
  constructor(private key: string, private fetcher: typeof fetch = fetch) {}

  private async request(url: string, mask: string, body?: object): Promise<unknown> {
    if (!this.key) throw new ApiError('provider_not_configured');
    try {
      const response = await this.fetcher(url, {
        method: body ? 'POST' : 'GET',
        headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': this.key, 'X-Goog-FieldMask': mask },
        ...(body ? { body: JSON.stringify(body) } : {}),
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new ApiError(response.status === 429 ? 'provider_rate_limited' : 'provider_unavailable');
      }
      // Bound provider response size; do not log provider bodies or request coordinates.
      const reader = response.body?.getReader();
      if (!reader) throw new ApiError('invalid_provider_response');
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      try {
        while (true) {
          const item = await reader.read();
          if (item.done) break;
          bytes += item.value.byteLength;
          if (bytes > 524288) throw new ApiError('invalid_provider_response');
          chunks.push(item.value);
        }
      } finally { await reader.cancel().catch(() => {}); }
      return JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
    } catch (error) {
      if (error instanceof ApiError) throw error;
      throw new ApiError('provider_unavailable');
    }
  }

  private inLagos(place: z.infer<typeof googlePlaceSchema>): boolean {
    const components = place.addressComponents;
    return components.some((p) => p.types.includes('country') && p.shortText === 'NG') &&
      components.some((p) => p.types.includes('administrative_area_level_1') &&
        /^lagos(?: state)?$/i.test(p.longText ?? p.shortText ?? ''));
  }

  async search(query: string): Promise<PlaceCandidate[]> {
    const raw = await this.request('https://places.googleapis.com/v1/places:searchText',
      'places.id,places.displayName,places.formattedAddress,places.location,places.addressComponents', {
        textQuery: `${query} Lagos Nigeria`, regionCode: 'NG', languageCode: 'en', pageSize: 5,
        locationBias: { circle: { center: { latitude: 6.5244, longitude: 3.3792 }, radius: 50000 } },
      });
    const data = z.object({ places: z.array(googlePlaceSchema).default([]) }).safeParse(raw);
    if (!data.success) throw new ApiError('invalid_provider_response');
    return data.data.places.filter((p) => this.inLagos(p)).map((p) => ({
      id: p.id, name: p.displayName.text, address: p.formattedAddress,
      latitude: p.location.latitude, longitude: p.location.longitude,
    }));
  }

  async route(input: RouteRequest) {
    // Resolve the selected provider ID again; never accept destination coordinates
    // supplied by a client as proof of a real, eligible place.
    const place = googlePlaceSchema.safeParse(await this.request(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(input.placeId)}`,
      'id,displayName,formattedAddress,location,addressComponents',
    ));
    if (!place.success) throw new ApiError('invalid_provider_response');
    if (!this.inLagos(place.data)) throw new ApiError('outside_service_area', 422);
    // Coarse origin window is an explicit pilot limit, not an exact state boundary.
    if (input.origin.latitude < 6.2 || input.origin.latitude > 6.9 ||
        input.origin.longitude < 2.6 || input.origin.longitude > 4.6) {
      throw new ApiError('outside_service_area', 422);
    }
    const raw = await this.request('https://routes.googleapis.com/directions/v2:computeRoutes',
      'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.legs.steps.travelMode,routes.legs.steps.transitDetails.transitLine.vehicle.type', {
        origin: { location: { latLng: input.origin } },
        destination: { placeId: input.placeId },
        travelMode: input.mode === 'bus' ? 'TRANSIT' : 'WALK',
        languageCode: 'en', units: 'METRIC', computeAlternativeRoutes: false,
        ...(input.mode === 'bus' ? { transitPreferences: { allowedTravelModes: ['BUS'] } } : {}),
      });
    const result = z.object({ routes: z.array(z.object({
      distanceMeters: z.number().nonnegative(), duration: z.string().regex(/^\d+(?:\.\d+)?s$/),
      polyline: z.object({ encodedPolyline: z.string().min(2).max(150000) }),
      legs: z.array(z.object({ steps: z.array(z.object({
        travelMode: z.string(),
        transitDetails: z.object({ transitLine: z.object({ vehicle: z.object({ type: z.string() }) }) }).optional(),
      })).default([]) })).default([]),
    })).default([]) }).safeParse(raw);
    if (!result.success) throw new ApiError('invalid_provider_response');
    const route = result.data.routes[0];
    if (!route) throw new ApiError('no_route', 404);
    if (input.mode === 'bus') {
      const steps = route.legs.flatMap((leg) => leg.steps);
      const vehicles = steps.filter((step) => step.travelMode === 'TRANSIT')
        .map((step) => step.transitDetails?.transitLine.vehicle.type);
      if (vehicles.length === 0 || vehicles.some((vehicle) => vehicle !== 'BUS')) {
        throw new ApiError('bus_route_unavailable', 404);
      }
    }
    return {
      encodedPolyline: route.polyline.encodedPolyline,
      distanceMeters: route.distanceMeters, durationSeconds: Number.parseFloat(route.duration),
      mode: input.mode, expiresAt: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      source: 'google_routes' as const,
      kind: input.mode === 'bus' ? 'bus_transit' as const : 'walking' as const,
    };
  }
}
