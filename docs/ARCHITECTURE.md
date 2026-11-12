# Navi Architecture — v0.1

Guiding principle: **small modular MVVM-ish feature slices**, not speculative enterprise layers.

```text
main.dart → ProviderScope → NaviApp (theme + router)
                                 ├── home presentation
                                 │     └── JourneyController (Riverpod Notifier)
                                 ├── preparation presentation
                                 │     └── JourneyController
                                 └── route preview presentation
                                       └── JourneyController

Future integrations behind interfaces:
  NavigationGateway → repository → Google maps/route/location services
  VoiceGateway      → voice orchestration → TTS/STT/wake-word platform adapters
  RequirementsRepository → official sources/cache/verification records
```

## Rules
1. Views render and handle UX; controllers/view models manage state.
2. Repositories own persisted data and APIs; platform-specific plugins live behind service adapters.
3. No model decides navigation safety from LLM prose. Arrival alerts are derived from location/route progress with fallback uncertainty.
4. Keep the microphone lifecycle outside widget trees; foreground-service and privacy constraints require separate review.
5. Distinguish raw destination text from selected geocoded place and confirmed route. Current model is intentionally draft-only.
6. Reuse existing features/providers before creating similar ones; append decision log for each architecture change.
7. Test controller state in isolation, then navigation UI, and finally integration/device conditions.

## Initial repository layout

```
lib/
  app/                           app composition, routing
  core/theme/                    shared colours, ThemeMode state
  core/widgets/                  reusable companion/page components
  features/home/presentation/    home view
  features/journey/domain/       immutable draft and travel mode
  features/journey/presentation/ Riverpod controller + preview view
  features/preparation/domain/   requirements boundary
  features/preparation/presentation/ purpose view
  features/navigation/domain/    navigation boundary
  features/voice/domain/         voice boundary
```

## Dependency versions (checked 2026-10-18)
- flutter_riverpod: ^3.4.3
- go_router: ^18.1.0
- flutter_lints: ^6.0.0
- Dart SDK >= 3.12.0 required by selected router/state versions.

Verified background guidance: https://docs.flutter.dev/app-architecture/guide

## Lagos map/navigation implementation direction — 2026-11-12

The phased roadmap and acceptance gates are in
[maps_navigation_plan.md](maps_navigation_plan.md). Android map/foreground location
now has a development implementation; device validation, backend and active
navigation remain pending. Setup is in [google_maps_setup.md](google_maps_setup.md).

- Continue the Flutter app at the repository root; add an independently deployed
  backend under `backend/` as server-backed place lookup begins.
- Recommended initial service: modular TypeScript HTTP API on Cloud Run. Runtime,
  framework, authentication and deployment configuration are implementation tasks.
- Keep location quality, journey progress and stop decisions on the device. The
  server owns protected place/route calls, usage controls and owned corridor data.
- Evolve the draft navigation interface into typed place, route, fix, session and
  event contracts. Preserve Riverpod and the existing journey/preparation flow.
- Google Maps is the selected map foundation; Lagos transit coverage and reliable
  corridor-specific stop guidance require separate validation.
- Location/background execution and spoken guidance need their own device-tested
  lifecycle. A map widget or server deployment alone does not provide navigation.

Implemented first slice:
- `LocationGateway` isolates Geolocator and its Android fused-location adapter.
- `LocationController` is an auto-disposed Riverpod notifier owning foreground
  subscriptions, permission/recovery state, generation guards and freshness timers.
- `LocationQualityPolicy` uses reported uncertainty and monotonic sample age for
  display quality. Its thresholds are not arrival/stop-alert thresholds.
- `JourneyMapPreview` renders the native map and quality-aware position in the
  existing journey overview. It never geocodes a draft or enables navigation.
- Android reads the ignored local map key at build time; the configuration channel
  exposes presence only. Native map rendering and real location are device checks.
