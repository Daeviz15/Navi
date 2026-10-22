# Navi

A Flutter travel companion with a compact Syne typeface, muted golden-yellow accents, solid black surfaces by default, and a warm light theme.

## Run

```sh
flutter pub get
flutter run
```

Restart the app after pulling changes to native plugins or bundled assets. The current platform project is Android; the official video player supports Android, iOS, macOS, and web, rather than Windows desktop.

## Current experience

- The home screen centers a looping, muted preview of `assets/videos/idle/idle_01_sip.mp4`.
- The top-right appearance control switches between dark and light modes. The preference lasts for the current app session.
- The character animates without visible playback controls, pauses while the app is in the background, and respects reduced-motion settings. A bundled still frame is used while loading or when playback is unavailable.
- Light mode uses a transparent animated WebP derived from the same source clip, so Navi blends into the page. A border-connected background matte preserves enclosed dark details. The original MP4 is used in dark mode.
- The home wordmark and appearance control stay fixed while the page scrolls.
- Destination entry, suggested places, purpose selection, and travel-mode selection are interactive. Live navigation and microphone input are still pending.
- The legacy character lab, GLB benchmark, and performance meter are commented out. Their original source and model files remain available for reference; the 3D dependency and model asset registrations are commented out in `pubspec.yaml`.

## Assets

Only the home preview clip is bundled at present. The broader animation-selection system has not been added. See `assets/videos/README.md` for the earlier clip audit and naming history.

`tools/prepare_navi_matte.ps1` regenerates the light-mode animation and transparent poster from the source MP4 using FFmpeg. The derivative has 240 frames at 540 × 960 and 24 fps; the original clip is preserved. Matting is approximate at very dark exterior edges, so future clips should be reviewed against both themes.

Syne is bundled in `assets/fonts/` for offline use. Its SIL Open Font License is included alongside the font. Source: https://github.com/google/fonts/tree/main/ofl/syne.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --debug
```

Widget tests cover the destination flow, theme switching, larger text on a narrow screen with an open keyboard, and video playback lifecycle using a fake video platform. Native video decoding needs a device or emulator.
