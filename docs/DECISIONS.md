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
