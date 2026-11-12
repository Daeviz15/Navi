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
- Tap the microphone icon to start a Push-to-Talk voice turn:
  - **Speech-to-Text (`GroqSpeechEngine`)**: Streams 16 kHz mono PCM16 audio through a client-side RMS Voice Activity Detector (`-40 dBFS` onset, 750 ms silence endpointing, 300 ms pre-roll ring buffer) and transcribes complete utterances using Groq's `whisper-large-v3-turbo` endpoint (`https://api.groq.com/openai/v1/audio/transcriptions`).
  - **Conversational & Intent Reasoning (`DeepSeekVoiceAgent`)**: Sends the transcript and available Lagos places to DeepSeek (`deepseek-chat` in strict JSON mode) to produce a concise spoken reply, companion mood, and structured destination action (`select_place`, `clear_place`, `sleep`, or `none`). Falls back automatically to `LocalCommandRouter` when offline or when `DEEPSEEK_API_KEY` is omitted.
  - **Voice Output (`AndroidVoiceOutput`)**: Speaks the reply via Android's native `TextToSpeech` engine while the Cloud companion animates its speaking cadence, then automatically closes the microphone at the end of a non-follow-up turn so zero background network or battery cost is incurred.

## Assets

All legacy character videos (`.mp4`), animated `.webp` files, poster images, 3D `.glb` models, and bundled offline speech weights (`moonshine_tiny_en`, `en_small`, `en_commands`, `wake_navi`) have been removed to keep the release APK lightweight.

Syne is bundled in `assets/fonts/` for offline use. Its SIL Open Font License is included alongside the font. Source: https://github.com/google/fonts/tree/main/ofl/syne.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi
```
