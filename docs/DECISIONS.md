# Navi Decisions Log

All accepted product decisions. Append dated changes; do not overwrite history.

## 2026-10-18 — Accepted
- Focus on Navi rather than continuing idea exploration.
- **Navi** is the working app name and official companion name; app store/trademark/domain availability has **not** been verified.
- Users may customize companion name; user-name-aware dialogue later.
- Flutter, Android-first, lightweight and modular. iOS later.
- Riverpod for reactive state; GoRouter for screen navigation.
- UI Design B is the primary inspiration: elegant dark minimalist, with warmth from a custom soft expressive mascot (Design A influence); offer light mode.
- Conversation-first home with destination input; map appears at route stage.
- Purpose question is optional; only purpose-specific errands need verified checklists.
- Public bus and walking are initial travel modes.
- Hands-free 'Hey Navi' is a **product requirement**, but activated-journey scoped implementation will be investigated after deterministic stop alerts; no blanket Siri-like promise.
- Keep AI token cost low using templates/TTS where sufficient.
- Build personally useful journeys, then validate with others; no commercial demand assumed yet.
- Keep `PROJECT_BRIEF.md` and `DECISIONS.md` current to mitigate chat-context drift and duplication.

## Pending, not assumed
- Final brand trademark/domain clearance
- Exact companion illustration and Rive/Lottie assets
- Choice of maps/routing APIs and budget after pricing and transit coverage validation
- Precise wake-word engine, licenses and Android service approach
- Confirmation of requirements data providers and verification workflow
- Persistent user preferences/account approach

## 2026-10-19 — Navi character direction and feasibility spike
- The mature, semi-realistic Afro-futuristic female digital guide is the approved direction; original cartoon mascot is superseded.
- Keep her sleek braids, calm adult expression, navy smart-casual outfit, discreet electric-blue navigational accents and standing pose.
- The production character must react to touch/drag, listening, speaking and journey events; no fully realistic live rendering assumed.
- Preserve a light-on-resources Android-first experience; prioritize device performance on TECNO KI7.
- Before commissioning a detailed rigged model, test a separate interactive low-polygon GLB inside Navi (`/character-lab`) using Flutter + temporary 3D-viewer integration.
- The small geometric character in `navi_interaction_test.glb` is ONLY an interaction stand-in, NOT approved visual identity.
- Do not replace the existing approved cosmic-orb home until performance is validated and the actual production character is ready.
- A WebView-backed 3D viewer is a technical experiment, not an endorsed final rendering architecture. Review local networking permission before release.

## Remaining 3D decisions
- Whether the viewer stays responsive on low-end Android in profile mode.
- Whether production requires a different 3D renderer.
- Final Blender GLB asset, animation rig, materials, surface hit-testing and actual touch-location-dependent gaze.
- Whether Navi will load character lazily, suspend rendering during navigation or offer low-motion mode.

## 2026-11-12 — Lagos maps/navigation planning

User direction:
- Proceed with a sequential, production-oriented map/navigation plan using Google
  Maps as the initial foundation, with Lagos as the initial geographic scope.
- Prioritize correct location/stop guidance and explicit uncertainty; do not
  promise near-100% accuracy without field evidence.
- Preserve current speech work during map integration. Previously reviewed voice
  hardening remains a dependency before external rollout.

Recommended implementation direction (planned, not implemented):
- Keep this repository and root Flutter app; introduce an independently deployable
  `backend/` for protected place/route calls and service-side controls.
- Start with one modular TypeScript service on Cloud Run; finalize tooling and
  deploy configuration when implementing the backend phase.
- Compute location quality, route progress and stop alerts on the device.
- Deliver map/location, confirmed places, route preview, foreground guidance,
  locked-screen lifecycle and voice coordination as separate validated milestones.
- Keep Lagos bus/walking objectives; use walking to validate routing mechanics,
  and enable bus guidance only for supported, field-validated corridors.

See [maps_navigation_plan.md](maps_navigation_plan.md) for dependencies, tests,
acceptance gates, pending inputs and release controls. Cloud resources, credentials,
runtime code and backend deployment have not been changed by this planning entry.

## 2026-11-12 — First Android map/location implementation

- User authorized proceeding and supplied a local Google Maps key. Support the
  existing `GOOGLE_MAPS_API` field and the canonical `GOOGLE_MAPS_API_KEY` alias;
  inject into native Android metadata at build time without checking in its value.
- Keep the current application ID during development; configure Android app/SHA-1
  and Maps SDK API restrictions. Production identity/signing remain release work.
- Add the native map to Journey overview and an explicit foreground location opt-in.
  Use one Riverpod-owned location stream with uncertainty, freshness and lifecycle
  guards. Do not enable navigation or stop alerts from this map-only milestone.
- Google Maps Flutter 2.18.1 is compatible with the current Dart 3.12 toolchain;
  the newer 2.19.0 requires a newer SDK. Geolocator 14.1.2 supplies location access.
- Unit and widget checks cannot establish real map authorization or GPS quality;
  phone checks in [google_maps_setup.md](google_maps_setup.md) remain required.
