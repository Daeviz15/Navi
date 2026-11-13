# Trip and voice reliability implementation plan

Date: 2026-11-13  
Status: staged implementation in progress. State/lifecycle protection and
destination confirmation, active-route retention and approximate progress are
implemented and regression-tested. Broader fact confidence, voice deadlines,
anchored instructions, field calibration and production deployment remain unfinished.

## Implementation record

2026-11-13: state/lifecycle foundation delivered.

- `JourneyController` owns a typed, container-local `JourneyIdentity` consisting
  of a trip ID and destination/mode revision. Preparation, checklist edits and
  activation retain identity; routing edits revise intent; reset separates trips.
- Navigation state/results carry that identity. Search and route completions
  from an earlier trip cannot populate a replacement trip, even for the same query.
- `journeyTransitContextProvider` derives the voice-facing snapshot from the
  existing owners. The bridge acknowledges accepted voice changes synchronously;
  external intent changes cancel pending conversation work. Enrichment cannot
  overwrite context for a newer identity.
- End-trip invalidates both GPS and voice before awaiting cleanup. Repeated
  commands share pending cleanup; late cancellation cannot reset new acquisition
  or clear a newer conversation. UI/voice start/end commands check their identity.
- Area lookup generations reset on trip/intent changes. An old lookup's completion
  or `finally` block cannot publish into or unlock a newer lookup.
- Initialization rejects permission completion for a replacement draft. End-trip
  navigation also checks identity after awaited cleanup.

Verification: **141 Flutter tests passed**, including 13 new regression cases;
`flutter analyze --no-pub` reported no issues. No physical-phone navigation or
latency measurements were performed in this slice. Backend source was unchanged.

Contract rollout refinement: introduce destination-confirmation and
provenance/freshness types with their consuming fixes in packages 2-4, rather
than adding unused parallel models. Destination confirmation is now implemented
below; the derived snapshot does not yet certify progress/estimate confidence.

2026-11-13: destination confirmation delivered.

- Search produces immutable `DestinationSuggestions` with an opaque search token
  bound to the journey identity. A `ConfirmedDestination` records the canonical
  provider place and explicit tap/voice evidence. `selected` is derived from that
  confirmation, never from result order. A single match still needs confirmation.
- No route request or blue destination cloud appears before confirmation. The
  map shows numbered names/addresses, and Home distinguishes a pending address
  from the confirmed place. Bus/walking changes preserve an accepted address,
  while rebinding pending controls and recalculating only the route as needed.
- Tap and voice invoke the same synchronous, guarded commands. A new search,
  rejection, destination change or newer selection invalidates old controls.
  Duplicate confirmations do not trigger additional route requests. Malformed
  places and duplicate provider IDs cannot be selected.
- Voice handles option numbers, unique names/addresses, agreement and rejection
  locally. An option is read back with its full name/address. Only after that
  speech completes can the next agreement confirm it. An unrelated intervening
  turn, new tapped session, replacement search or cancelled readback disarms the
  old prompt. The LLM does not supply place IDs or apply confirmation commands.
- A failed/stale command cannot speak a successful confirmation. Pending address
  status and options are included in model context, and the connection fallback
  no longer claims route guidance for an unconfirmed destination.
- `Refine destination` allows a specific typed query when suggestions are wrong.
  It starts a new destination intent, clears old preparation and requires another
  confirmation. The dialog states the checklist effect and cannot overwrite a
  newer journey if it remains open across a trip change.

Verification: **163 Flutter tests passed**, including 22 new cases in this slice;
`flutter analyze --no-pub` reported no issues and diff whitespace checks passed.
Widget tests exercise map taps, the real voice-to-navigation command adapter,
stale pickers and query refinement. Google and audio responses are fixtures;
physical-phone speech, GPS and latency were not measured. Backend source and
wire contracts did not change.

Physical-phone check for this slice (pending):

