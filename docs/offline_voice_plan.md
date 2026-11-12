# Local voice trial and paid fallback

Owner decisions, 23 October 2026: try the free, fully local recognizer next.
If it still fails on the phone, proceed with paid speech services once the
owner supplies credentials. This supersedes zero API fees as an unconditional
long-term restriction. **No paid service or cloud upload is enabled now.**

## Implemented for this trial

The default Android build now uses **Moonshine Tiny Streaming English** for
both greetings and subsequent commands, through one microphone and one native
model. The eight checksum-pinned model files are bundled and run offline.
The former Sherpa package/models are excluded from shipping; source snapshots
are preserved. The microWakeWord integration remains an optional future
low-power path, but still has no trained Navi model and is not the default.

The engine accepts Hi/Hey/Hello Navi/Navy, including narrowly defined joined
spellings observed in testing, and immediately selects the listening expression
when the greeting is accepted. A 650 ms audio-time endpoint grace joins native
segments so a continuing request is not cut off by a greeting reply. Native
history and audio queues are bounded. See [architecture](voice_architecture.md).

This changes recognition, not the spoken voice. Output remains offline Android
TTS with scripted local replies. Human-recorded acknowledgments and a neural
TTS voice have not been installed. They are separate work from hearing Navi's
name. Do not promise ChatGPT voice quality from this recognizer change.

## Physical-phone decision

Install/run the new ARM64 release build with a full restart, not hot reload.
Enable the ear icon and wait for the ready caption. In a quiet room, say each
of Hi Navi, Hello Navi and Hey Navi naturally, once per completed test turn.
Try a greeting alone and 'Hey Navi, take me to Lekki' in one breath. After a
spoken prompt, give a destination without repeating the wake. Check airplane
mode, disable, background/return, and a fresh/cold launch.

The immediate check is whether the owner can call Navi reliably without five
to ten repetitions and without a long startup. Do not keep lowering thresholds
or asking for repeated retesting indefinitely if the practical trial still fails.
The initial synthetic checks are regression evidence, not phone acceptance.

For broader release, measure multiple Nigerian speakers, noise, distance,
negative similar names, location accuracy, p95 response timing, power, RAM and
thermal behavior. Proposed targets remain 95% first-attempt quiet greeting
success, warm ready under two seconds, cold ready within five seconds after
permission/model availability, and listening feedback within 250 ms of detector
acceptance. These are goals, not measured results or guarantees. Phrase-end to
recognition delay must be measured separately. Known local-place errors still
require destination review.

## If the local trial fails

Use a paid speech recognition or realtime voice service, with explicit audio
handling and a server-side credential boundary. An LLM alone does not replace
speech recognition or a wake detector. Choose the provider/model against the
failed phone recordings/metrics and agreed response-quality target at that time.

Keep long-lived API keys out of Flutter source, assets, git and the APK. A
backend should hold the key and issue supported short-lived client sessions,
with usage limits and clear microphone/session controls. Request credentials
through the appropriate secure setup when implementing that fallback; do not
paste a production key into this chat. The current speech interfaces and
Riverpod controller allow a backend adapter without rewriting character logic.

## Later local efficiency/voice options

If the local trial succeeds, profile foreground streaming ASR before enabling
broader hands-free behavior. A trained microWakeWord model may reduce the cost
of waiting for a greeting; it still needs licensed data and phone validation.
See [wake model work](wake_model_training.md).

Short, locally stored human greetings can improve known replies without API
fees. Check recording rights and personality consistency. Arbitrary natural
speech needs separately evaluated offline neural TTS or the chosen paid voice
service. Avoid playing acknowledgments over a continuing command before echo
cancellation and interruption handling are implemented.

Primary references:
- [Moonshine models](https://moonshine-voice.readthedocs.io/en/stable/models/available-models/)
- [Android SDK](https://moonshine-voice.readthedocs.io/en/stable/quickstart/)
- [Model/runtime licenses](https://moonshine-voice.readthedocs.io/en/stable/license/)
