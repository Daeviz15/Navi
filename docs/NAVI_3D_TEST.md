# NAVI — Character Interaction Spike v0.1

This archive contains ONLY changed/new files for your existing Navi Flutter project. Do NOT replace your entire project.

## Scope
- A separate `/character-lab` screen reached via the new 3D icon beside the moon/sun toggle on the home screen.
- A local GLB with no downloaded textures, a prototype **woman-like figure** with braids and a navy jacket; NOT the approved realistic Navi design.
- A real 3D viewpoint you can drag to turn; tap attempts to play Wave; long-press attempts Listen; buttons also trigger animation directly.
- Four named clips: Idle, Wave, Listen, Nod. The Listen clip does not turn on the microphone or use AI.
- Back button returns to the current (unchanged) home, without affecting journey state.

## Replace/add files by exact project path
- `pubspec.yaml` (adds flutter_3d_controller and a local GLB asset)
- `android/app/src/main/AndroidManifest.xml` (allows local WebView HTTP traffic; CHECK before overwriting if you've customized it)
- `lib/app/router.dart` (new `/character-lab` route)
- `lib/features/home/presentation/home_screen.dart` (one extra AR icon in header; all else kept)
- `lib/features/character/presentation/character_lab_screen.dart` (new)
- `assets/models/navi_interaction_test.glb` (new)
- `docs/NAVI_3D_TEST.md` (this file, optional)

## Run and test on your TECNO KI7
In your Navi project folder:

```sh
flutter pub get
flutter analyze
flutter run --profile
```

Use an Android physical device. The test uses `flutter_3d_controller: ^2.3.0`, which embeds a local WebView based on Google's model-viewer. It is a useful functional spike, **but the GLB being tiny does not automatically make the WebView lightweight**. Check performance in profile mode before choosing this for your production home screen. The 3D route is *not loaded on home*.

Open Navi → tap the cube/AR icon in the upper-right corner → drag the character left or right. Try tapping/long-pressing her, then Wave, Listen, Nod and Reset view buttons. Native Android WebView gesture routing may prevent parent `Listener` callbacks on some devices, which is why we also provide guaranteed Flutter buttons. This first pass is NOT precise 3D bone/face tap-hit-testing.

## Limitations and next checkpoints
1. The geometric low-poly figure is a temporary interaction stand-in, not the photorealistic signed-off Navi avatar. It deliberately has no high-quality skin/textures.
2. WebView renderer is likely heavier than the GLB bytes; a low-frame-rate result rules out the engine for the always-visible home without further work.
3. This proves camera rotation and playing preauthored transform clips. True 3D surface hit-testing and eye-gaze following a tap point would be separate engineering milestones.
4. Android `usesCleartextTraffic="true"` is a broad permission used here to allow the package's local HTTP viewer. Before production release, review and constrain it to localhost via network-security-config and audit the plugin's networking.
5. No wake word, TTS or navigation/GPS is added. Existing Navi functionality is preserved.
6. No Flutter SDK is available in the file-generation environment, so **the code has not been built or device-tested here**. Please share `flutter analyze` output if needed.

## Acceptance criteria
- GLB opens without a network asset download.
- Figure rotates with a single-finger drag.
- Wave, Listen, Nod buttons visually move parts of model.
- No severe lag / overheating on your TECNO KI7 in profile mode, compared to previous orb home.
- Return home without changes to Navi's destination/preparation/preview flow.

If the figure is not centered in the viewer, use two fingers to adjust, then Reset view. If black/blank, confirm INTERNET and cleartext manifest, Android System WebView availability and flutter pub get.