1. Start a journey with a business that has multiple Lagos branches. Before
   selection, check that no blue destination cloud or route is shown.
2. Confirm a displayed name/address by tap and check the resulting place and path.
3. On an unconfirmed journey, tap Navi and say "option two". Wait for the full
   address readback, then say "yes". Check the same confirmed place appears.
4. Try "no", stopping/restarting Navi, changing destination and answering an
   unrelated question between readback and "yes". No old address should be
   silently confirmed. A fresh readback may be required.
5. Refine a wrong query, check preparation resets, and confirm the new result.

2026-11-13: active-route retention and progress foundation delivered.

- Active movement no longer invalidates a route at 150 m from its origin.
  Origin movement checks remain specific to unstarted previews. A valid initial
  response can be adopted while an active traveller moves or loses GPS precision.
- Geometry and estimate freshness are separate. Five-minute expiry retains an
  active path, marks planning estimates stale, and refreshes only when a usable
  foreground fix is available. The previous path remains during refresh/failure;
  a different destination or mode invalidates the old route immediately.
- Refresh is single-flight per intent. Repeated commands share the pending
  future. The default minimum interval is 30 seconds; consecutive failures back
  off to 60 and 120 seconds. Cooldown completion alone does not start an API call.
  Identity guards reject old requests and timers after an intent changes. An old
  transport request may still finish; it cannot publish into the new intent.
- `JourneyRoute` freezes its input collections and caches `RouteGeometry` once.
  The pure `RouteProgressTracker` uses segment projection for both along-route
  progress and deviation. A sparse segment is not judged by its nearest vertex.
  Physical travel budgets and ambiguous-branch checks resist jumps at crossings
  and parallel roads; actual backtracking can increase remaining distance.
- Route matching uses an independent provisional policy: fixes at most 10 s old
  and 30 m reported uncertainty; confirmed deviation requires at least three
  distinct usable samples over six seconds, with no sample gap over eight
  seconds, beyond the larger of 60 m or three times reported uncertainty.
  Recovery requires two usable matches. Walking/bus plausibility budgets are
  deliberately broad; these are engineering defaults, not validated accuracy
  guarantees or thresholds for arrival/stop alerts.
- `NavigationController` owns the tracker for its adopted geometry and publishes
  immutable `RouteProgress` in its existing Riverpod state. Home, map and voice
  consume that same result. This refines the earlier separate-controller proposal:
  there is no second mutable progress store or controller dependency cycle.
- Poor, stale, ambiguous or off-route positions withhold current remaining
  distance. No straight-line substitute is labelled as road distance. Geometry
  remaining distance is scaled to the provider route length and explicitly
  approximate. Provider duration remains a labelled planning estimate from its
  original refresh, never a proportionally scaled live remaining ETA.
- The map does not automatically fit the whole path on every refresh. Its moving
  overlay initially paused without an eligible route match. The directional
  preview refinement below supersedes that initial presentation gate.
- The old first-five instruction list is withheld from `nextGuidanceSteps`.
  Neither those unpositioned hints nor zero remaining geometry distance prove
  the next junction, correct bus stop or arrival. Structured provider-step parity
  and validated instruction progression remain a separate gated task.

Verification: **186 Flutter tests passed**, including 12 new geometry/matching
cases and 11 controlled-clock lifecycle cases. The existing route adapter test
now verifies immutable cached geometry rather than proportional ETA.
`flutter analyze --no-pub` reported no issues, and diff whitespace checks passed. All
route responses and movement traces in these tests are fixtures; no physical
Lagos route replay, native map capture, battery profile or GPS calibration was
performed. Backend wire contracts did not change.

Physical-phone check for this slice (pending):

1. Confirm a destination, move beyond 150 m along its route, and verify that the
   line persists and approximate progress follows the journey.
2. Lose location precision or background the app. Check that the path stays, while
   precise progress is withheld. The directional preview may continue with weak
   GPS, but pauses in the background; background navigation is not enabled.
