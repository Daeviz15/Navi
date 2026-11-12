# Navi: Lagos maps and navigation implementation plan

Date: 2026-11-12
Status: implementation roadmap. Android map/foreground location foundation is
implemented for development; physical-device validation and route integration remain pending.

## 1. Product outcome and scope

Help a traveller select the right destination, prepare where appropriate, understand
the journey, and receive timely guidance about approaching the correct stop.
Conversation remains the home experience. A map becomes central during route
review and an active journey; the companion stays compact and never obscures
instructions or attribution.

Initial scope: Android, Lagos, bus and walking. Lagos is the geographic boundary;
dependable bus-stop guidance will roll out by validated corridor within it.
Walking is the first routing implementation used to validate the full pipeline,
not a change to the bus-first product objective. Purpose and checklists remain
optional. Accounts must not be a prerequisite for using the app.

Map display, route planning, and reliable active navigation are separate releases.
No position or alert accuracy percentage is promised before device validation.
The team must measure false alerts, missed alerts, and suppressed guidance together;
remaining silent must not make an unreliable system appear successful.

## 2. Repository and deployment decision

Continue in this repository. Keep the existing Flutter app at its current root.
Add a separately buildable and deployable `backend/` when the first server-backed
place lookup is implemented. A separate Git repository is unnecessary at this stage.

Recommended backend: one modular TypeScript HTTP service, initially deployed on
Google Cloud Run, with managed secrets and independent development/staging/production
configuration. This is a proposed implementation choice, not existing infrastructure.
Select framework/runtime versions when scaffolding, against then-current support.

Separate repositories become useful if ownership, access controls, release teams,
or operational requirements diverge. Independent deployability is needed now;
independent Git history is not. Scale the service using observed load and latency.

Proposed additions, created as their phases begin:

```text
lib/features/places/{domain,data,application,presentation}/
lib/features/location/{domain,data,application}/
lib/features/navigation/{domain,data,application,presentation}/
backend/src/{places,routes,access,observability}/
backend/test/
contracts/openapi.yaml
docs/maps_navigation_plan.md
```

Reuse existing journey/home/preparation features and Riverpod. Keep provider-specific
SDK types in adapters. Do not move the Flutter project or generate empty layers.

## 3. Responsibility boundaries

| Responsibility | Owner |
| --- | --- |
| Google map rendering, markers, camera, attribution | Flutter map adapter |
| Permission, fresh location stream, fix quality | Android location adapter |
| Selected place and reviewed route | Journey state in Riverpod |
| Progress, uncertainty, stop-alert decisions | Device-side deterministic engine |
| Locked-screen tracking and notification lifecycle | Android journey service |
| Place search/details and route requests | Backend provider adapters |
| Provider credentials, request limits, error normalization | Backend |
| Verified local stop metadata and supported-corridor versions | Backend-owned data, delivered to app |
| Wording, ordinary conversation, companion reactions | Existing voice/character systems |

The device's every location update must not require a backend round trip. The
backend receives an origin when planning/replanning; it does not need a continuous
user-location feed. An already loaded journey can retain its local progress logic
during a connection interruption, subject to SDK, licensing, data availability,
and route-validity constraints. This does not promise downloadable offline maps.

Google Maps SDK is the rendering choice. Use Places API (New) and Routes API for
the proposed server-backed planning path. Evaluate Navigation SDK separately for
supported modes, lifecycle, cost, and permitted spoken guidance before adopting
it for active navigation. Do not assume a driving-navigation SDK supplies Lagos
bus routing or that a displayed polyline is a navigation engine.

## 4. Domain contracts and invariants

Evolve the existing draft-only `NavigationGateway`; its string/bool/void signature
cannot represent confirmed places, route options, progress, or errors.

Introduce these concepts incrementally, with contract tests at their boundaries:

- `PlaceCandidate` / `SelectedPlace`: provider ID, display label, coordinates,
  provenance, service-area eligibility, explicit user selection.
