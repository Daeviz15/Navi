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
will use separate credentials appropriate to its own APIs and deployment.

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

Enter/say a destination, continue through the purpose screen, and open Journey
overview. The Lagos map appears below the travel mode options. Tap **Use my
location** to request foreground permission and start a high-accuracy stream.

- The initial Lagos centre is a map viewport, not the user's location.
- No location permission is requested merely by opening the app or preview.
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
- Debug builds expose an optional diagnostics panel for uncertainty and reading age.
- Map notices are accessible; the native Google logo/attribution remains visible.

This version does not resolve the destination to coordinates, draw a real route,
issue stop alerts, or keep navigation running while the screen is locked. Bus and
walking selections remain journey-draft choices until route planning is implemented.

## Device validation record

Automated tests use injected location gateways/clocks and map configuration.
They do not contact Google, request permission on a phone, or validate real GPS.
Before closing the map/location milestone, record results for:

- [ ] Native map loads with the restricted key on TECNO KI7.
- [ ] Dark/light maps remain readable and attribution is unobstructed.
- [ ] Permission is requested only after Use my location.
- [ ] Precise permission yields fresh samples outdoors; inspect reported uncertainty.
- [ ] Approximate-only permission remains clearly approximate.
- [ ] Denial, permanent denial and settings return recover without repeated prompts.
- [ ] GPS off/on produces an honest state and Retry recovers.
- [ ] A stale sample is never described as the current position.
- [ ] Pan/zoom does not fight repeated automatic camera updates; Re-centre works.
- [ ] Background/foreground rechecks access; leaving preview releases tracking.
- [ ] Representative compact layouts and larger text remain usable.

No field positioning accuracy or stop-guidance reliability has been established yet.
Pilot corridor data, service-area policy and route API contracts remain Phase 0 work.
