# Navi

A Flutter travel companion with a compact Syne typeface, muted golden-yellow accents, solid black surfaces by default, a warm light theme, and a procedural volumetric Cloud companion that reacts in real time to user speech.

## Run

```sh
flutter pub get
flutter run --dart-define=GROQ_API_KEY=your_groq_key --dart-define=DEEPSEEK_API_KEY=your_deepseek_key
```

You can also store your keys in a local git-ignored JSON file (e.g. `env.json`) and run:

```sh
flutter run --dart-define-from-file=env.json
```

## Current experience

- Navi renders a procedural, volumetric Cloud companion (`lib/core/widgets/navi_companion.dart`) using a 48-point Catmull-Rom spline contour, 7 internal radial-shaded lobes, core luminescence, and concentric acoustic resonance rings.
- Live microphone PCM16 audio is metered over a 50 ms window (`lib/features/voice/data/pcm_audio_levels.dart`) with asymmetric attack/release smoothing and fed directly to `NaviCompanion`'s `CustomPainter` via a `ValueListenable<double>` so the Cloud vibrates and billows at 60 fps in response to your voice without rebuilding the widget tree.
- The top-right appearance control switches between dark and light modes. The preference lasts for the current app session.
- Interactions reset the quiet timer. Background screens and reduced-motion settings suppress discretionary gestures.
- The home wordmark and appearance control stay fixed while the page scrolls.
- Tap **Navi itself** to start a conversation on Home or the journey map. Tap again to stop, including during speech or processing. The ear and microphone buttons have been removed.
- Conversations continue between replies until destination and purpose are captured. Navi finishes the confirmation before stopping. Casual trips need no checklist; silence and model follow-up flags do not silently end a session. Backgrounding ends capture and requires a fresh tap on return.
- **Speech-to-text (`GroqSpeechEngine`)**: 16 kHz mono PCM16, client-side VAD with a -43 dBFS onset, 750 ms silence endpoint and 300 ms pre-roll; complete utterances go to Groq Whisper.
- **Conversation (`DeepSeekVoiceAgent`)**: local Lagos destination/preparation shortcuts plus structured Groq model replies, with optional DeepSeek fallback. The selected journey destination is available as context on the map. Cancellation guards pending replies and conversation history.
- **Voice output (`AndroidVoiceOutput`)**: Groq Orpheus audio with Android TTS fallback. Capture stops during playback and resumes while the conversation still needs trip details.
- See [voice behavior and device checks](docs/voice_response_validation.md) and [local maps backend setup](backend/README.md).

## Assets

All legacy character videos (`.mp4`), animated `.webp` files, poster images, 3D `.glb` models, and bundled offline speech weights (`moonshine_tiny_en`, `en_small`, `en_commands`, `wake_navi`) have been removed to keep the release APK lightweight.

Syne is bundled in `assets/fonts/` for offline use. Its SIL Open Font License is included alongside the font. Source: https://github.com/google/fonts/tree/main/ofl/syne.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
```