- `LocationFix`: coordinate, monotonic age, horizontal uncertainty, speed/heading
  when valid, and source/status. Device clock changes must not freshen old fixes.
- `RoutePlan`: route ID/version, input revision, origin, selected destination,
  mode, geometry/legs, supplied estimates and their timestamps, source, expiry
  policy, and whether it is supported for planning or stop guidance.
- `TransitLeg`: boarding/alighting points, travel direction, ordered stops and
  geometry when available, provider provenance and corridor validation status.
- `JourneySession`: session ID, selected route version, lifecycle, current leg,
  progress confidence and emitted-alert ledger.
- `NavigationEvent`: typed approach, arrival candidate, location degraded,
  off-route, and journey-ended events. Events carry session/route revision IDs.

Required invariants:

1. Destination text, a selected real place, and a confirmed route are distinct.
2. A voice suggestion may start place lookup; it does not confirm a branch or start a trip.
3. Changing destination/origin/mode invalidates affected routes and cancels or
   disregards outstanding requests. An old response cannot replace a newer choice.
4. A route is computed for the actual mode. Driving directions cannot be relabelled bus directions.
5. Arrival at an alighting stop and arrival at the final walking destination are distinct.
6. Route/stop decisions never depend on an LLM inventing geography or interpreting raw GPS.
7. Progress uncertainty is represented explicitly, not hidden behind a precise-looking marker.
8. Starting, replacing, resuming, and ending a journey are explicit user-visible actions.

Journey lifecycle: `idle -> planning -> preview -> active -> arrived -> ended`,
with explicit paused/interrupted recovery. Fix quality (`acquiring`, `usable`,
`uncertain`, `unavailable`) is a separate dimension; a poor fix must not silently
end an active journey. Process-death recovery revalidates permissions, route data
and a fresh fix before enabling guidance again.

## 5. Sequential delivery and acceptance gates

Each phase is a reviewable change with relevant tests and an updated completion
record. Do not enable its dependent production behaviour until its gate passes.

### Phase 0: baseline, coverage and contracts

- Preserve current voice behaviour and record the existing Flutter checks.
- Confirm the Lagos service boundary, pilot corridors/directions, example
  destinations, and real boarding/alighting locations with the owner.
- Probe actual Google place/transit responses on those journeys using protected
  tooling; compare branch selection, route, direction and stop data to field knowledge.
- Record unsupported cases. A missing transit route is an unavailable result,
  not permission to ask the LLM to invent one.
- Establish project/environment names, monthly operating budget, expected pilot
  request volume, API quotas, final Android application ID and signing strategy.
  The current `com.example.navi` and debug signing are development configuration.
- Define OpenAPI v1 shapes, typed provider errors, data-retention rules and test
  fixtures. Check applicable provider terms for spoken instructions, data handling
  and attribution before implementing those uses.
- Verify Flutter/Android plugin compatibility, maintenance, licenses and SDK
  requirements before choosing versions; verify native service support explicitly.

Gate: a written coverage matrix, initial contracts, and a recorded supported pilot
scope. Unverified bus corridors stay preview-only or unavailable.

### Phase 1: map and foreground location foundation

- Add the Google map adapter to the existing preview flow under a feature flag.
- Configure an Android-restricted SDK key with API restriction, registered package
  and signing fingerprints. Provide a configuration error state when missing.
- Add on-demand location permission and settings recovery, including approximate-only
  access, permanent denial, GPS disabled and failure to obtain a fresh fix.
- Introduce a single owned location stream, freshness checks and quality evaluation.
  Display uncertainty honestly; diagnostic age/accuracy/update counters belong in
  a developer panel, not the main traveller interface.
- Support pan/recentre without fighting user camera gestures. Match dark/light
  themes while preserving road readability and attribution.
- Stop subscriptions when the foreground prototype no longer needs them. Do not
  advertise screen-locked journey guidance in this phase.

Gate: usable map and honest live position on TECNO KI7, tested outdoors, with
permission denial, stale fixes, GPS off/on and lifecycle changes. There are no
automated stop/arrival instructions yet.

