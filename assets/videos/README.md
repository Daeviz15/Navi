# Navi video library

Audited on 2026-10-21 against the supplied 27-clip production list. Filenames were matched to behavior using sampled video frames, including a closer inspection of the microdance clip.

## Naming

Use `<behavior>_<two-digit-variant>_<action>.mp4`, matching the IDs in the production list. Keep filenames lowercase and retain the existing category folders. Variant numbers belong to each behavior, rather than the entire folder.

## Completeness

| Category | Expected | Present | Missing |
| --- | ---: | ---: | ---: |
| Idle / nonchalant | 8 | 8 | 0 |
| Active assistant states | 7 | 6 | 1 |
| Personality and emotional reactions | 9 | 4 | 5 |
| Bonus reactions | 3 | 3 | 0 |
| **Total** | **27** | **21** | **6** |

The PNG character reference is not included in the video count.

## Existing clips and rename history

All 21 videos were renamed in place. SHA-256 hashes before and after renaming matched for every file.

| Folder | Filename | Previous filename |
| --- | --- | --- |
| idle | idle_01_sip.mp4 | Navi_drinks_from_cup_20261021161251.mp4 |
| idle | idle_02_crosslegs.mp4 | Navi_sitting_with_smug_smirk_20261021161832.mp4 |
| idle | idle_03_bored_blink.mp4 | Animated_character_waiting_patie…_20261021162010.mp4 |
| idle | idle_04_whistle.mp4 | Navi_taps_foot_looking_upward_20261021162239.mp4 |
| idle | idle_05_stretch.mp4 | NAVI_stretches_and_resets_posture_20261021162437.mp4 |
| idle | idle_06_sideeye.mp4 | Animated_character_giving_side-eye_20261021162634.mp4 |
| idle | idle_07_daydream.mp4 | NAVI_resting_and_gazing_20261021162918.mp4 |
| idle | idle_08_microdance.mp4 | Animated_character_listening_to_…_20261021163555.mp4 |
| assistant | listening_02_curious.mp4 | NAVI_reacting_with_curiosity_20261021191938.mp4 |
| assistant | thinking_01_chin.mp4 | NAVI_thinking_thoughtfully_20261021190622.mp4 |
| assistant | thinking_02_analyzing.mp4 | Animated_character_thinking_and_…_20261021190927.mp4 |
| assistant | speaking_01_explaining.mp4 | Character_explaining_to_viewer_20261021191134.mp4 |
| assistant | speaking_02_excited.mp4 | Animated_character_speaking_sile…_20261021191342.mp4 |
| assistant | speaking_03_serious.mp4 | Animated_character_delivers_sile…_20261021191753.mp4 |
| personality_emotions | happy_01_smile.mp4 | Animated_character_smiling_happily_20261021192748.mp4 |
| personality_emotions | happy_02_celebrate.mp4 | NAVI_performs_victory_fist_pump_20261021192824.mp4 |
| personality_emotions | cry_01_teary.mp4 | Animated_character_crying_and_wi…_20261021192933.mp4 |
| personality_emotions | confused_01_shrug.mp4 | Cartoon_character_shrugs_20261021193001.mp4 |
| bonus_reactions | success_01_gotit.mp4 | Navi_raises_finger_with_solution_20261021194239.mp4 |
| bonus_reactions | error_01_facepalm.mp4 | Character_performs_gentle_facepalm_20261021194302.mp4 |
| bonus_reactions | tired_01_drowsy.mp4 | Animated_character_yawns_and_perks_20261021194433.mp4 |

The ellipsis characters in previous filenames were present in the original filenames.

## Missing clips and original prompts

### assistant/listening_01_attentive.mp4

Target: 4–6 seconds, loop.

NAVI notices someone speaking, subtly straightens up, opens its eyes a little wider, tilts its head toward the viewer, and gives two small responsive nods. Expression attentive but calm. End in listening-ready posture.

### personality_emotions/sad_01_disappointed.mp4

Target: 3–5 seconds, one-shot.

NAVI looks down, eyes soften, brows curl upward at the center and smile fades into a mild, believable frown. It takes a gentle breath and recovers to neutral. Sensitive and restrained, not melodramatic.

### personality_emotions/confused_02_doubletake.mp4

Target: 3–5 seconds, one-shot.

NAVI makes a quick comical double take to the right, blinks twice, pauses with one eyebrow raised and restores its neutral gaze. Do not rotate the entire body or change camera framing.

### personality_emotions/touch_01_surprised.mp4

Target: 2–4 seconds, one-shot.

Someone lightly taps NAVI's forehead from outside frame, but NO additional person or hand should appear. NAVI reacts to the imaginary tap: eyes open suddenly, slight backward lean, quick blink and mild confused glance at the viewer; then returns to neutral.

### personality_emotions/touch_02_annoyed.mp4

Target: 2–4 seconds, one-shot.

NAVI is gently poked again by an invisible touch, narrows its eyes, folds its arms and slowly gives an unimpressed, disapproving side-eye, with comic restraint. Then eases back to idle. No anger or aggression.

### personality_emotions/touch_03_playful.mp4

Target: 2–4 seconds, one-shot.

NAVI reacts to a friendly touch by grinning mischievously, leaning toward the viewer a little and offering a tiny wave. Then returns to the standard resting pose.

## Production observations

- All 21 existing clips report approximately 10.01 seconds, exceeding their requested durations. They are H.264 videos at 720 × 1280, each with an AAC audio stream. The presence of an audio stream does not establish whether it contains audible sound.
- The character in `idle/idle_08_microdance.mp4` has visibly different proportions and a lighter belly than the character in most other clips. Review character consistency before including it in random idle playback.
- Loop labels above describe the requested behavior. Seamless looping and transitions between clips have not been verified by this inventory audit.
- At audit time, `pubspec.yaml` did not register these video folders, and `NaviCompanion` still displayed the existing orb image. No references to the original video filenames were found in project text files.
