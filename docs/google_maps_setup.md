# Google Maps: Android setup and first location milestone

Date: 2026-11-12. Android map/foreground location implementation; device validation pending.

## Restrict the key in Google Cloud

The key in local `env.json` is used by Maps SDK for Android, not by a server-side
Places or Routes implementation. On the onboarding restriction screen choose
**Android apps**. In the credential's full settings configure both:

1. Application restriction: Android apps, using the installed app's application ID
   and signing certificate SHA-1 fingerprint.
2. API restriction: Restrict key -> Maps SDK for Android. Enable that SDK in the
   same billing-enabled Google Cloud project.

Current development application ID: `com.example.navi`.

Current local debug signing SHA-1:

```text
29:6B:EB:86:4F:40:A8:EF:C8:B9:05:92:40:97:61:DB:35:CF:AF:12
```

The fingerprint is public certificate metadata, not an API credential. It is
specific to this machine's existing debug keystore. The current local release
build also uses debug signing. Production must use an appropriate signing
configuration and a separate restricted production key; Play-distributed builds
need the Play app-signing certificate fingerprint. Registering only an upload
certificate does not authorize an app signed by Play's different certificate.

Do not choose Websites or IP addresses for this Android SDK key. The later backend
uses separate credentials appropriate to its own APIs and deployment. See
[backend setup](../backend/README.md) for Places API (New), Routes API, local
phone testing and authenticated remote configuration.