### Phase 2: backend and destination confirmation

- Scaffold the backend and independent build/test/configuration commands.
- Implement `/v1/places/autocomplete` and `/v1/places/resolve`, runtime-validated
  requests/responses, bounded body sizes, deadlines and normalized error codes.
- Use anonymous guest authentication with verified short-lived tokens. Add app
  attestation as a supplementary abuse signal, never a substitute for rate limits.
- Keep Google web-service credentials server-side. Restrict APIs and use least
  privilege runtime identities; do not ship an unrestricted service credential.
- Add per-session/device and global request limits using shared state/managed
  controls; process-local counters alone cannot enforce a multi-instance quota.
- Debounce search, use Places session tokens correctly, and discard stale results.
  Resolve a spoken destination using the same confirmation path as typed input.
- Restrict supported destinations to the agreed Lagos boundary. A country filter
  or camera bounds alone do not enforce a Lagos service area. Handle border cases
  explicitly; verify permitted coordinate/boundary use under the provider terms.
- Show distinguishing branch/address information and let the user choose. If
  location permission is denied, retain manual origin/destination selection.

Gate: the user can confirm a real Lagos destination; ambiguous branches, rapid
query changes, no matches, auth failure, rate limits and network failures behave
predictably. The deployed gateway is not an unrestricted public provider proxy.

### Phase 3: real route preview

- Add `/v1/routes/plan` for selected origin/destination/mode with minimal provider
  field masks. Validate coordinates, supported modes and geographic scope.
- Return typed alternatives where available, leg details, geometry and estimates
  actually supplied by the provider. Give routes/source data explicit freshness.
- Replace the placeholder preview; retain purpose/checklist state and explicit Start.
- Implement walking first; expose transit only for verified provider responses
  and pilot coverage. Never substitute another mode without explicit user choice.
- Handle no route, provider outage, out-of-area origins, changed destinations and
  stale planning results. A denied automatic origin supports a manual start point.
- Add provider deadlines, bounded transient retries within one overall deadline,
  request IDs, redacted logs and cost/latency counters. Do not retry indefinitely.

Gate: confirmed endpoints produce a real, correctly labelled route; changing an
input invalidates it; unsupported bus journeys cannot start precise stop guidance.

### Phase 4: foreground journey progress and stop-alert engine

- Create a pure Dart progress engine, independently testable with synthetic traces.
- Evaluate fix age/uncertainty, plausible movement, route leg, travel direction,
  ordered progress, remaining route distance and verified stop position together.
- Consider candidate segments across a history window. A nearest-point calculation
  alone must not jump across parallel roads, a loop, a bridge or a later route leg.
- Reject implausible outliers without permanently freezing progress. Preserve
  uncertainty when multiple roads/levels remain plausible; do not force snapping.
- Separate advance approach, near-stop and arrival-candidate events. Calibrate
  timing to speed, sampling gaps and speech delay. Do not use one fixed-radius
  geofence for every route or assume a speed threshold proves alighting.
- Use hysteresis, session/route-scoped deduplication and expiry so events neither
  repeat nor play after their stop has passed. A poor fix suppresses precise
  instructions and surfaces a degraded state.
- Detect sustained off-route movement before replanning, with a cooldown and
  replan budget. Never silently switch the selected destination or travel mode.
- Require a fresh, plausible recovery window after long gaps or re-entry.

Gate: replay cases pass for approach, passage, missed stops, adjacent roads,
wrong direction, dense junctions, repeated coordinates, out-of-order/stale fixes,
teleports, loops, GPS loss and reroutes. Critical labelled cases must produce zero
wrong-stop events; expected approach events must also occur in valid traces.
Thresholds remain tunable policy, not a claimed accuracy guarantee.

### Phase 5: Android screen-locked journey lifecycle

- Add a location foreground service that the user starts through Start journey
  while the app is visible, with the required service type, permissions and a
  persistent notification containing an End action.