3. Leave an active path for five minutes. Verify its stale planning label and
   retained geometry, then restore usable GPS and observe a refresh.
4. Test a network failure during refresh and a destination change while loading.
   Neither should erase the applicable old path prematurely or restore an old
   destination after the new one is selected.
5. Replay/field-test parallel roads, flyovers, crossings and real backtracking on
   selected Lagos corridors before enabling spoken manoeuvre or stop alerts.

2026-11-13: guided destination confirmation and map preview refinement.

- When matching addresses arrive on the map, the screen smoothly reveals and
  highlights the confirmation section. A visible next-step button can bring it
  back into view. Manual scrolling while search is pending suppresses the initial
  automatic scroll; later location updates do not repeatedly take over scrolling.
- Navi gives one short orientation per destination/mode intent when no tapped
  conversation is running. `VoiceSessionController` serializes this speech-only
  output with conversation output. It creates no microphone or speech recognizer,
  requests no recording permission, and starts no automatic follow-up capture.
- A small instance of the shared tappable companion sits beside the numbered
  choices. Tapping it interrupts orientation and starts the existing conversation.
  Option selection still requires completed full-address readback and agreement;
  the generic orientation never arms a bare "yes" as confirmation.
- Search tokens and journey identities guard pending speech and scroll effects.
  Confirmation, trip changes, leaving the map or backgrounding cancel obsolete
  orientation. Completed orientation text is cleared after confirmation instead
  of continuing to ask for an address that is already accepted.
- After tap or voice confirmation, the screen returns to the boxed map. The
  camera frames the confirmed blue cloud and available current-position cloud
  even while routing is pending. A subsequent GPS update cannot overwrite a
  fitted route overview with a current-position-only camera move. New destination
  choices reset old map-pan suppression; ordinary route refreshes preserve it.
- The moving highlight is explicitly a directional preview of provider geometry,
  independent of eligibility to report remaining distance. There is no invented
  straight connector while route lookup is pending or fails. Existing confidence
  gates still govern approximate progress and voice facts. Stale paths, confirmed
  deviation, hidden surfaces and backgrounding pause the highlight.
- Reduced-motion settings use immediate section/camera positioning and a static
  route. The moving highlight updates a bounded 13-point overlay at 20 Hz; native
  rendering smoothness and device cost still require a physical-phone check.
- Riverpod remains the owner of trip, navigation and voice state. Widget-local
  scroll controllers, section keys and one-time presentation effects introduce no
  second destination or route store. The Maps platform-interface dependency is
  development-only for map/controller regression fixtures.

Verification: **200 Flutter tests passed**; `flutter analyze --no-pub` reported
no issues, and diff whitespace checks passed. Backend source and wire contracts
were unchanged in this refinement.

Automated coverage includes speech-only output, interrupt/cancel races, completed
prompt cleanup, unmounting without provider mutation, automatic/manual scrolling,
voice selection, reduced motion, map cloud objects, camera commands and directional
flow with unavailable GPS progress. These are provider/platform fixtures, not a
claim of physical-device audio latency, native frame timing or Lagos accuracy.

Physical-phone check for this refinement (pending):

1. Start a new trip and wait for matches. Confirm that Navi explains the next
   step once, choices become visible, and recording stays off until Navi is tapped.
2. Tap the small Navi beside the choices, say "option two", wait for its address
   readback and agree. Also test choosing an address directly by tap.
3. Verify return to the map, both clouds, and the flowing real route when routing
   succeeds. If routing fails, keep the confirmed cloud and display the actual
   failure; do not substitute a straight line.
4. Scroll manually before search completes, stop Navi mid-prompt, leave the map
   and background the app. Check for unwanted scrolling, late speech or capture.
5. Test reduced motion, weak GPS and route expiry. Route-preview movement must
   never be described as measured traveller progress or proof of arrival.

