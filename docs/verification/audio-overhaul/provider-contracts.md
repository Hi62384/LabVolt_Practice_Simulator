# OpenAI voice contracts — verified 2026-11-27

These contracts were checked against official documentation during the audio overhaul. Protocol fixtures test our transport and gameplay boundaries; they do not establish audible voice quality or account access.

## Separate provider routes

| Capability | Models / route | Voice compatibility |
| --- | --- | --- |
| Authoritative text rendered as speech | `gpt-realtime-2.1-mini`, `gpt-realtime-2.1`; WebSocket `/v1/realtime?model=…` | Ten documented presets or consented recording voices |
| Full duplex / prompt-generated voices | `gpt-live-1.1`, `gpt-live-1`; WebSocket `/v1/live/sessions` with no query | Live presets, prompt voices, or consented recording voices |
| File transcription | `gpt-transcribe`; multipart `/v1/audio/transcriptions` | Completed mono WAV input in the game |
| Existing speech compatibility | `gpt-4o-mini-tts`, `tts-1`, `tts-1-hd`; `/v1/audio/speech` | Model-specific presets; mini-TTS supports recording voices |
| Permanent voice creation | JSON `POST /v1/audio/voices`, `type: prompt` | Returned voice ID is reusable only with Live |

A model name is never substituted across endpoints. Preset and permanent custom identities are never changed because a request fails. An unknown model remains unverified. The account's model list is separate from documented lifecycle/capability metadata.

