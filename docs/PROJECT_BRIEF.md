# Navi Product Brief — v0.1 — 2026-10-18

## Vision
A friendly, expressive personal travel companion that helps people **reach destinations and accomplish the purpose of their journeys**. Start with the creator's unfamiliar Lagos bus journeys; validate personally before broad release.

## Core workflow
1. Open Navi (guest-first, no forced account).
2. Enter or say destination; verify selected place once geocoding is implemented.
3. Optionally state purpose: personal visit or errand. Skipping is always allowed.
4. For applicable errands, show sourced, recently verified preparation guidance, with uncertainty made explicit.
5. Review mode and route (Lagos bus/walking first).
6. Begin journey and receive useful, personalized stop alerts, including while the screen is locked where OS support permits.
7. Ask where you are; later allow hands-free 'Hey Navi' during an active journey.
8. Confirm arrival, optionally receive last-mile guidance and finish.

## Experience requirements
- Modern, sophisticated, minimalist **Design B**-inspired visual language.
- Dark charcoal with indigo/electric-blue accents, plus outdoor-readable light theme.
- Original expressive mascot: idle, listening, thinking, speaking. Don't obscure the map.
- Warm localized language without sacrificing factual precision.
- Respect user control over chatty versus minimal notifications.
- Default companion name = Navi. Users may rename their companion.
- Voice-first aspiration: eventually 'Hey Navi' without tapping during active journeys; full Siri-like always-on cannot be promised across OS states.
- Low-end Android performance, battery and privacy are product constraints.
- Reduce paid LLM usage; GPS/navigation is deterministic, not performed by LLM.

## Non-negotiable reliability
- No invented route/ETA when no live route exists.
- No invented establishment paperwork requirements or unsourced claims.
- Clear errors and uncertainty; safety is improved awareness, not a promise of personal protection.
- Respect Google Maps Platform terms, pricing, key restrictions and attribution once added.

## Initial scope
Android-first Flutter prototype; destination → purpose → preview, then real navigation. No artificial deadline or guarantee that one month yields production-grade background tracking.

## Initial user validation metrics
- Correct alert before selected stop, not after it.
- False alerts and missed alerts in actual journeys.
- Battery impact on representative Android devices.
- Number of interventions/manual map checks needed.
- Whether pre-departure guidance prevented an unnecessary trip (later).