Next implementation package remains typed route provenance and current-area freshness.
Bus-versus-road-corridor contracts, stale area labels and shared speech deadlines
remain open items from packages 4-5.

## Outcome and scope

Navi should keep a coherent trip across Home and the map, confirm the correct
destination, retain the route during travel, and answer from trustworthy journey
data with bounded voice delays. Keep the existing Flutter app, Riverpod, and the
independently deployable TypeScript backend in this repository.

Preserve dark mode, tap-to-talk, tap-again-to-stop, destination/purpose preparation,
checklists, and the compact companion above the map. Do not reintroduce hands-free
listening. Distinguish ending a planning conversation from ending an active trip.
During an active trip, completing an answer must not reset the journey.

This plan refines the broader [Lagos roadmap](maps_navigation_plan.md). It focuses
on current integration defects before adding turn-by-turn or bus-stop alerts.
There is no claim of perfect GPS accuracy or verified Lagos-wide transit coverage.

## Current baseline and priorities

The preceding review passed 128 Flutter tests and static analysis. Those checks
do not establish route continuity on a moving phone or real voice latency.

| Priority | Observed behavior | Required change |
| --- | --- | --- |
| P0 | Movement beyond 150 m from the route origin clears the route; expiry also clears it | Separate preview validation, active progress, geometry retention, and estimate freshness |
| P0 | Search selects its first result automatically | Distinguish a suggested place from a destination the user confirmed |
| P0 | Driving fallback retains the requested bus mode | Carry actual route provenance and prevent driving estimates becoming bus promises |
| P0 | Old area names can survive stale GPS or lookup failure | Attach freshness and fix quality to location facts used by UI and voice |
| P1 | Cloud speech providers can time out sequentially before native speech starts | Use one playback-start budget and cancellation across the provider chain |
| P1 | Multiple providers and a bridge coordinate lifecycle side effects | Make ownership, identities, and trip transitions explicit |

## State ownership with Riverpod

Keep existing controllers where they already own the right responsibility. Add a
controller only for independently evolving state; use derived providers for
computed views of existing state. Do not introduce a second mutable trip store.

| Owner | Canonical responsibility |
| --- | --- |
| `JourneyController` | Trip identity, intent revision, destination text, purpose, checklist, requested mode, and trip lifecycle |
| `NavigationController` | Search candidates, confirmed geographic selection, request state, adopted route and refresh state |
| `LocationController` | One location subscription, permission, foreground lifecycle, fix freshness and uncertainty |
| `CurrentAreaController` | Area observation tied to its source fix, lookup time, confidence and failure state |
| `RouteProgressTracker`, owned by `NavigationController` | Temporal segment matching, approximate progress and sustained off-route evidence; immutable results in navigation state |
| Proposed derived `JourneyGuidanceSnapshot` | The eligible current facts shared by UI, deterministic replies, and LLM context |
| `VoiceSessionController` | Tap session, microphone, transcription, reasoning, output, turn cancellation and visible conversation status |
| `ActiveTripCoordinator` | Explicit start/change/end commands across owners; orchestration without a second state store |

Widgets render state and dispatch commands. Voice emits typed trip-action requests;
it does not establish geographic truth. Centralize routing side effects in a
single action coordinator rather than scattering listeners across screens.

Give a trip a stable ID and an intent revision. Route, geocoder and voice work
also carry their request/turn generation and relevant trip revision. An async
completion may publish only if its identity is still current. Ending a trip
invalidates old work before awaiting cleanup; old cleanup must not stop a new trip.

Retain trip state across screen changes while the trip is active. Explicitly stop
resources when their session ends. Use automatic disposal for bounded request
providers and `ref.onDispose` for timers, subscriptions and clients. Keep fast
audio meters and map animation separate from broad trip-state rebuilds. Use
`select` and narrow derived providers where measurement shows unnecessary updates.

## Sequential implementation packages

### 1. Establish contracts and lifecycle guards

