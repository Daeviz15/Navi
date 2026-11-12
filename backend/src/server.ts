import { createApp } from './app.js';

const production = process.env.NODE_ENV === 'production';
const host = process.env.HOST ?? '127.0.0.1';
const authMode = process.env.NAVI_AUTH_MODE ?? 'firebase';
if (authMode !== 'local' && authMode !== 'firebase') throw new Error('Invalid NAVI_AUTH_MODE');
const app = await createApp({
  production, host, authMode,
  projectId: process.env.FIREBASE_PROJECT_ID ?? '',
  googleKey: process.env.GOOGLE_MAPS_SERVER_KEY ?? '',
  requestsPerMinute: Number(process.env.NAVI_REQUESTS_PER_MINUTE ?? 20),
});
const port = Number(process.env.PORT ?? 8080);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
await app.listen({ host, port });
console.info('Navi navigation API listening', { port, authMode });
for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.once(signal, async () => { await app.close(); process.exit(0); });
}
