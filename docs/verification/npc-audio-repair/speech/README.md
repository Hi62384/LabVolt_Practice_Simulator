# Speech and Character Voices repair verification

Verified on November 27, 2026 (America/Los_Angeles; November 28 UTC) with Godot 4.5.1 Mono and .NET 8.0.408 on Linux. Native screenshots use the real OpenAI Settings window, X11 and Mesa llvmpipe. Provider protocol fixtures also used Godot 4.7.2. All provider traffic in these checks goes to local deterministic fixtures; no OpenAI account was contacted.

## Confirmed cause

`teacher_voice_profiles.gd` inferred a local variable from a dynamically typed dictionary member (`var unresolved := _state.pending_creations.size()`). Godot rejected the script at parse time. Speech delivery and Character Voices both preload that script, so the failure prevented their initialization regardless of the selected provider model. Declaring `unresolved` as an integer restored the dependency chain. This was reproduced before changing the code.

A separate strict transcript comparison rejected harmless spoken numeric forms. The speech-only adapters now compare conservative canonical representations of numbers, signs, common units, case-sensitive SI prefixes, contractions, explicit mathematical operators and mathematical grouping. They still reject changed values, units, operators, negation and added sentences. No fuzzy similarity or model substitution is used. A genuine mismatch is visible as `speech_transcript_mismatch` and uses the existing bounded same-provider retry policy.

## Preserved behavior

The custom voice creation journal, original design, approval, model pin, resource ID and account capacity protections remain. Playback failure does not select another provider, another speaker or Piper. Portable student voices carry the approved permanent identity and origin scope; they exclude audition recordings, per-device hearing claims and request journals. Conflicting approved identities are not overwritten, and receiving an imported resource does not claim that the current API account owns it.

Native Live conversations are retired. Speech-only Live and Realtime renders reject an empty supplied line and expose no microphone streaming path. Startup instructions contain only the authoritative utterance and vocal performance. No conversation history, personality reasoning request or player audio is sent to these temporary rendering sessions.

## Official protocol and lifecycle sources

- [Live primary WebSocket reference](https://developers.openai.com/api/reference/resources/live/primary-websocket): connect to `wss://api.openai.com/v1/live/sessions` without query parameters. Configure the model and output audio in `session.start`; wait for `session.started` before sending input. The application preserves this startup sequence.
- [Managing GPT-Live sessions](https://developers.openai.com/api/docs/guides/live-conversations): immediate speech can be requested by a startup developer input message while silent input frames keep the audio timeline running. The documentation does not guarantee that such a request produces speech or exact wording. This implementation checks returned audio and transcript, then closes the temporary session. Final cumulative `usage.seconds` comes from `session.closed`; a transport timeout leaves final usage unconfirmed. Completion is not inferred solely from a gap in transcript messages.
- [Text-to-speech guide](https://developers.openai.com/api/docs/guides/text-to-speech): `tts-1`, `tts-1-hd` and `gpt-4o-mini-tts` are deprecated but remain operational until January 6, 2027. Their Speech API integration remains selectable. `gpt-realtime-2.1-mini` requires the Realtime API and is not a supported `/v1/audio/speech` model. The older TTS models have a smaller preset voice set, so incompatible saved voices remain explicit errors.
- [GPT-Live 1.1](https://developers.openai.com/api/docs/models/gpt-live-1.1), [GPT-Realtime 2.1 Mini](https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini), [GPT-Audio 1.5](https://developers.openai.com/api/docs/models/gpt-audio-1.5) and [deprecations](https://developers.openai.com/api/docs/deprecations) are the catalog references. Existing catalog routing, pricing and lifecycle records were retained.

## Executed checks

`summary.json` records ten passing native Mono regressions: permanent identity, custom voice recovery, synth adapter, player, scheduling/retry/cancellation, PCM DSP, long speech delivery, Studio approval flow, transcript equivalence/rejection, and portable voice persistence. The transcript suite contains 38 equivalence and rejection cases. The two additional provider logs exercise actual HTTP/WebSocket adapters against local fixtures for Live, Realtime, Audio Chat and legacy Speech API routes. The baseline legacy delivery instructions were also measured across all 21 faculty in three moods; the maximum was 2,886 characters, within the 4,096-character legacy instruction limit.

The native Studio test uses the actual settings popup, no credentials, all 21 faculty and two saved-student fixtures. Opening the roster, filtering and searching by program make zero student dossier hydration calls. Selecting one student loads only that profile. A missing/corrupt selected dossier disables mutations without creating a replacement vocal identity; leaving the selection releases its full profile from the Studio map. It checks roster population, appearance, design, model choices, fixed roster while details scroll, disabled paid actions when offline, readable action widths, and bounds at 720×520. Screenshots were inspected after fixing a FlowContainer minimum-width issue that collapsed action labels.

- `voice-studio-offline-1280.png`: default selection and local information, captured from the 1,060×660 popup inside a 1,280×720 window.
- `voice-studio-auditions-1280.png`: audition and approval controls after scrolling the details pane.
- `voice-studio-student-720.png`: saved-student filter at the smaller popup size.

## Follow-up classroom checks

The independent real-Main seating audit reproduced two navigation defects. Ordinary approach planning treated the student's own chair as an obstacle, despite a valid seven-point route when only that verified chair was excluded. A destination moved during relocation caused a 2.5-meter position jump after the student was marked seated. Approach and return steps now share a verified own-chair exclusion. A moved destination aborts in place and releases pending claims. Room containment also prevents a chair rolled into a hallway from becoming a new classroom spawn or relocation target.

The expanded seating test passed actual approach/return, concurrent human claims, new actor obstruction, retry, moved destination, and class ending during another move. Broader NPC occupancy and discipline-route checks are recorded separately.

The assignment behavior test found a stale fixture assumption and a production cancellation ordering issue. The fixture now waits for the real frame-based opening presentation and explicitly asserts that the pending opening cannot commit the reply's biography early. Production checks host/dossier validity before waiting for that opening, so obsolete queued speech is discarded immediately. All original safety assertions remain. The dedicated run against lazy dossier storage passes 566 checks, with no failures (`assignment-final.log`).

The subsequent [broader character and speech gate](../character-regressions/README.md) passed all 52 cases with zero unexpected errors, including a fresh assignment run, memory/relationship/evolution/facial regressions, full speech lifecycle, and actual AC-fault subtitle presentation. Its exact pass list and raw logs are stored alongside its summary. Assignment check counts vary with the generated student roster; both recorded runs pass all assertions.

## Limits

These are deterministic integration tests and rendered UI checks, not live-provider voice auditions. They do not establish account access, acoustic identity, physical speaker output, microphone quality or perceived emotional realism. The provider fixtures synthesize PCM rather than using OpenAI speech.

This Linux environment cannot load the repository's Windows-only CEF extension. Each Mono log retains the exact three known extension-loader diagnostics. The regression summary distinguishes those platform diagnostics from unexpected script, parse, assertion or runtime errors; none of the latter remain in the passing runs.
