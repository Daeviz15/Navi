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
