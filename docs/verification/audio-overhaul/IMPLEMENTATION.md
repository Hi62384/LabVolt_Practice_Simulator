# NPC audio and natural voice conversations

Implementation and verification record, 2026-11-27. Development branch: `audio-overhaul-20261127`, based on `windows-launcher` at `7ec6c95241fca70e724783d6234dc3f445a6630c`.

## Acceptance status

The code integrates permanent voice profiles, current provider transports, expressive delivery, shared microphone capture, natural targeting, authoritative character reasoning, queued positional playback, classroom interruption/resume, multiplayer routing, settings, and diagnostics. Deterministic tests and actual local network peers exercise those paths.

**Acoustic acceptance remains open.** This environment has no configured live OpenAI credential, physical microphone, listening setup, or usable desktop display. No permanent custom voice was created on a real account, no teacher voice was heard or approved, and no actual room echo, speaker feedback, device hotplug, or subjective emotional performance test passed here. The voice studio preserves that distinction: descriptions and provisional presets are not approved custom voices. Synthetic PCM and loopback service fixtures are explicitly identified throughout the tests.

## What was repaired

The previous implementation had multiple microphone consumers, competing capture-buffer reads, short automatic recording limits, an interaction-panel-dependent conversation path, global provider-busy fallbacks, speech state indexed too coarsely by room, and lecture timing that could advance independently of what players were hearing. Those conditions could lose recordings, change the effective voice when a provider was busy, replace queued speech, or leave multiplayer lectures paused.

The new implementation makes capture a shared service, routes natural voice through the existing character system, gives every character/utterance a bounded lifecycle, separates provider request lanes, and ties lecture progress to pending and completed playback. Additional regressions found and fixed fragmented resampling at noninteger rate ratios, interrupted playback on clients, delayed transfer cancellation after normal host completion, and muted hosts advancing other players' speech too early.

## Voice identities and approval

`assets/campus/faculty/character_voice_designs.json` contains an explicit design for each of the 21 established teachers. Designs describe adult vocal age, accent, resonance, texture, articulation, pace, and characteristic delivery. They are keyed by stable character identity rather than roster position. Existing public-figure-style character names do not instruct the provider to imitate the corresponding person.

`teacher_voice_profiles.gd` persists voice IDs, provider/model compatibility, profile versions, candidates, audition records, and approvals in `user://character_voices.json`. Students use durable identity assignments and a matching pool, with allocation limits and externally reserved capacity. Corrupt stores fail closed; allocation does not silently delete another voice to make room. Transient errors do not regenerate or replace permanent voices.

The **Character Voices** studio searches teachers and students, shows the current design and approval state, creates a candidate, auditions different emotions, and requires a deliberate approval action. Normal, sad, and angry samples must finish playing before quality approval can be recorded. This checks that the audition workflow happened; only a listener can decide whether the result actually fits. A failed or interrupted audition does not approve the voice. The previous permanent voice remains available while a candidate is being evaluated.

Prompt voices are compatible with GPT-Live. A saved incompatible voice is reported explicitly; it is not replaced with a different preset or sent to the wrong endpoint. The implementation retains an explicitly selected legacy offline adapter for compatibility tests. Piper is not a fallback in normal OpenAI gameplay.

## Personality, emotion, and phrase delivery

`character_voice_delivery.gd` combines stable identity, personality style, sustained emotional state, immediate reaction, conversational intent, and projection. It handles mixed feelings and different intensities, including restrained versus overt anger, subdued sadness that overrides habitual excitement, fatigue, hesitation, amusement, concern, and disinterest. Vocal identity is preserved; playback pitch is not used to manufacture different emotional identities.

The final-text helper supplies phrase guidance to the real synthesis request and ongoing Live sessions. It accepts bounded, validated phrase transitions, keeps changes in effect until the next explicit transition, and leaves unspecified emotional dimensions unchanged. A response remains one continuous synthesis request so the implementation does not introduce independently generated clip seams. This is a supported delivery mechanism, not proof that a model performed the requested emotion convincingly.

Cache keys include the character, approved voice/model, profile version, exact words, delivery instructions, phrase guidance, intensity, projection, and pace. Request IDs and retry counters are excluded. A delivery change invalidates a cached performance without changing the speaker's identity.

## Providers and game authority

The transports are intentionally distinct:

| Use | New-install selection | Transport |
| --- | --- | --- |
| Exact game text rendered as speech | `gpt-realtime-2.1-mini` | Realtime WebSocket |
| Microphone transcription | `gpt-transcribe` | Audio transcription HTTP API |
| Optional continuous conversations / prompt voices | `gpt-live-1.1` | Live WebSocket |
| Existing compatible saved selections | Preserved, with lifecycle warnings | Their documented endpoint |

