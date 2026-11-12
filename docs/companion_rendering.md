# Character rendering

Riverpod's `CompanionController` selects the behavior, clip, and revision from the voice session and touch events. The widget owns animation tickers, image codecs and native video handles. These resources remain scoped to the rendered stage; per-frame playback does not update Riverpod application state.

## Rest and listening

The default idle state is a held poster, with no video decoder or animated image codec. While home is visible, one weighted random idle gesture is scheduled after 90–150 seconds without interaction. It plays once and returns to rest, then starts a new quiet interval. Touch, typing, scrolling and voice phase changes reset this timer. Hidden/background screens, voice preparation, errors and reduced motion suppress discretionary gestures. Revision checks reject stale completion events; a 12-second fallback ends a gesture if its playback callback never arrives.

Listening also holds a poster, from the user's `assistant/listening_001.mp4`. `tools/prepare_listening_pose.ps1` extracts 0.75–1.50 seconds at 24 fps and pads the square source to 540 × 960 without distortion. Its viewport covers the central 540 × 540 source area. Poster frame 16 selects the half-closed-eye expression at approximately 1.42 seconds of the source. This tilted-head expression stays until the voice session leaves listening; clip duration never ends a voice turn. Holding the pose avoids a visible short loop. The normal dissolve and attention zoom still apply; thinking and speaking remain animated. Silence endpointing and voice deadlines belong to the speech layer, not playback.

## Prepared handoffs

`NaviCompanion` keeps the current layer visible while mounting a transparent incoming layer. Dark-mode MP4 playback must initialize, be muted, and report an advancing position before a 240 ms eased dissolve begins. Position advancement is a readiness proxy, not an explicit native first-texture callback. Light mode waits for the animated image's first decoded frame. The same keyed layer survives promotion to current, preserving the warmed decoder and playback position.

The outgoing decoder is released after the dissolve. Another decoder cannot mount until that release finishes, keeping a hard two-player bound. State changes during loading coalesce to the latest requested clip; stale completion callbacks cannot advance behavior. An in-progress dissolve finishes before handling the next request, avoiding opacity jumps from restarting a blend midway.

Initialization has a five-second deadline; foreground playback warmup has a two-second deadline. Failure falls back to the corresponding transparent poster. Both deadlines are cancelled on disposal, and warmup time does not accumulate while paused. Background and hidden stages pause playback. Reduced motion uses static images and disables the attention zoom and dissolves.

Looping thinking and speaking behaviors request another prepared cycle approximately 800 ms before their end, using the same dissolve rather than the native player's hard loop. Transparent animations request a cycle 20 frames before the end. These early handoffs soften loop seams but do not create new motion between unrelated poses.

## Framing and layout

The earlier renderer enlarged a portrait source to 135% of a square stage, cropping the head and feet. The new renderer uses a contained viewport with 20 logical pixels of vertical stage padding and 16 pixels horizontally. Source aspect ratio is preserved. Each clip's viewport in `NaviClip` uses coordinates at 540 × 960 and includes motion margins around its measured silhouette.

Viewports normalize the character's apparent height and baseline. Listening, thinking and speaking also apply a subtle scale of 1.035 over 440 ms using `easeInOutCubic`, anchored at the feet. Stage size changes use the same eased duration, so responsive layout changes do not snap. The home subtitle has additional separation above the stage. The caption remains below the reserved character space.

The rendering uses the existing solid theme colors and transparent assets. There are no gradients, transport controls, or extra product UI.

## Verification

`test/companion_transition_test.dart` exercises delayed initialization, delayed playback progress, opacity during handoff, stale completion events, rapid voice changes, the two-player limit, disposal during warmup, the attention scale, reduced motion, transparent light mode, and loop handoffs. Existing home tests retain narrow-screen, large-text, keyboard, fixed-header and lifecycle coverage.

Run these optional tools when changing source clips or framing:

```powershell
flutter test tools/inspect_companion_framing_test.dart --reporter expanded
flutter test tools/preview_companion_layout_test.dart --reporter expanded
```

The first measures sampled alpha silhouettes. The second exports idle and attention layout previews in both themes and a narrow layout into `build/companion-previews/`, using predecoded posters and reduced motion for deterministic geometry checks. The widget tests separately exercise the animated zoom. These previews verify framing, not native decoding performance.

Check the full sequence on the target phone in profile mode (`flutter run --profile`). Measure frame times and handoff latency, especially during speech model startup, theme switches, and loop restarts. Different facial expressions, arm positions, hair shapes, props, and lighting are baked into the source clips. A dissolve can soften those differences; fully continuous movement requires compatible start/end poses or authored transition clips. No frame interpolation or pose morphing is performed here.
