# NAVI — Meshy Head/Bust LOD Test (19 October 2026)

## What this contains

Three replacement project files and one optional alternative GLB for existing Navi:

- `assets/models/navi_bust_balanced.glb` — approximately 47,514 triangles, 1.58 MB, **experimental vertex clustering**.
- `assets/models/navi_bust_lite.glb` — approximately 27,461 triangles, 1.09 MB, **experimental vertex clustering**.
- `lib/features/character/presentation/character_lab_screen.dart` — selectable previews: Balanced, Lite, original Motion demo. Preserves current 3D view and touch rotation.
- `pubspec.yaml` — adds both new GLB assets alongside existing models.

Only the original user-provided source has ~227,120 triangles and ~11.9 MB; both derived versions use 1024px compressed textures instead of 2048px. The original was **not** changed. Both derived GLB files have been parsed using Python trimesh. Neither was built/run in Flutter in this environment.

## Critical animation distinction

The Meshy model is a **single static mesh** and has **no skeleton, facial blendshapes, separated movable eyeballs, jaw or braids, and no animation clips**. It can be rotated in a 3D viewer as an object, but it cannot realistically blink, speak, or move hair until a rigged/rebuilt version is made.

The existing tiny 3D animation prototype with `Idle`, `Wave`, `Listen`, and `Nod` is **preserved**. Switch to **Motion demo** in the Character Lab to test those clips. The realistic Meshy previews offer touch rotation and tap acknowledgment only; they do not pretend to have animations.

## Install without losing project work

Extract and copy the two GLB files to `assets/models/`, replace the character screen at `lib/features/character/presentation/character_lab_screen.dart` and replace or manually merge `pubspec.yaml` with the supplied version. Your other Flutter files remain unchanged. This release builds on the prior **NAVI_3D_Interaction_Test_Only.zip** project; retain the existing `assets/models/navi_interaction_test.glb` and required Android WebView settings.

Then run from your project root:

```
flutter pub get
flutter analyze
flutter run --profile
```

If you have additional custom dependencies in `pubspec.yaml`, **merge rather than overwrite**. The supplied pubspec is based on the last shared Character Lab package, not a read of your current Windows project.

## Check on TECNO KI7

1. Open Character Lab, **Balanced**. Note if she looks recognizable, detailed, and correctly textured. Drag to rotate. Check front, profile and back.
2. Switch to **Lite**. Check the face, braids, eyes and ears for visual errors/holes. Note if rendering feels faster.
3. Switch to **Motion demo**. Confirm Wave, Listen and Nod still work.
4. Exit Character Lab and verify that GPS/app UI is not degraded or left constantly rendering.
5. Send a screenshot of Balanced and Lite, plus performance observations.

**Quality risk:** The experimental geometry reduction may introduce holes, stretched triangles or blurry/misaligned texture seams, especially on hair and eyes. These GLBs are strictly prototypes; **do not use as release-ready art without visual inspection**. If either model is visually damaged, stop and revert to the original model while arranging proper retopology.

## Next stage for blinking and speaking

To animate the face, we need riggable geometry and facial controls. In Blender or another DCC tool, separate/retopologize eyelid and mouth loops and add `BlinkLeft`, `BlinkRight`, `JawOpen`, `Smile` morph targets (or rig a jaw and eyelids); bone-rig the head and a few braid clumps. Export glTF 2.0/GLB with tested morph target/skin animation support. The existing Flutter viewer's support for morph-target control must be verified before implementing live lip sync. Do not assume a static GLB can be animated by simple Flutter commands.

## License

The Meshy generation in screenshots was under CC BY 4.0. Preserve attribution and review the applicable Meshy license and terms before any public release. Original reference and asset remain under their applicable rights.