Sources: [audio overview](https://developers.openai.com/api/docs/guides/audio), [Realtime 2.1 Mini](https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini), [Realtime 2.1](https://developers.openai.com/api/docs/models/gpt-realtime-2.1), [GPT-Live 1.1](https://developers.openai.com/api/docs/models/gpt-live-1.1), [transcription](https://developers.openai.com/api/docs/guides/speech-to-text), [speech API](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create).

## Creation, allocation, and approval

Prompt creation takes `name` (1–256 characters), nonblank `prompt` (up to 2,000 characters), `model: auto`, and optional representative `script_hint` (up to 2,000 characters). It returns metadata and a saved `voice_…` ID, **not preview audio**. Auditions require a billed Live session. Prompt creation is free. Voice descriptions must describe original adult vocal qualities rather than imitate named people.

The documented organization limits are 100 prompt voices and 20 recording voices. The public Voices reference documents create and delete, not a list/quota endpoint. Our local allocation count cannot know voices created elsewhere; the studio exposes externally reserved capacity and reports capacity failures. It does not auto-delete voices. An ambiguous creation timeout is not retried automatically because the service may already have allocated the voice. Candidates require explicit host approval and do not overwrite established profiles during audition.

Sources: [custom voices](https://developers.openai.com/api/docs/guides/custom-voices), [create voice](https://developers.openai.com/api/reference/resources/audio/subresources/voices/methods/create), [Voices resource](https://developers.openai.com/api/reference/python/resources/audio/subresources/voices).

## Live protocol and authority

The first WebSocket event is `session.start`; wait for `session.started`. Raw mono PCM16LE travels in base64 `session.input_audio.append.audio` and `session.output_audio.delta.delta`. Fixed-line rendering uses 24 kHz; the gameplay microphone bridge uses documented 16 kHz PCM in both directions, matching the shared microphone without a second resampler. Live also documents 8 kHz G.711. The selected format and voice cannot change mid-session.

Client delegation emits `session.delegation.created` with an ID and timestamp, **without the player's utterance**. The host accumulates `session.input_transcript.delta` and `session.output_transcript.delta` with their timestamps and passes history to the existing character reasoning system. IDs prevent duplicate execution and reject stale results after interruption. All game actions, memory, relationships and educational facts remain game-owned.

`session.commentary.append` may paraphrase. Exact game dialogue uses a trusted `session.instructions.append`, plus a local transcript gate: no unvalidated audio reaches the player. For speech rendering, Realtime completion supplies a definitive response boundary; Live has no audio-done event, so the adapter waits for a quiet output segment and a stable matching transcript. Mismatched or missing transcripts fail to text instead of playing a different claim. This conservative buffering adds latency and must be evaluated with real voices. The transcript gate checks textual agreement; it does not prove every acoustic sample is pronounced correctly.

Live append content is capped at 500 tokens. The adapter bounds each append to 480 UTF-8 bytes, including non-English text, and stages long authoritative dialogue in numbered literal blocks before one final performance instruction. It never truncates technical content to fit the cap. The entire returned transcript must match the original complete line. GPT-Live 1 uses its documented `<|SpawnThinking|>` delegation marker; 1.1 uses the current delegation instruction.

The final text passes through the shared phrase-delivery helper before a real synthesis request. Realtime/fixed-line sessions receive its complete instructions; ongoing Live conversations refresh the current identity, emotional mixture, projection and phrase guidance with bounded instruction appends before performing the authoritative line. These controls are delivery directions, not additional character reasoning or independently rendered sentence clips. The game does not pitch-shift a preset to claim a different permanent identity.

Live input and output transcript fragments are not complete turns. Primary output audio has no timestamps. The app owns playback queues, interruptions and completion. Muting input does not stop generated output. Local playback must also be stopped. Model instructions alone are not a permission or action boundary.

Live `usage.seconds` snapshots are cumulative. `session.close` is followed by `session.closed` with final usage; a transport close without that event is marked unconfirmed. Gameplay maintains at most three active host-owned conversations, reuses a player's same-character session, and closes after three minutes of inactivity, opt-out, private calls, leaving range, or disconnection. Changing an immutable voice or target closes the previous session. Synthetic silence advances the timeline when microphone input ends; it contains no player audio. The app does not claim WebRTC standby billing for idle WebSockets.

Sources: [primary WebSocket reference](https://developers.openai.com/api/reference/resources/live/primary-websocket), [WebSocket guide](https://developers.openai.com/api/docs/guides/voice-websockets), [Live sessions](https://developers.openai.com/api/docs/guides/live-conversations), [delegation](https://developers.openai.com/api/docs/guides/live-delegation), [prompting](https://developers.openai.com/api/docs/guides/live-prompting), [playback controls](https://developers.openai.com/api/docs/guides/voice-server-controls).

## Lifecycle and cost

| Model family | Announced shutdown | Migration |
| --- | --- | --- |
| `tts-1`, `tts-1-hd`, `gpt-4o-mini-tts` and listed snapshots | 2027-01-06 | `gpt-realtime-2.1-mini` via a different API workflow |
| `gpt-realtime`, `gpt-realtime-mini` and listed snapshots | 2027-01-20 | Corresponding 2.1 models |
| `gpt-4o-mini-transcribe-2025-03-20` | 2027-01-20 | Later snapshot or current transcription workflow |
| `whisper-1`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, diarize | 2027-02-26 | `gpt-transcribe` or `gpt-live-transcribe` |

Deprecated selections remain selectable until shutdown; saved choices are preserved. Retired or incompatible requests are rejected with a compatible migration suggestion. New installations use `gpt-realtime-2.1-mini` and `gpt-transcribe` defaults; existing selections are not silently changed.

Live active sessions cost $0.05/minute, with backend usage separate. Realtime billing distinguishes audio and text tokens; unknown or incomplete modality splits do not produce fabricated cost estimates. The recorded request totals include usage even when a generated response is withheld for transcript mismatch. Prices and lifecycle dates are a documented snapshot, not a live billing balance.

Sources: [deprecations](https://developers.openai.com/api/docs/deprecations), [Live pricing](https://developers.openai.com/api/docs/models/gpt-live-1.1), [Realtime Mini pricing](https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini), [Realtime usage events](https://developers.openai.com/api/reference/resources/realtime/server-events).

## Reproducible verification

Run `python tests/campus/ai/run_voice_provider_tests.py --godot /path/to/godot`.

The runner launches an HTTP/WebSocket fixture and Godot inside the same network namespace, removes any real API key from the test process, and uses temporary Godot user data. It checks protocol routing, prompt creation, exact transcript gating, missing transcripts, cancellation, rate limits, concurrent speech/text/transcription lanes, long transcription, client delegation, duplicate events, interruption, and cumulative usage. A second test runs singleplayer and two actual ENet peers through the gameplay bridge, checking host-only credentials, ordered turn/PCM RPCs, 16 kHz output, permission changes, session reuse and canceled backend completion. It is not a listening test or a real microphone acceptance test.

### Recorded local results, 2026-11-27

| Command | Result |
| --- | --- |
| `python tests/campus/ai/run_voice_provider_tests.py --godot /opt/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64` | `VOICE_PROVIDER_PROTOCOL PASS`, `NPC_LIVE_BRIDGE PASS`. Includes multilingual append limits, credential change during active/queued speech, account-catalog isolation and real ENet routing. |
| Same runner with Godot 4.5.1 Mono | Both protocol and bridge suites passed on the game's Mono runtime. |
| `python tests/campus/ai/run_character_http_tests.py --godot /opt/godot/4.7.2/Godot_v4.7.2-stable_linux.x86_64 --output /tmp/labvolt-audio-http-regression` | Host client, teacher AI, evaluation, and actual character HTTP transport all passed; no script errors. |
| `godot --headless --path . --script tests/campus/academics/test_character_interaction_pipeline.gd` with a temporary `XDG_DATA_HOME` and no `OPENAI_API_KEY` | `CHARACTER_PIPELINE PASS checks=46 failures=0`; includes the busy-lane regression. |

The standalone Linux protocol runs report that the repository's optional CEF extension has no Linux binary in this checkout; the voice scripts themselves load and all assertions pass. Game/menu startup verification is tracked separately by the integration owner. The fixture observes zero active WebSockets after cleanup. Its peak can include a socket completing graceful cancellation while the next bounded request starts.

No real account capability check, billable custom-voice creation, listening audition, room acoustics test, or physical microphone/device-change test was performed during these fixture runs. Preset and candidate audition status must remain honest until the host completes the studio auditions on a configured account. A text transcript gate cannot establish subjective vocal identity, emotional performance quality, or acoustic correctness.
