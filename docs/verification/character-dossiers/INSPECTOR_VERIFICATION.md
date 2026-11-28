# Character inspector and local disposition verification

## Implemented behavior

Pressing E on a teacher or classroom student opens the selected-character panel. The persistent composer keeps typed messages, microphone recording, and applicable classroom/equipment actions. Overview, Personality, Life history, Relationships, Emotions, and Diagnostics are separate reading pages. Long descriptions and numerical traits scroll without moving the composer. State refreshes approximately every 0.8 seconds; an unrelated mood change does not rebuild an unchanged personality or life-history page.

The reader obtains complete stored descriptions explicitly from the host's dossier store. It does not call the model, initiate microphone capture, appraise a social event, or change relationship/emotion state merely because it opens. Missing request measurements display “Not recorded.” Expanded identities that are still awaiting generation retain their actual generation status.

Diagnostics distinguish host receipt to reply readiness from character-processing duration. The former includes measured queue and microphone-transcription time. Separate rows show host receipt to an available audio stream and to actual local `AudioStreamPlayer3D` playback start when those events were observed. A bounded speech-serial/event mapping keeps asynchronous audio measurements attached to the correct conversation. Unobserved stages remain absent; client upload, remote-client playback, and audio-device buffering are explicitly outside these measurements.

Local diagnostic access checks both host authority and the active host profile. Traces require the selected character and the local speaker. Another player's emotional-event explanation, belief evidence, transcript, or assessment context is not exposed. The old global F8 JSON dump is replaced by selecting the current inspector's Diagnostics page; no editor command-line flag is needed.

Joining players can read a host-provided public dossier and the selected character's relationship with their own authenticated player identity. The host checks the current roster, room, character selection, and interaction range on every request. Requests are rate-limited, packet size is capped at 192 KiB, and a selection nonce plus request serial rejects stale replies. Unchanged static identity data is omitted from later dynamic refreshes. Host diagnostics and persistence details are never included in these packets.

The panel captures the selected teacher and class at opening; automatic microphone conversations capture them at microphone start. Submission checks these identities again, preserving an unsent text draft if the target has changed. Typed questions, recorded audio, classroom feedback, and inspector actions carry their target across the network. Remote callers must supply both identifiers. The host rejects a changed teacher or class before queuing or performing work and checks queued identity again before processing. A microphone transcription also checks both identifiers after its asynchronous request. Delayed replies cannot rename an inspector that is displaying a different character.

Teacher routine attention and escalation use numeric traits, including attention span, teaching motivation, laziness, patience, anger sensitivity, confrontation, discipline, empathy, sociability, and emotional stability. Descriptive phrases such as “short temper” no longer act as hidden code switches. A confirmed defect allowed a temperament modifier to add awareness after sound attenuation; inaudible events now cannot become perceived incidents. A zero attention probability also remains zero at the random-number boundary.

## Executed checks

| Check | Runtime | Result |
| --- | --- | --- |
| `test_character_inspector.gd` | Godot 4.5.1 Mono and 4.7.2 | Passed host/profile/client authority, selected-speaker privacy, assessment redaction, read-only state, actual page controls, draft preservation, measured/unknown telemetry, and public dossier access. |
| `test_character_inspector_transport.gd` | Godot 4.5.1 Mono and 4.7.2 | Passed rate limits, packet allowlisting, static revision caching, nonce/serial/selection checks, range invalidation handling, and oversize rejection. |
| `test_character_inspector_network.gd` | Godot 4.5.1 Mono | Passed two real ENet peers using production faculty RPC handlers and production reader controls. A guest received Mr Bro's actual profile and the guest's relationship history; host history and diagnostics remained absent. Moving the guest outside interaction range invalidated the next refresh. A reliable-channel barrier verified stale text, microphone, action, and classroom-feedback requests were rejected after a teacher changed in transit. Valid typed/audio requests retained their teacher, class, and authenticated peer; a class change before queue processing rejected both. Empty target identifiers were rejected at RPC entry. No AI request or social conversation was created. |
| `test_teacher_numeric_disposition.gd` | Godot 4.5.1 Mono and 4.7.2 | Passed descriptor-wording invariance, independent attention probabilities, patient/impatient differentiation, accumulated frustration, inaudible-event authority, safety awareness, nonfinite-input rejection, and legacy numeric escalation. |
| `test_character_request_timing.gd` | Godot 4.5.1 Mono | Passed 19 assertions through production queue/transcription methods and the native speech player. An authored transcript isolates scheduling; actual monotonic timestamps measured an 84 ms typed queue hold and 124 ms transcription. The observed microphone path reached reply readiness in 131 ms; audio readiness and the native playback-start signal were recorded at 131 ms. Muted speech and missing timestamps did not invent playback or latency. These are instrumentation checks, not live API or audio-device benchmarks. |
| `test_character_silent_dispatch.gd` | Godot 4.5.1 Mono, actual Main | Passed 20 assertions with a real host-selected persistent student and the production classroom action dispatcher. A pending response creates no delivered receipt or playback. Coordinated silence preserves supported gestures, executes the first accepted shrug, and rejects a nod while the student uses equipment. Unsupported actions, unperformed narration, and unspoken biography stay absent from conversation and personal history. Both silent turns keep empty speech and create one completed receipt each, with no TTS serial. The provider response is authored test data. |
| `test_faculty_specialized_paths.gd` | Godot 4.5.1 Mono, actual Main | Passed 48 assertions for official lesson cues, delayed/cancelled callbacks, office-hours rotation, and heard-only handoff memory. Pending handoffs retain no canned fallback or spoken opening and start no playback. The previous assertion requiring a fallback field was corrected to the production delivery contract. |

## Native rendering

`render_character_inspector.gd` rendered the production controls with actual repository character data on Godot 4.5.1 Mono, the OpenGL compatibility renderer, and Mesa llvmpipe through an Xorg display. The fixture uses empty conversation history; it does not invent an AI transcript or request measurements.

- `inspector_overview.png`, `inspector_personality.png`, `inspector_diagnostics.png`: 1280 × 720.
- `inspector_compact.png`: 800 × 600.

The first rendered pass exposed a minimum-height overflow. Reader-specific control padding corrected it. The final 1100 × 684 panel fits the 720p viewport; its minimum height is 568 pixels. At 800 × 600, the 764 × 568 panel remains entirely visible with its navigation and composer intact. Long content is confined to its reading scroll area.

## Limits of this evidence

These checks verify the reader, transport, numeric decisions, and the production UI's native rendering. Campus position/session fixtures isolate the ENet test; it does not claim complete native campus gameplay or live AI dialogue quality. The environment emitted the existing missing Linux CEF extension warning; rendering also reported unsupported VSync. No new GDScript errors were emitted by these checks. Full menu and classroom regressions are recorded separately by the overall integration verification.