- Add immutable trip identity/revision and documented legal lifecycle transitions.
- Define typed destination confirmation, route provenance, distance/ETA quality,
  area observations and guidance availability. Avoid a single `isReliable` flag.
- Keep one owner for each fact. Derive the voice journey snapshot from these
  owners instead of maintaining another independently editable trip context.
- Guard end/change/start commands and in-flight completions against stale IDs.
- Preserve current behavior outside the defects; migrate one consumer at a time.

Acceptance: delayed search, route, area, voice and end-trip operations cannot
overwrite or stop a newer trip. Repeated end/cancel commands are safe. Home and
map show the same trip, destination, purpose and checklist.

### 2. Confirm geographic destinations

- Search returns suggestions, not confirmation. Show place name and address.
- Bind confirmation to a specific place ID and current search/intent revision.
- Support selection by tap and explicit voice confirmation using the same command.
  Ask a concise clarification when an area or business has multiple plausible
  matches. A rejected suggestion cannot become the confirmed destination.
- Show the blue cloud as confirmed only after that action. A preview, if shown
  earlier, must remain visibly provisional and cannot feed authoritative guidance.
- Destination changes invalidate the old destination's route and guidance before
  starting the new lookup. Keep preparation where applicable without attaching
  an old checklist or address to a new place.

Acceptance: a multi-branch query never silently confirms the first result;
declining or changing it cannot leave old destination guidance active. A late
voice confirmation cannot confirm a newer suggestion accidentally.

### 3. Keep active routes and calculate progress consistently

- Separate route preview origin checks from active-trip movement. Normal travel
  must not invalidate a route just because the user moved beyond 150 m.
- Separate geometry retention from ETA/traffic freshness. Refresh estimates or
  the route without blanking the last applicable path; label stale estimates.
  Retention applies only to the same confirmed destination and mode.
- Precompute cumulative segment lengths. Use segment projection for both progress
  and off-route distance, instead of mixing segment distance with nearest vertex.
- Use recent movement, uncertainty and hysteresis to resist jumps at parallel
  roads, crossings and route loops. Do not force monotonically increasing progress
  when the user actually turns back.
- Require sustained usable evidence before rerouting. Allow one refresh at a
  time, with cooldown/backoff; never make a route API call for every GPS sample.
- Progress instructions using structured step locations. The first five route
  instructions are not automatically the user's next five instructions.

Acceptance: simulated and recorded travel beyond 150 m retains the route;
five-minute estimate expiry does not erase the active path. Sparse geometry does
not create a false off-route event halfway along a segment. Poor fixes suppress
precise guidance. Route loops and genuine backtracking have regression fixtures.

### 4. Make guidance truthful under uncertainty

- Keep requested mode separate from returned route kind: walking, verified transit,
  or road corridor. Carry the same contract through backend and direct adapters.
- A road corridor can be offered as a clearly labelled preview; its driving ETA
  must never appear as a verified bus arrival time or support bus-stop instructions.
- Distinguish provider estimates, rough proportional estimates, straight-line
  distance, and unavailable values. Do not label a straight-line fallback as
  remaining road distance or a proportional ETA as live traffic timing.
- Store area label with source coordinates/fix identity and observation time.
  Expire or mark it last-known when the fix ages, movement makes it irrelevant,
  or lookup freshness cannot be established. Reject late lookup results.
- Bound reverse-geocoding frequency and retries. A failed lookup may retain
  explicitly last-known information, but cannot support “you are here now”.
- Enforce eligibility before both deterministic replies and LLM prompting. The
  LLM explains eligible facts; it cannot upgrade their confidence.

Acceptance: stale/missing GPS prevents a current-area claim in every response
path. Bus fallback cannot expose a bus ETA. UI and voice agree on unavailable or
approximate information. The existing 10-second/50-metre display-quality policy
is not treated as proof that a stop or junction alert is safe.

### 5. Bound voice response latency without cutting speech