`CharacterInteraction` and the existing character mind remain responsible for knowledge restrictions, educational claims, personality, relationships, memory, and actions. Live delegates a transcribed utterance to that same authority. Provider-generated dialogue cannot independently grade work, perform actions, or replace the authoritative response. Both Realtime speech and Live speech are withheld until their output transcript matches the complete validated text. Missing or mismatching transcripts produce text fallback.

That check trades latency for control of educational content. The transport receives audio incrementally, but this implementation does **not** promise immediate audible streaming of unvalidated words. It also cannot prove acoustic pronunciation merely because a transcript matches. Real service latency and performance remain acceptance work.

Speech, transcription, and reasoning have separate bounded request lanes. Different characters can progress concurrently; the same actor and player are serialized across typed, manual-microphone, and Live turns. There are cancellation tokens, deadlines, bounded retry/backoff, explicit account/model errors, session reuse, and stale-result checks. Only the host handles the API credential. Changing credentials cancels old requests and clears availability metadata from the previous account.

See [provider-contracts.md](provider-contracts.md) for official sources, exact API contracts, lifecycle dates, quota assumptions, billing boundaries, and provider regression commands.

## Shared microphone and privacy

`MicrophoneCapture` is the sole owner of `AudioStreamMicrophone` and `AudioEffectCapture`. Human proximity voice, private phone calls, NPC recognition, and local settings tests subscribe to that shared source. They do not independently clear or drain its capture buffer.

Native C# performs input conditioning and stateful resampling to 16 kHz PCM. The capture service emits 20 ms packets, activity metadata, speech onset, and coherent segments. The activity detector preserves preroll, allows ordinary pauses, and carries 30-second chunks under one turn identity. Completed transcription turns are bounded at three minutes/8,000 transcript characters; they do not become unrelated 30-second conversations. This is a local energy/zero-crossing heuristic with noise-floor adaptation, not a claim of a neural speech detector or accurate emotion recognition from waveform alone.

Push-to-talk, voice activation, and mute are explicit modes. NPC recognition is a separate opt-in, disabled by default. Muting, turning recognition off, leaving play, opening a menu, changing a device, or starting a private phone call cancels relevant NPC input. Private call audio is routed only to the call participant and is excluded from NPC hearing/AI. Diagnostic readouts retain numeric state, not microphone recordings or keys.

The local microphone test does not submit to a provider. **Test transcription** and **Test response and voice** are separate explicit cloud actions in the host's settings. They use the same capture service.

### Echo management

Native acoustic echo cancellation is **not implemented**. The UI and diagnostics say so. Speaker protection gates open-microphone NPC recognition while NPC output is active; holding push-to-talk permits an intentional interruption. Headphones mode allows continuous interruption. This avoids claiming a threshold increase or complete microphone shutdown is full-duplex AEC. Speaker-based hands-free interruption and realistic room acoustics must be tested separately and require an actual echo-cancellation backend to meet unrestricted full-duplex acceptance.

## Natural conversations and classroom continuity

With recognition enabled, speech onset chooses a nearby visible NPC using gaze, distance, line of sight, current conversation, and an authority-issued invitation. A nearer aligned human prevents accidental NPC targeting unless the conversation or invitation is explicit. The host rechecks the actor, class, room, distance, line of sight, and private-call state. Natural conversations do not open the typed panel or require E; follow-up turns keep the selected identity while the context remains valid.

Sustained player speech can pause a speaking NPC. Brief acknowledgments do not automatically force a full answer. The interrupted utterance retains its playback position and queued continuation. Resume is sent to the other hearing peers as well as applied locally. Lesson time keeps its remaining duration while the question is active, and the assessment transition waits for final narration. Invited NPC questions speak before the teacher replies.

Addressed academic speech is exempt from a separate loudness-only noise reprimand during that input turn. The character still interprets the recognized meaning, and unrelated sustained opted-in classroom noise still reaches classroom behavior. The implementation does not infer distress, confidence, or intent reliably from microphone volume; those richer acoustic interpretations remain a live-input validation area.

Class, phase, teacher, target, or session changes invalidate pending audio and active classroom channels. An old asynchronous callback cannot clear a new session's reservation. Students' classmate channels are canceled alongside the teacher's channel on an assessment/class transition, while unrelated rooms continue normally.

## Playback, multiplayer, and presentation

NPCs, human proximity voice, and private calls have separate buses and controls. NPC PCM uses clip-level speech-gated RMS adjustment, limited gain, peak headroom, bus compression, and limiting. Projection preserves meaningful whisper/quiet/normal/lecture/shout differences and internal dynamics. These are measured RMS/peak controls, not a claim of integrated LUFS or listening-room calibration.

NPC speech uses positional players, a single distance attenuation stage, short whisper ranges, and basic ray-tested wall attenuation/filtering. The scheduler has priorities, aging, bounded concurrency, duplicate request listeners, and separate queued/playing/suspended states. A local speech mute cannot cancel another player's transfer or change their utterance timing; the host can retain an inaudible authoritative presentation clock.