- Request only the permission scope needed for this lifecycle. Do not request
  background permission by default; evaluate it separately if a later feature
  genuinely requires starting/accessing location from the background.
- Ensure the location stream, progress engine and alert execution have a real
  background owner. Keeping native GPS running while the Dart UI is suspended
  is insufficient. Choose and verify a service-owned execution strategy here.
- Persist minimal permitted recovery state with session/version IDs. Avoid
  persisting provider data beyond its allowed terms. Require explicit recovery
  if reliable automatic resume cannot be established.
- Test screen lock, app task removal, process death, force-stop, reboot, calls,
  battery saver and revoked permissions on TECNO and another Android device.
  Document actual limitations; do not promise restart after an OS/user force-stop.
- End releases location/audio/service resources and prevents delayed alerts.

Gate: repeated locked-screen field journeys have measured update gaps and alert
delivery results. No claim of locked-screen support before this gate passes.

### Phase 6: journey voice and companion integration

- Publish typed navigation events to a journey-level coordinator. Existing voice
  ownership is home-scoped, so navigation must not depend on keeping Home mounted.
- Prioritize time-sensitive journey guidance above ordinary chat and companion
  reactions. Tag queued speech with session, route revision and relevance deadline.
- Use local templates and installed offline/native speech where possible for
  critical alerts; cloud conversational TTS must not be their sole delivery path.
  Provide visible and optional haptic alternatives if audio is unavailable.
- Handle audio focus, headphones, calls, user mute, cancellation and speech that
  would otherwise finish after the relevant junction.
- Add typed intents for current progress, repeat instruction, pause/end and route
  questions. Pass minimal verified facts to conversation; the LLM cannot manufacture
  ETA, fares, stops, or route availability or execute arbitrary destination changes.
- Keep general speech refinement and always-listening wake-word work separate.
  Voice provider migration to the gateway is scheduled before external rollout;
  this map work does not rewrite the current speech pipeline now.

Gate: ordinary conversation cannot block a valid time-sensitive alert; ended or
superseded sessions cannot speak stale guidance. Offline output behaviour is tested.

### Phase 7: Lagos pilot, operational readiness and rollout

- Validate each supported bus corridor in both directions using independently
  checked boarding/alighting positions and current provider responses. Maintain
  source, ownership, last verification and correction/disable procedure for
  Navi-owned stop records; do not copy a provider's dataset into an owned database.
- Expand the pilot beyond one phone. Include bus/walking, daytime/evening,
  congestion, adjacent roads, GPS degradation and intermittent mobile data.
- Predeclare the field sample and release thresholds before collecting the
  release-validation dataset. Use a separate calibration dataset; repeated tests
  on the same route alone must not be presented as broad Lagos validation.
- Record timely/correct, wrong, missed, late and uncertainty-suppressed alerts,
  plus positional uncertainty, speech delay, background gaps, battery/data use
  and actual request cost per journey. Report counts and denominators, not only percentages.
- Every reproducible wrong-stop failure blocks that corridor until fixed and
  replay-tested. Zero observed failures is evidence about the sample, not proof
  of universal correctness. If thresholds are undecided, rollout remains blocked.
- Complete production signing, restricted credentials, backend access controls,
  logs/retention, provider attribution, required notices and permitted guidance use.
- Resolve the previously reviewed voice credential/fallback/timeout issues before
  external release. They are tracked dependencies, not map-sprint scope expansion.
- Enable corridor/mode kill switches, staged builds and rollback. A provider
  outage or disabled corridor must yield an explicit unavailable/degraded state.

Gate: documented pilot report, passed release criteria, functioning rollback and
approved operational budget. Enable only the modes/corridors actually validated.

## 6. Cost, latency, data and operational rules

- Separate the mobile SDK key from backend web-service credentials and separate
  development from production. A Maps Android SDK key is expected on the client
  but must be app/API restricted; an LLM or server credential is not equivalent.
- Measure search-session, route-planning and replan volume; request only needed
  fields. Budget alerts are monitoring, not a hard cap. Add API quotas and service
  request limits, and a tested feature-specific disable path.