- Instrument speech end, transcription completion, reasoning completion, synthesis
  start, and actual first audio. Track microphone readiness separately.
- Preserve pause-aware endpointing and measure false endings and clipped first
  words alongside latency. Faster timeout settings alone are not success.
- Give the whole TTS chain one playback-start deadline. Use remaining budget for
  each provider, cancel expired work, and skip unhealthy providers temporarily.
- Start native fallback when that shared budget expires. Token-check audio before
  playback so an old turn cannot speak after cancellation or a new tap session.
- Include provider/model/voice/format in bounded synthesis cache keys. Do not
  let stale requests publish audio to the current session.
- Show consistent states: listening, transcribing, thinking, speaking, or retry.
  Do not display listening before the microphone is ready. Preserve the user's
  last transcript while a reply is being prepared.

Proposed initial targets, to validate against a physical-phone baseline: end of
speech to first response audio at or below 2 seconds median and 4 seconds p95 on
a defined working-network profile; begin native fallback within a shared
4-second cloud synthesis budget. These are targets, not achieved results. Track
complete-answer audio separately from acknowledgement audio so a filler cannot
hide a slow answer. Revisit targets with measured accuracy and provider latency.

Acceptance: two failed cloud TTS providers cannot each consume a full independent
timeout. Cancellation produces no late or overlapping audio. Transcription stays
visible, and latency gains do not increase truncated utterances. Test on TECNO KI7.

### 6. Enforce production boundaries and validate Lagos journeys

- Keep backend and Flutter in this repository, with independent build/deploy
  configuration. Choose staging and production hosting as a separate deployment
  task; this plan does not deploy infrastructure.
- Make direct Google access an explicit development policy. Release configuration
  must not silently bypass the intended authenticated backend after an invalid
  URL or backend failure. Match adapter semantics with shared contract fixtures.
- Complete server-side secret handling for paid providers, authenticated access,
  request validation, bounded retries/timeouts, usage controls and deployment
  health checks. Verify which controls already exist before adding equivalents.
- Log timings, error codes, provider route kind and cancellation outcomes without
  raw audio, transcripts, precise movement traces or credentials by default.
- Measure route requests per trip, voice failures, response latency, memory,
  battery and release size. Investigate budgets using release builds, not only
  debug APK size. Establish operational alerts and a rollback procedure.
- Validate selected Lagos corridors on physical devices: parallel roads,
  flyovers, poor GPS, route changes, permission loss, network loss, background /
  foreground transitions and return to Home. Background navigation remains a
  separate platform capability, not an assumption of this foreground design.

Acceptance: release configuration fails clearly when required services are absent;
provider failures do not manufacture guidance. Record false, missed and suppressed
alerts together. Enable stop/arrival claims only on corridors that pass documented
field criteria; thresholds must be agreed before those trials, not after them.

## Verification and delivery discipline

Deliver one package at a time with focused regression tests, static analysis and
relevant backend tests. Use fake clocks, controlled async completions, synthetic
location sequences and provider fixtures; ordinary tests should not spend API
credits. Add device checks for microphone/playback and moving-route behavior that
unit tests cannot establish. Rerun broader checks when the changes warrant them.

Each package records: changed behavior, tests and device evidence, unresolved
limits, and its acceptance result. No framework migration, separate repository,
distributed-service split or new state library is required for these fixes.

Implementation starts with package 1, followed immediately by destination
confirmation and route continuity. New companion effects and navigation features
follow the reliability gates rather than expanding the current uncertainty.

## Supporting guidance

- [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
  support separated UI/data responsibilities and testable components.
- [Riverpod automatic disposal](https://riverpod.dev/docs/concepts2/auto_dispose)
  documents provider lifetime and resource cleanup; choose retention by ownership.
- [Google transit routes](https://developers.google.com/maps/documentation/routes/transit-route)
  describe transit-specific route data; a driving result is not equivalent.
