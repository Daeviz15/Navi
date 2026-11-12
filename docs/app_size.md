# Android app size audit

Measured 11 November 2026. MB means 1,000,000 bytes (Flutter's CLI reports MiB where 1 MiB = 1,048,576 bytes). These are APK file sizes, not Android installed storage, memory use or Play Store download estimates.

| Artifact | Bytes | Decimal MB | Binary MiB |
| --- | ---: | ---: | ---: |
| Original universal debug APK | 347,509,377 | 347.51 | 331.41 |
| ARM64 release after asset cleanup, before voice migration | 151,739,693 | 151.74 | 144.71 |
| Previous Moonshine + video ARM64 release | 136,538,354 | 136.54 | 130.21 |
| **Current Procedural Cloud + Cloud Voice ARM64 release** | **18,425,011** | **18.43** | **17.57** |

The current release APK is **86.5% smaller** (**-118.11 MB**) than the previous 136.54 MB release and **94.7% smaller** than the original debug APK:
- Replacing the 8 dark-mode `.mp4` videos, 8 light-mode `.webp` animations, and 8 poster images with the procedural volumetric `_NaviCloudPainter` (`lib/core/widgets/navi_companion.dart`) eliminated **62.18 MB** of bundled character media and the `video_player` native plugin.
- Replacing bundled offline Moonshine/Sherpa model weights and ONNX runtime libraries (`ai.moonshine:moonshine-voice` + `microwakeword`) with the Push-to-Talk cloud pipeline (`GroqSpeechEngine` + `DeepSeekVoiceAgent`) eliminated **36.64 MB** of model assets and **18.27 MB** of native C++/ONNX binaries.

## Current ZIP contents

| Category | Compressed ZIP MB | Raw MB | Files |
| --- | ---: | ---: | ---: |
| ARM64 native libraries (`libflutter.so`, `libapp.so`, etc.) | 17.49 | 17.49 | 4 |
| Other entries (DEX, Android resources, manifest) | 0.77 | 1.42 | 357 |
| Font (`Syne-Variable.ttf`) | 0.08 | 0.15 | 1 |
| ZIP container overhead | 0.09 | — | — |

## Verification and reproduction

```powershell
flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub
python tools/audit_apk_size.py build/app/outputs/flutter-apk/app-arm64-v8a-release.apk --json build/cloud-apk-size.json
```

Artifact: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (`17.6 MB` reported by Flutter CLI / `18.43 MB` decimal).