Audio transfers use bounded reliable chunks with size/order/hash validation and session/actor guards. Private replies target their recipient; public speech targets listeners in the relevant hearing context. A slow client's valid transfer survives normal host playback completion but stops on explicit cancellation. Test peers receive identical PCM bytes.

Subtitles start with playback, progress through intact text, and resume with the utterance. Without audio, readable text fallback remains. Mouth movement follows the playback envelope and expressive gestures continue for the utterance. This is amplitude-based mouth animation, not phoneme/viseme recognition. Subjective lip synchronization and animated presentation still need a visible, audible playthrough.

## Verification performed

The primary game runtime used was Godot 4.5.1 Mono with the project rebuilt in .NET. Provider protocol tests also ran on native Godot 4.7.2. All profiles were isolated from normal user data; fixtures remove real credentials.

| Verification | Observed result |
| --- | --- |
| .NET project build | Passed, zero warnings/errors |
| Real Main menu, Singleplayer Play and Host Game Play | Passed with a local Wrangler relay; `MENU_ROUTES PASS` |
| Natural Main-scene conversation | 18 checks passed: speech onset without E, opt-in, actual HTTP adapter, character memory, positional playback, follow-up, mute, walk-away |
| Speech pipeline | Ten suites passed: scheduler, playback, long delivery, transport, lifecycle, native DSP, NPC turns, lecture deadline, route cancellation |
| Speech audio multiplayer | Two real ENet processes passed: identical payload, private reply, pause/resume, cancellation, session change |
| Existing classmate multiplayer | Host and client passed the existing full-Main network regression |
| Provider and Live bridge | HTTP/WebSocket protocol fixtures and real ENet routing passed; transcript mismatch, duplicate delegation, bounded long input, credentials, cancellation, serialization covered |
| Existing AI HTTP regressions | Host client, teacher AI, evaluation, and character HTTP transport passed |
| Shared capture and resampling | 62-second coherent-turn test and fragmented 8/11.025/16/22.05/44.1/48/96 kHz boundaries passed |
| Voice identity/studio/targeting | Persistence, compatible stable identity, candidate approval, emotional instructions, nearby-human privacy, and occlusion cases passed |
| Conversation context | Addressed sound, stale turns, old-session reservation, invited student gate, and class-phase cancellation passed |
| Audio and Character Voices layout | Native Control geometry passed at 1280×720 and studio sizes 1060×660 / 720×460; scrolling and controls remain reachable |

The original Linux import cache listed the project's Windows-only optional CEF extension. Initial tests emitted extension-loading errors. For clean Linux verification, only the generated `.godot/extension_list.cfg` was cleared; no tracked CEF configuration or production extension was removed. Pixel screenshots and physical pointer placement were unavailable because the isolated display server could not establish a usable display. Geometry checks are reported separately from visual QA.

Useful reproduction commands, after importing assets and building the Mono project:

```sh
python tests/campus/academics/run_voice_pipeline_tests.py --godot /path/to/godot-mono --logs /tmp/labvolt-voice-pipeline
python tests/campus/academics/run_speech_audio_network.py --godot /path/to/godot-mono --logs /tmp/labvolt-voice-network
python tests/campus/ai/run_voice_provider_tests.py --godot /path/to/godot-mono
python tests/campus/ai/run_character_http_tests.py --godot /path/to/godot --output /tmp/labvolt-http
```

Standalone scene tests use `godot --headless --path . --script res://tests/campus/academics/<test>.gd` with an isolated `XDG_DATA_HOME`/`APPDATA`. The natural gameplay test additionally needs `openai_fixture_server.py` and `LABVOLT_OPENAI_FIXTURE_PORT` in the same network namespace. Menu instructions are in [tests/menu_startup/HANDOFF.md](../../../tests/menu_startup/HANDOFF.md); use the actual relay override to exercise hosted Play.

## In-game completion steps

1. Configure the host's OpenAI account in **OpenAI Settings**, inspect the available compatible models, and enable the desired speech/transcription or Live capabilities.
2. Open **Character Voices**. Generate a candidate for each established teacher, listen to normal/sad/angry and additional emotional samples, compare the intended age/accent/timbre, and approve only satisfactory results. Repeat for student identities or the matched pool within actual account capacity.
3. In **Settings → Audio**, choose input/output devices, microphone mode, recognition opt-in, and the appropriate headphones/speaker-protection setting. Run the explicit local/transcription/response tests.
4. Play singleplayer and with a remote human: approach an NPC without E, ask a long question, pause naturally, follow up, interrupt a lecture, verify the exact resumed explanation, leave range, mute, reconnect, and change class phase. Check quiet/strong speech and noisy-room conditions with real hardware.
5. Listen for identity consistency across moods, clipping, intelligibility, distance/occlusion, simultaneous NPCs, subtitles, and mouth/gesture timing. Check current account errors, actual latency, billing, and candidate quota reporting.

These steps are outstanding acceptance work; the fixture results do not replace them. The development branch preserves the implementation without representing provisional voices as final approved performances.
