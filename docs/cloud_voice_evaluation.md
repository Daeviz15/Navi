# Cloud voice evaluation for Navi

Research date: 28 October 2026. This is a recommendation and evaluation plan,
not a completed provider trial or a change to the active local voice engine.
No account-specific credits, API availability or phone performance were verified.

## Recommendation

Move the next conversation prototype to hosted speech-to-speech. Use OpenAI
GPT-Live 1 as the first paid conversational baseline, and compare Grok Voice 3.0
on the same physical-phone cases before choosing a production provider. If a
free API trial is the priority, Gemini 3.8 Live has an explicitly documented
free tier and is the alternative to test first. Do not choose a provider on an
unverified promise of recurring credits or assume the most natural voice also
recognizes NAH-vee best on the TECNO.

Today's app does not contain an LLM. Moonshine is an offline speech recognizer.
Replies come from `LocalCommandRouter`'s fixed intents and Android offline TTS.
Changing the response text alone cannot provide open-ended reasoning, a natural
neural voice, reliable interruption handling or conversation memory.

## Current official options

| Option | Fit | Published pricing |
| --- | --- | --- |
| OpenAI `gpt-live-1` | Full-duplex conversation while a separate backend reasons and uses tools | $0.05/session minute, billed per second; backend model/tool usage extra. Free tier unsupported. |
| xAI `grok-voice-3.0` | Native speech-to-speech with function calls | $0.08/minute plus $0.004 per applicable text-input event; default server-VAD sessions billed by session duration. |
| Google `gemini-3.8-live` | Live audio conversation; candidate for a free development trial | Limited free tier. Paid audio input $3/M tokens and output $12/M tokens, with text/tool costs as applicable. |

OpenAI's current audio guide recommends GPT-Live for new conversational apps.
It delegates complex reasoning/tool work to a backend; the $0.05 rate is not
an all-inclusive intelligence price. If explicit turn/response control is
needed for activation and playback, the Realtime API is another documented
path: `gpt-realtime-2.1-mini` lists $10/M input audio tokens and $20/M output
audio tokens, plus text/tool usage. These token rates are not directly
comparable to session-minute prices without representative usage measurements.

Sources:
- [OpenAI audio workflow selection](https://developers.openai.com/api/docs/guides/audio)
- [GPT-Live capabilities and price](https://developers.openai.com/api/docs/models/gpt-live-1)
- [GPT-Live/backend responsibilities](https://developers.openai.com/api/docs/guides/live)
- [OpenAI Realtime Mini](https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini)
- [xAI voice model selection](https://docs.x.ai/developers/model-capabilities/audio/speech-to-speech)
- [xAI voice billing](https://docs.x.ai/developers/models/speech-to-speech)
- [Gemini pricing and free-tier data use](https://ai.google.dev/gemini-api/docs/pricing)
- [Gemini Live capabilities](https://ai.google.dev/gemini-api/docs/live-api)

## xAI free-credit claim

The widely cited $25/month offer was explicitly a public-beta promotion through
the end of **2024**, not a verified current recurring allowance. Current billing
documentation describes prepaid credit and optional invoiced billing. The
enterprise FAQ says conditional credits may sometimes be offered in exchange
for allowing training on business data; it does not promise a universal grant.
Check the actual account's balance, eligibility, expiry and voice applicability.
Free access to the consumer Grok app does not establish free API voice usage.

- [Dated 2024 beta announcement](https://x.ai/news/api)
- [Current API billing](https://docs.x.ai/console/billing)
- [Conditional credits/data use](https://x.ai/legal/faq-enterprise)

Gemini's published free-tier table says data is used to improve products; the
paid-tier column says it is not. Use the free tier for deliberate development
samples, and review the applicable data terms before public-user testing.
Free-tier quotas/account access must be checked; free is not unlimited capacity.

## Activation and character design

Putting an LLM behind the existing local wake gate would leave missed wakes
unchanged. For the first controlled cloud trial, connect voice when the user
explicitly enables hands-free on the foreground home screen, before they say
Hi/Hey/Hello Navi. Make online microphone use visible, bound session duration,
and release capture/session on disable, background and screen departure.
Provider turn events, transcript/activation policy and actual playback events
must be mapped deliberately to Navi's listening/thinking/speaking states.
Prompt instructions alone are not authorization to run navigation tools.

This trial exchanges local inference/storage for network dependence, latency
and metered listening time. GPT-Live includes silence and backend work in active
session time; default xAI server-VAD sessions also charge session duration.
Do not leave a paid session waiting throughout a journey without measuring the
cost. A later production design can use a validated small dedicated wake model
to open cloud conversations, replacing full Moonshine transcription while idle.
That model is not trained or installed today.

Store long-lived credentials on a backend. Use provider-supported session
handshakes or short-lived client credentials. Keep microphone ownership singular,
support cancellation and audio-focus changes, and coordinate echo cancellation
and playback interruption before claiming full-duplex behavior in Flutter.
An API capability does not make the current app's audio pipeline full duplex.

Give Navi concise personality instructions (relaxed, warm, lightly playful),
relevant conversation context, and tools for real place lookup/routes. Do not
let the model invent traffic, journey duration, fares or route availability.
Changing destination text and starting navigation remain distinct app actions.

- [OpenAI duration billing](https://developers.openai.com/api/docs/guides/voice-latency-cost)
- [xAI ephemeral client credentials](https://docs.x.ai/developers/model-capabilities/audio/ephemeral-tokens)

## Size audit

Existing artifacts audited on 28 October: debug APK **249,785,695 bytes**;
23 October ARM64 release APK **136,538,354 bytes**. These are different build
configurations/dates, not installed-size or RAM measurements.

The release's compressed ZIP entries include 46.98 MB of alpha WebP animations,
12.90 MB of MP4 clips, 36.64 MB of model/metadata/notices, and 35.76 MB of native
libraries. Only part of the native library category belongs to speech.
The weight files occupy about 45.2 MB uncompressed and are staged privately;
older caches can also remain after updates. Source videos outside the explicit
asset list do not all ship in the APK.

After cloud voice passes acceptance, remove the unused full offline model and
its native SDK, with a scoped migration for obsolete generated model caches.
Keep character artwork until a smaller rendering representation is visually
validated. Cloud audio transport adds some dependencies, and the app will still
include visual assets; do not promise an unmeasured final APK size or equate a
smaller download with lower RAM use.

## Acceptance and training

Use the same short test script, personality and network for each provider:
first-attempt NAH-vee greetings, one-breath destinations, follow-ups without a
wake, interruptions, local place names, quiet/far speech, TV/street noise,
silence, cold/warm starts, offline/disconnect and lifecycle recovery. Measure
first-audio p50/p95, task success, false activations, confirmed destination
accuracy, actual total API usage/cost, and phone CPU/RAM/battery. Do not declare
a provider best for Nigerian speech from its marketing or synthetic results.

Training an entire language-and-voice stack from scratch is not the next step.
Start with personality prompts, grounded tools and a consistent evaluation set.
Fine-tuning an existing model can be evaluated later if data identifies a
specific repeated failure; hosting/training costs remain. Training a small
dedicated Navi wake detector is a narrower, reasonable longer-term project,
but still needs suitable licensed data and real-phone validation.

Next deliverable: a bounded cloud voice prototype behind the existing voice
interfaces, with backend credential setup, Navi personality and actual audio
playback events driving character state. Provider selection/credentials and
real phone results remain outstanding; none of these services was invoked here.
