import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { ApiError, GoogleNavigationService, searchSchema, routeSchema, type NavigationService } from './navigation.js';

export type ServerConfig = {
  host: string; production: boolean; authMode: 'local' | 'firebase';
  projectId: string; googleKey: string; requestsPerMinute: number;
};

export function validateConfig(config: ServerConfig) {
  if (config.authMode === 'local' &&
      (config.production || !['127.0.0.1', '::1', 'localhost'].includes(config.host))) {
    throw new Error('Local auth is allowed only on loopback in development');
  }
  if (config.authMode === 'firebase' && !config.projectId) {
    throw new Error('FIREBASE_PROJECT_ID is required');
  }
  if (!Number.isInteger(config.requestsPerMinute) || config.requestsPerMinute < 1 || config.requestsPerMinute > 1000) {
    throw new Error('Invalid request limit');
  }
}

export async function createApp(config: ServerConfig, dependencies: {
  navigation?: NavigationService;
  verifyToken?: (token: string) => Promise<string>;
} = {}) {
  validateConfig(config);
  const app = Fastify({
    bodyLimit: 4096, requestTimeout: 12000, connectionTimeout: 15000,
    disableRequestLogging: true,
    // Do not serialize request headers, URLs, bodies or precise trip data.
    logger: false,
  });
  const service = dependencies.navigation ?? new GoogleNavigationService(config.googleKey);
  let verifyToken = dependencies.verifyToken;
  if (config.authMode === 'firebase' && !verifyToken) {
    const firebase = initializeApp({ projectId: config.projectId }, `navi-${crypto.randomUUID()}`);
    verifyToken = async (token) => (await getAuth(firebase).verifyIdToken(token)).uid;
    const { deleteApp } = await import('firebase-admin/app');
    app.addHook('onClose', async () => deleteApp(firebase));
  }
  // Apply IP limits before authentication as well, to bound invalid-token work.
  await app.register(rateLimit, { max: config.requestsPerMinute, timeWindow: '1 minute' });
  const userRequests = new Map<string, { count: number; until: number }>();
  app.addHook('preHandler', async (request) => {
    if (request.routeOptions.url === '/healthz' || config.authMode === 'local') return;
    const authorization = request.headers.authorization;
    if (!authorization?.startsWith('Bearer ') || authorization.length > 8192) throw new ApiError('unauthorized', 401);
    let uid: string;
    try { uid = await verifyToken!(authorization.slice(7)); }
    catch { throw new ApiError('unauthorized', 401); }
    const now = Date.now();
    if (userRequests.size > 10000) {
      for (const [key, value] of userRequests) if (value.until <= now) userRequests.delete(key);
      if (userRequests.size > 10000) throw new ApiError('capacity_exceeded', 503);
    }
    let counter = userRequests.get(uid);
    if (!counter || counter.until <= now) {
      counter = { count: 0, until: now + 60000 }; userRequests.set(uid, counter);
    }
    if (++counter.count > config.requestsPerMinute) throw new ApiError('rate_limited', 429);
  });
  app.addHook('onRequest', async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    reply.header('X-Content-Type-Options', 'nosniff');
  });
  app.get('/healthz', async () => ({ status: 'ok' }));
  app.post('/v1/places/search', async (request) => {
    const parsed = searchSchema.safeParse(request.body);
    if (!parsed.success) throw new ApiError('invalid_request', 400);
    return { places: await service.search(parsed.data.query) };
  });
  app.post('/v1/routes/plan', async (request) => {
    const parsed = routeSchema.safeParse(request.body);
    if (!parsed.success) throw new ApiError('invalid_request', 400);
    return await service.route(parsed.data);
  });
  app.setErrorHandler((error, _request, reply) => {
    const rawStatus = typeof error === 'object' && error !== null && 'statusCode' in error
      ? error.statusCode : undefined;
    const status = error instanceof ApiError ? error.status :
      typeof rawStatus === 'number' && rawStatus >= 400 && rawStatus < 500 ? rawStatus : 503;
    reply.code(status).send({ error: {
      code: error instanceof ApiError ? error.code : status === 429 ? 'rate_limited' : status === 413 ? 'body_too_large' : 'request_failed',
    } });
  });
  return app;
}
