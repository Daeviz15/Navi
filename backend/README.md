# Navi navigation backend

This service connects destination search and route previews to Google Places API
(New) and Routes API. The mobile Maps SDK key only draws the basemap; it cannot
replace this connection. Flutter owns the journey and voice state with Riverpod.
The server owns the Google server credential and validates provider requests.

## Run locally with your Android phone

1. Enable **Places API (New)** and **Routes API** in the billed Google project.
   Create a **separate server API key**, restrict its APIs to those two services,
   and keep it outside Flutter's `env.json`. For local development, an IP
   restriction must match the computer's public egress IP. For deployment, use
   the backend's fixed egress IP; Android package restrictions will not work for
   this server credential.
2. Install Node.js 22 or newer. In PowerShell, from the repository root:

   ```powershell
   if (-not (Test-Path backend/.env)) {
     Copy-Item backend/.env.example backend/.env
   }
   ```

   Set `GOOGLE_MAPS_SERVER_KEY` inside **backend/.env**. Do not paste it into chat
   or add it to the root app configuration. The file is git-ignored.
3. Start the service in a separate terminal:

   ```powershell
   Set-Location backend
   npm.cmd ci
   npm.cmd run dev
   ```

   Check `http://127.0.0.1:8080/healthz` on the computer. A healthy process does
   not prove that the provider key, billing or API enablement is correct.
4. With the phone connected by USB and USB debugging enabled:

   ```powershell
   adb reverse tcp:8080 tcp:8080
   flutter run --dart-define=NAVI_BACKEND_URL=http://127.0.0.1:8080
   ```

   If `adb` is not on PATH, use `platform-tools/adb.exe` from your Android SDK.
   Alternatively add `NAVI_BACKEND_URL` to the app's local `env.json` and fully
   restart the app. Hot reload does not refresh cached configuration. USB reverse
   must be repeated after some device disconnects. No emulator is required.

5. Enter a destination, complete initialization, and **choose the exact place**
   from search results. The blue cloud and animated route appear after this
   confirmation, a fresh precise location, and a successful provider route.
   Bus routes depend on Google's published transit coverage; informal Lagos
   bus routes are not invented. Try walking to validate the integration where a
   verified bus route is unavailable.

Debug Android permits HTTP only to loopback for USB development. Release builds
require HTTPS. The unauthenticated local server refuses production or non-loopback
binding. Do not expose the development server through a tunnel.

## Remote deployment preparation

The Dockerfile builds a Node 24 non-root image. Before deploying:

- Set `NODE_ENV=production`, `HOST=0.0.0.0`, `NAVI_AUTH_MODE=firebase`,
  `FIREBASE_PROJECT_ID`, and inject `GOOGLE_MAPS_SERVER_KEY` from a secret manager.
- Enable Firebase Authentication's anonymous sign-in provider in the same project.
  Configure Application Default Credentials with the runtime service account;
  never put a service-account JSON credential in the mobile app.
- Set the app's `NAVI_BACKEND_URL` to the HTTPS service URL and
  `NAVI_FIREBASE_API_KEY` to the Firebase project's public web API key. That public
  key identifies the project; the server authenticates requests with verified
  Firebase ID tokens. Keep the Maps server key separate from it.
- Anonymous identity is currently held in memory and refreshed during the app
  session. Add persistent identity through the Firebase client SDK before a wider
  rollout to avoid creating an anonymous account on each new app process.
- Restrict the Google server key to the deployment's fixed egress IP and required
  APIs. Set provider quotas, billing alerts, and instance limits before opening
  the service publicly. Firebase authentication alone is not abuse protection.
- Limits currently apply **per process**, by IP and authenticated UID. Keep a
  small single-instance pilot or introduce a shared rate limiter and app
  attestation before horizontal scaling. TLS termination/proxy IP handling also
  needs deployment-specific configuration.

Deployment has not been performed by this implementation. Provider credentials,
Firebase provisioning and device route accuracy still require live validation.

## API and constraints

- `GET /healthz` returns process health without provider calls.
- `POST /v1/places/search` accepts `{ "query": "Computer Village" }` and returns
  up to five Lagos/Nigeria places.
- `POST /v1/routes/plan` accepts
  `{ "origin": { "latitude": 6.52, "longitude": 3.37 }, "placeId": "...", "mode": "walking" }`.
  Supported modes are `walking` and `bus`. The server revalidates the place ID
  with Google and returns real encoded geometry, estimates and expiry.
- Lagos filtering uses provider address components for destinations and a coarse
  pilot rectangle for origins, **not** an authoritative state boundary.
- Requests and provider responses are bounded, provider calls have deadlines,
  and errors omit upstream payloads, keys and trip coordinates. Precise locations
  and raw request bodies are not logged or persisted.
- Routes expire after five minutes. Movement beyond 150 m invalidates a preview
  and offers refresh rather than continuously issuing billable calls. This is
  route preview infrastructure, not turn-by-turn or stop-arrival navigation.
- Google attribution stays visible. Styling and cloud markers do not remove it.

## Validation

```powershell
npm.cmd run check
npm.cmd test
npm.cmd run build
```

Tests inject provider responses and make no billable Google requests.
