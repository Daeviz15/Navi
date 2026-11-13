# Voice response diagnosis and device validation

## Current conversation contract

Navi is the only voice control on Home and the journey map. Tap its character
to begin, and tap it again to stop at any stage, including playback or a pending
network reply. There is no ear toggle, input microphone button, wake-word mode,
or persisted hands-free opt-in in the application.

The Riverpod session stays active between replies until both destination and
purpose are captured. A destination alone, silence, an empty transcript, a spoken
goodbye, or a model's `followUp: false` cannot end it. Once both details are known,
Navi finishes its final confirmation before ending capture. Casual purposes count
without requiring a checklist. An old purpose is not reused to complete a newly
tapped conversation, and the map's selected destination is supplied as context.

Capture is muted during Navi's playback and reopened for the next user turn.
Second-tap cancellation invalidates pending results so they cannot update the
journey, speak later, or enter the model's conversation history. Home and map
use the same accessible `InteractiveNaviCompanion` control and shared state.

Backgrounding ends the active session; returning requires a new tap. Leaving all
Navi surfaces releases capture. Permission, microphone and provider failures are
explicit error states with tap-to-retry recovery. Bounded capture/transcription
deadlines remain in place; there is no idle-silence timer that silently ends a
conversation.

## Why the greeting repeated

The previous cloud conversation path marked wake detection as satisfied so follow-ups did not
need a fresh greeting. The local router labels unrecognized phrases in those
turns as acknowledgments. The production shortcut mistakenly treated that label
as a complete response and returned before calling the language model.

Only explicit greetings, identity questions and thanks use that shortcut now.
Other content reaches destination/purpose handling or the model. If providers
fail, Navi explains the connection failure instead of repeating a greeting.

## Response and recording changes

- Native recorder objects survive normal stop/start between turns. Capture stops
  before full reply playback so Navi does not transcribe its own output.
- Listening is published after the recorder starts and its audio subscription is
  attached. Preparation/transcription/reply states are separate from listening.
- A speech-onset event starts a bounded capture deadline. Up to 32 seconds of PCM are
  retained; a limit violation reports an error rather than submitting a prefix.
- All VAD frames in the first audio packet are counted. A 300 ms pre-roll protects
  speech onset. The existing 750 ms silence endpoint is preserved, so a short
  pause inside a sentence does not force a response.
- Transcription and first-playback timings are available through diagnostics.
  Microphone shutdown and model work can overlap; playback waits for shutdown.
- Model fallbacks share one seven-second reasoning budget. Qwen 3.8 uses
  `reasoning_effort: none` for short voice dialogue, as documented by
  [Groq](https://console.groq.com/docs/model/qwen/qwen3.8-27b).
- The map shows the captured transcript. Use it to distinguish a recognition
  error from a correctly heard request that received the wrong response.

This is still an endpointed STT -> text model -> TTS pipeline. It is not a
full-duplex realtime voice transport. Network delays, provider limits, microphone
hardware and background noise can still affect latency and recognition. No
near-instant response or field accuracy target has been established by unit tests.

## Check on the TECNO phone

Tap-only update validated on 2026-11-12: 110 Flutter tests passed, static analysis
was clean, and the updated debug app was installed and launched on the TECNO KI7.
The native accessibility hierarchy confirmed an idle "Navi, Tap to talk" control,
the visible tap instruction, and no legacy voice buttons on Home. Home and map
tap/start/stop semantics and session completion were covered by injected widget
and controller tests. Real spoken recognition accuracy still needs user testing.

Fully restart after a config change, or rebuild after native Android changes.
Enable content-free diagnostic timings with:

```powershell
flutter run --dart-define=NAVI_VOICE_DIAGNOSTICS=true
```

Record the following for at least 20 turns, in a quiet room and then outdoors:

1. Mic-ready startup milliseconds after tapping or Navi finishing a reply.
2. Whether the first word, soft words and the final word appear in the transcript.
3. A 500 ms mid-sentence pause and a sentence longer than eight seconds.
4. Time from end of speech to transcription and to first reply audio.
5. A natural follow-up without another greeting, including changing destinations.
6. A timeout/offline case: an explicit connection error should replace a greeting.
7. Home-to-map handoff and app background/resume without duplicate capture.

Diagnostics log timing and levels, not raw speech, transcripts or credentials.
Use the resulting distribution and audio-level evidence before tuning the VAD
threshold or endpoint. If the transcript is already wrong, changing the response
model cannot recover words that were never captured reliably.
