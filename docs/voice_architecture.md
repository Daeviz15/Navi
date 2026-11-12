# Foreground local voice

Updated 23 October 2026. The default Android engine is now **Moonshine Tiny
Streaming English**, replacing the Sherpa keyword/command pair for the next
physical-phone trial. This is an integration candidate, not phone acceptance.
The owner has authorized paid speech as a fallback if this local trial fails;
no paid API, key, cloud upload or hosted model is configured in this build.

## Runtime and ownership

`VoiceSessionController` remains a Riverpod notifier. It owns opt-in, permission,
one microphone, phases, command routing, output and lifecycle cleanup.
`MoonshineSpeechEngine` implements the existing `SpeechEngine` boundary;
widgets and the character controller do not depend on a recognizer SDK.

`RecordMicrophone` captures mono PCM16 at 16 kHz in roughly 100 ms chunks.
`NaviMoonshine` receives that same stream through a platform channel and runs
synchronous Moonshine JNI on one dedicated executor. The SDK microphone,
downloader, diarization, spelling, TTS and conversational agent are not used.
One model serves both greeting detection and the command that follows. A wake
changes Dart policy to listening without resetting the native stream or model.

Native Android dependency: `ai.moonshine:moonshine-voice:0.1.5`, pinned in Gradle.
It requires Android 8/API 26, reflected in `minSdk`. R8 keeps JNI classes/fields.
The three SDK ARM64 libraries' ELF LOAD segments were checked for 16 KB alignment.
This does not replace physical-device testing or store compatibility validation.

The shipping Flutter dependency and asset list no longer include Sherpa. Both
SDKs supply `libonnxruntime.so`; selecting an arbitrary duplicate with `pickFirst`
is not safe. Previous Dart implementations/benchmarks are preserved as source
snapshots in `archive/voice_sherpa/`. Original model assets/preparation scripts
remain in the repository, outside the shipping asset bundle.

## Greeting and endpoint policy

`StreamingGreetingPolicy` accepts Hi/Hey/Hello followed by bounded Navi/Navy
spelling variants at the start of a speech segment. Two agreeing partial
results or one final result accept the greeting. No edit-distance or substring
search is used. An explicit measured joined spelling, Hainavi, is normalized
as Hi Navi; joined HiNavi/HeyNavi are also supported. This does not change the
owner's agreed **NAH-vee** pronunciation. Similar names and quoted greetings
remain negative evaluation cases; no recognizer can infer intent perfectly.

The wake event immediately selects the held listening expression. Native VAD
can split a greeting and its command into separate segments. The policy joins
those segments and waits for **650 ms of additional processed audio** after a
completed segment plus a fresh quiet VAD result. New active speech, including an
empty line whose words are not decoded yet, cancels that endpoint. A wall-clock
timer must not fire while captured command audio is queued for inference.
The router handles recognized punctuation such as 'Hey, Navi, Take me to London.'

Native segments are capped at 12 seconds. The controller separately bounds a
wake turn to 14 seconds and follow-ups to eight seconds. Known commands require
an explicit instruction before filling the destination field. Recognition does
not geocode, verify a place or start navigation. The destination needs review.

## Resource and cancellation bounds

The Dart bridge allows one process request in flight and a 96 KB/three-second
queued PCM backlog. Each platform message is at most 64 KB. Overflow fails
visibly rather than silently dropping speech. Session/epoch guards reject late
results after mode changes, disable, navigation or backgrounding.

Native transcription checks for updates at a 250 ms floor, adapting to the
last inference cost up to 2.5 seconds. Slow devices can therefore be less
responsive; log inference and queue delay to measure this. Models load and
inference runs off the Flutter UI thread.

The native transcript stream retires at a quiet boundary after 45 seconds.
After 90 seconds, the Dart bridge can rotate an armed stream with three seconds
of native PCM context replay, bounding accumulated history during continuous
background speech. Rotation is decided after checking the current result and
never resets an accepted greeting/active command. Odd PCM bytes are preserved
across rotation. The ring is in memory only; no audio file is written.