- Navigation progress is computed locally. Do not make billable Roads API calls
  for every fix, poll routes continuously, or run the LLM on every location update.
- Choose backend region and instance settings using measured phone-to-service
  latency and pilot economics. Measure cold starts before paying for warm instances.
- Keep API contracts versioned and backward compatible because mobile updates
  are not immediate. Add separate CI checks and staged deploys for app and service.
- Persist own preferences, exempt identifiers and independently collected stop
  records only where permitted. Provider caching/storage/attribution rules are an
  implementation constraint; offline and replay fixtures need valid provenance.
- Default diagnostics to event categories, durations and coarse quality summaries.
  Do not log precise routes, coordinates, destination text, raw audio or credentials
  to production telemetry. Trace recording requires explicit tester opt-in,
  restricted access, a documented retention period and deletion.
- Use a shared durable store only when needed for enforceable multi-instance
  limits or owned corridor records; select its schema, expiry and cost in Phase 2.

## 7. Work order and outstanding inputs

Execute Phases 0 through 7 in order. Stop at a failed acceptance gate and fix the
evidence-backed problem before enabling the dependent feature. Small reviewable
changes within a phase can be merged without enabling incomplete user flows.

Inputs to obtain at the point they are needed:

| Input | Needed before |
| --- | --- |
| Pilot Lagos journeys, directions and known stops | Coverage gate / bus guidance |
| Agreed Lagos boundary and expansion behaviour | Service-area enforcement |
| Final application ID, debug/release signing fingerprints | Restricted map configuration |
| Google project/configured APIs and local SDK key configuration | Real map device test |
| Operating budget, quotas, service auth and deploy target | Live backend/provider access |
| Field release thresholds and test sample | Release-validation runs |

Do not ask for raw API keys in chat or place credentials into this document.
Configure them locally or in the deployment secret store when integration needs them.
The current billing-enabled console account does not imply these APIs, restrictions,
or backend deployment are already configured.

First implementation slice: contracts/coverage inventory, then a foreground map
with a fresh location stream and visible uncertainty. Route confirmation follows;
no automated stop advice is enabled by the map-only milestone.

## 8. Implementation record

| Phase | State | Evidence |
| --- | --- | --- |
| 0: baseline/coverage/contracts | Planning recorded; remaining work pending | This document; existing navigation interface is a stub |
| 1: map/location | Implemented for development; device gate pending | Android map configuration, Riverpod location controller, quality policy and preview; see [setup/device checks](google_maps_setup.md) |
| 2: backend/places | Not started | No backend service exists |
| 3: route preview | Not started | Current screen is a placeholder |
| 4: progress/alerts | Not started | No active navigation engine exists |
| 5: locked-screen lifecycle | Not started | No journey foreground service exists |
| 6: voice integration | Not started | Current voice ownership is home-scoped |
| 7: pilot/rollout | Not started | No field navigation results collected |

## 9. Primary references checked 2026-11-12

- [Google Maps for Flutter](https://developers.google.com/maps/flutter-package/overview)
- [Google Maps coverage](https://developers.google.com/maps/coverage): country coverage does not establish transit coverage.
- [Routes transit requests](https://developers.google.com/maps/documentation/routes/transit-route)
- [Fused Location Provider](https://developers.google.com/location-context/fused-location-provider)
- [Android location accuracy and age](https://developer.android.com/reference/android/location/Location)
- [Android location foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#location)
- [Maps credential security](https://developers.google.com/maps/api-security-best-practices)
- [Places session tokens](https://developers.google.com/maps/documentation/places/web-service/place-session-tokens)
- [Places policies](https://developers.google.com/maps/documentation/places/web-service/policies)
- [Routes policies](https://developers.google.com/maps/documentation/routes/policies)
- [Cloud Billing budget alerts](https://docs.cloud.google.com/billing/docs/how-to/budgets)
- [Cloud Run overview](https://docs.cloud.google.com/run/docs/overview/what-is-cloud-run)