Official guidance:
- [Maps security](https://developers.google.com/maps/api-security-best-practices)
- [Flutter configuration](https://developers.google.com/maps/flutter-package/config)

## Local configuration and build

The user's existing `GOOGLE_MAPS_API` field is supported without renaming it.
`GOOGLE_MAPS_API_KEY` is also supported. The Android Gradle build reads the local,
git-ignored root `env.json` and supplies the native manifest metadata
`com.google.android.geo.API_KEY`. CI may instead set `GOOGLE_MAPS_API_KEY` or
`GOOGLE_MAPS_API` as an environment variable; environment configuration wins.

The Android method channel exposes only whether the built-in key is present.
Presence does not prove that Google has accepted the key, SDK enablement, billing
or restrictions. Those need a real map-load test on the installed application.

After native configuration or dependency changes, stop the running app and do a
full `flutter run` on the phone. Hot reload cannot replace native manifest values.
Changing Google Cloud restrictions alone does not change the APK, although those
server-side changes may take time to propagate.

Do not paste keys into source, documentation, issue reports or logs. The Maps SDK
key is present in the installed app by design; app/API restrictions protect its
use. Existing voice configuration is outside this milestone's scope.

## Where to find the map

Enter/say a destination on Home, then tap **Let’s go together**. A short bus
animation circles the checklist already collected on Home (or a travel-light
card for casual trips). After the animation, Navi checks location permission,
prompts only if it needs permission, and opens the journey map automatically.
Declining permission still opens the map with an optional recovery action.
There is no second purpose-selection screen.

- The initial Lagos centre is a map viewport, not the user's location.
- Home does not request location. Starting the journey entry flow is the explicit
  opt-in; the permission check happens after the introduction. Existing grants
  are reused. Backing out cancels the pending handoff.
- A usable fix has an estimated position marker and an uncertainty circle.
- Approximate permission or poor accuracy shows an uncertainty area without a
  precise position marker. Settings lets the user review precise access.
- A reading older than ten seconds is labelled stale and loses its current-position
  marker. Fifty metres is the initial display-quality boundary, not an arrival rule.
- Location stops on backgrounding and preview disposal; resume rechecks permission
  without prompting again and requires a new sample. GPS-disabled and denied
  permission states have separate recovery paths.
- Camera movement does not follow every fix. First usable acquisition can centre
  once if the user has not touched the map; Re-centre is an explicit action.
- The boxed map has Navi dark/light styling, quieter business labels and custom
  yellow/blue cloud markers. Native attribution stays visible inside the map;
  the companion, checklist and destination controls sit outside its viewport.
- Navi remains available above the map. Voice preparation updates the shared
  journey even after Home has gone off screen. The microphone and companion
  use surface ownership so navigation between screens does not disable them.
- Destination search uses the repository's backend. Choose the exact provider
  result before a blue cloud is shown. A returned road/transit route gets a
  static path plus a small moving highlight sampled along its real geometry.
- Search never confirms its first result automatically. Tap the numbered
  name/address, or tap Navi, say an option number, wait for its complete address
  readback, then say "yes". "No" rejects that suggestion. `Refine destination`
  starts a more specific query and clears preparation for the old destination.
  These controls share Riverpod confirmation state and reject outdated choices.
- Active movement and estimate expiry retain the route geometry. Refreshes keep
  the applicable path visible, share one pending request per intent, and enforce
  cooldown/backoff. Stale planning estimates are labelled; current distance is
  shown only with an eligible approximate route match. The moving highlight
  pauses for uncertain/unmatched positions. Overview instructions are not current
  turn guidance, and provider planning time is not a live remaining ETA.
- No configured backend produces an explicit connection-required state. A map
  display key alone cannot resolve a destination or supply a route.
- Map options contains notices, the existing checklist and debug-only location
  diagnostics. The checklist and checked items survive the transition.
- A journey-flow scope owns acquisition across initialization -> map. It releases
  tracking when leaving that flow; initialization and map do not start two streams.
- Reduced motion skips the bus lap. Backgrounding pauses the introduction and
  never initiates a permission prompt while the app is hidden.

This version provides destination confirmation and route previews once the backend
is configured. It does not issue stop alerts or keep navigation running while the
screen is locked. Bus routes require verified provider coverage and are not
replaced with invented local routes. Automated tests mock Google responses;
real routes remain unverified until the server key and runtime are connected.

## Device validation record

Automated tests use injected location gateways/clocks and map configuration.
They do not contact Google, request permission on a phone, or validate real GPS.

Local integration check on 2026-11-12:

- Confirmed the configured server key differs from the Android Maps key without
  displaying either credential. Live Places search returned five Lagos results.
- Public Ikeja test origins produced provider geometry for walking and bus.
- Started the loopback backend and configured the local app's `NAVI_BACKEND_URL`
  as `http://127.0.0.1:8080`, with USB reverse forwarding on the TECNO KI7.
- Rebuilt, installed and launched the debug app on that physical phone. Entered
  Computer Village, Ikeja and confirmed a provider result in the app.
- The boxed map displayed the yellow current-position cloud, blue destination
  cloud and a real bus route. Two captured frames confirmed movement of the blue
  route highlight. This was a stationary integration check, not a field journey.
- Production hosting, key restriction auditing, voice timing and stop/arrival
  accuracy were not established by this check. The computer backend and USB
  connection are required for this local setup.

Before closing the map/location milestone, record results for:

- [ ] Native map loads with the restricted key on TECNO KI7.
- [ ] Dark/light maps remain readable and attribution is unobstructed.
- [ ] Permission is requested after the bus introduction; existing grants are reused.
- [ ] Precise permission yields fresh samples outdoors; inspect reported uncertainty.
- [ ] Approximate-only permission remains clearly approximate.
- [ ] Denial, permanent denial and settings return recover without repeated prompts.
- [ ] GPS off/on produces an honest state and Retry recovers.
- [ ] A stale sample is never described as the current position.
- [ ] Pan/zoom does not fight repeated automatic camera updates; Re-centre works.
- [ ] Background/foreground rechecks access; leaving preview releases tracking.
- [ ] Representative compact layouts and larger text remain usable.
- [ ] Back from initialization or map returns Home without repeating the purpose question.
- [ ] Checklist state survives initialization, map and the map's essentials sheet.
- [ ] Google attribution stays visible inside the boxed map in both orientations.
- [x] Destination search returns provider places; choosing one shows the blue cloud.
- [x] Provider route geometry and a flowing highlight reach the confirmed place.
- [ ] Unsupported bus routes show an honest message; walking remains selectable.
- [ ] Changing destination/mode cannot display a late result for the old journey.

No field positioning accuracy or stop-guidance reliability has been established yet.
Pilot corridor data and arrival-confidence policies remain future work.