`PreparedSpeechPool` warms a muted model on home without opening a microphone,
leases it exclusively, and retires an unused instance after 45 seconds. Leaving
home or backgrounding releases capture and retires the model when released.
After permission, the controller's ten-second startup deadline exposes recovery
rather than an indefinite preparing state. This bounds waiting, not device
load time. TTS initialization does not block recognition readiness.

## Speech output and character

Speech output is still the installed offline Android English TTS voice. It has
not been replaced with a human recording, neural TTS or LLM. Greeting-only turns
receive a local scripted reply after endpointing. The microphone stops before
output, and speaking animation follows the actual utterance-start callback.
Full duplex/barge-in and acoustic echo cancellation have not been validated.

The character rests still, with one optional gesture after 90-150 seconds of
inactivity. Listening uses the held expression until the actual voice phase
ends. Generic speaking movement is not phoneme lip sync. See
[character rendering](companion_rendering.md).

## Assets and privacy

`assets/voice/moonshine_tiny_en/manifest.json` pins eight Tiny Streaming English
files, dated `quantized_26_08_21`, by size/SHA-256. The import was also checked
against upstream catalog CRC32C values. `tools/prepare_moonshine_model.py`
restores only those pinned files. Upstream provenance and MIT/third-party
notices are bundled. Native code loads verified private staged files through
`VoiceModelAssets`; cache hashing runs off the UI isolate and corruption is
repaired from bundled assets. No runtime network download is called.

The app persists its enabled preference and verified model files. It does not
persist or upload microphone audio, transcripts or replies. Optional
`NAVI_VOICE_DIAGNOSTICS=true` logs timing, queue delay and microphone levels,
without speech content. Explicit developer WAV tools export synthetic fixture
transcripts for regression evaluation; they do not open a microphone.

## Validation and next acceptance

The final implementation passed 71 Flutter tests, static analysis and the
ARM64 release build (136.54 decimal MB). Model hashes and runtime provenance
were checked in the APK. No phone installation or microphone test was performed.

Run `flutter analyze --no-pub`, `flutter test --no-pub` and an ARM64 release build.
Tests cover bounded queues, stale native replies, turn assembly, pause checks,
window rotation, greeting boundaries, negations, model repair, permissions,
lifecycle, output events and character presentation.

For actual local inference without a microphone, use an isolated Python
environment with `moonshine-voice==0.1.5` and run
`tools/validate_moonshine_voice.py` on explicit mono PCM16/16 kHz WAV files.
Then replay the exported native segments with
`dart --packages=.dart_tool/package_config.json tools/replay_moonshine_transcripts.dart`.
The optional `-ExplicitNaviPronunciation` switch on
`tools/create_voice_test_audio.ps1` synthesizes IPA NAH-vee fixtures.

The initial two synthetic pronunciation sets produced accepted greetings and
complete turns for all ten positive fixture runs, with no activations in four
negative runs (two repeated negative phrases). These use one synthetic voice,
not ten speakers. The model returned Hainavi in one NAH-vee greeting, motivating
the explicit alias. One default-pronunciation Lagos request became 'logos';
three of four destination fixtures had the intended place spelling. These
results do not establish accent robustness, a false-wake rate, phone latency,
phone microphone behavior or battery performance.

Use a full native restart/release build on the owner's TECNO. Test first-attempt
Hi/Hey/Hello Navi, greeting-only pauses, one-breath requests, quiet/distance,
television/street noise, airplane mode, cold/warm enable, background/lock,
permission denial, calls, output and rapid disable/retry. Record readiness,
misses, false wakes/hour, queue lag, destination errors, CPU/RAM/battery and
animation frame timing. See [trial and fallback decision](offline_voice_plan.md).
