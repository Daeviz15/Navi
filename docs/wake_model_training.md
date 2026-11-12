# Navi wake model training

The agreed pronunciation is **NAH-vee**, rhyming with savvy. The runtime is
integrated, but there is currently **no trained Navi microWakeWord model in the
repository**. The standard build now uses Moonshine Tiny Streaming English for both
greeting detection and command transcription. The native microWakeWord engine
is an optional future low-power path, not the active detector. Enabling the candidate native engine without a
model reports a missing-model error; it never silently detects a different word.

## Required artifact

Train streaming int8 microWakeWord v2 models for `Hey Navi` and `Hi Navi`.
The source training framework is [OHF-Voice/micro-wake-word](https://github.com/OHF-Voice/micro-wake-word).
Its maintainers explicitly warn that the starter notebook typically does not
produce a usable model without substantial training and evaluation work.

The framework's Apache-2.0 license does not grant rights to arbitrary training
datasets, synthetic voices or third-party model weights. Use a documented,
commercially compatible training corpus. Community hosted model generators
have their own terms and are not automatically free for product distribution.

Use varied, consented positive recordings and synthetic examples with correct
NAH-vee pronunciation, plus unrelated speech, similar names, TV/music, street
noise, silence, and synthetic voices as negatives. Personal recordings should
include normal and quiet speech at realistic phone distances. A handful of one
person's recordings helps establish evaluation cases, but is not a complete
training corpus for an accent-robust public product.

Split training and evaluation by speaker/session. Keep the actual owner's phone
recordings out of training when measuring generalization. Evaluate both misses
and false wakes on continuous negative audio; isolated positive WAVs alone are
not sufficient. Do not choose thresholds using the final holdout set.

Recommended initial collection for diagnosis: five normal-speed `Hey Navi`
recordings and five `Hi Navi` recordings, one phrase per file with brief quiet
audio before/after. These are voluntary samples for model development, not
audio collected automatically by the app. Do not include private conversation.

## Installation and native testing

Export each trained model as a `.tflite` file and its microWakeWord v2 JSON with
`wake_word`, local `model` filename, and `micro.feature_step_size`,
`micro.probability_cutoff`, `micro.sliding_window_size`. Native model loading
validates the flatbuffer, operators, input shape and type. The current pinned
runtime uses a fixed 64 KB tensor arena; larger models require runtime sizing
work before they can load. Preserve the model's license and training run ID.

```powershell
python tools/install_wake_model.py path/to/hey_navi.json --license path/to/LICENSE.model --provenance "dataset and training run identifier"
python tools/install_wake_model.py path/to/hi_navi.json --license path/to/LICENSE.model --provenance "dataset and training run identifier"
flutter run --dart-define=NAVI_MICRO_WAKE_WORD=true --dart-define=NAVI_VOICE_DIAGNOSTICS=true
```

The importer checks metadata, file identity, size, settings and hashes. It does
not prove that a model actually detects its claimed phrase. It always labels
the result a candidate, pending real recognition measurements.

Test cold/warm startup, greetings spoken immediately after readiness, one-breath
destination requests, silence, TV/music, quiet/far speech, negative similar
names, theme changes, permission denial, calls, background, disable and retry.
Record tap-to-ready and wake-to-listening latency, misses per utterance, false
wakes per hour, CPU and battery. Diagnostics log levels/clipping and timings,
not recordings or transcripts. No emulator or microphone access is required to
build the runtime; actual acceptance uses the owner's phone.

## Current trial and optional low-power path

The default build now uses one Moonshine streaming model for greetings and
commands, preserving the same native stream across wake acceptance. This does
not require a custom wake model. The earlier staged handoff controller remains
available for the optional microWakeWord experiment: it buffers three seconds
of pre-roll and up to thirteen seconds total while command ASR prepares.
Its command engine is now Moonshine as well, not the archived Sherpa model.

Speech output remains installed offline Android TTS. No cloud service, account
or paid API is added. The owner has authorized paid speech as a fallback if the
local phone trial fails; see [the current decision](offline_voice_plan.md).
