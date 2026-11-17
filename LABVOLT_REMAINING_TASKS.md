# LabVolt remaining-work audit

This is a source-status and dependency record, not a claim of gameplay completion or authorization to implement the items. No tests were requested for this audit. Source presence alone does not establish that a feature works in play, and this audit is not an exhaustive guarantee.

## Remaining implementation

| Item | Source status and evidence | Dependencies and uncertainty |
| --- | --- | --- |
| 1. Real client-side web renderer for campus PCs, laptops and phones | **Complete for Windows x64 game devices.** Custom gdCEF 0.21.0 built for Godot 4.5 provides live Chromium tabs, navigation, input, login, and virtual-file/photo uploads. Its native file-dialog guard blocks host filesystem pickers; each device session has an isolated in-memory cookie context. A browser fixture passed public HTTPS, loopback form login through forwarded input, tab sharing, device isolation, virtual upload, and repeated close/reopen, including against the exported Windows executable. | Native Linux, macOS, Android, iOS, and web exports need separate renderer builds. Virtual uploads inside cross-origin frames are deliberately unavailable. Windows exports need `cef_artifacts/package_windows.ps1` for CEF sidecars. |
| 2. Host OpenAI API connection and settings menu | **Complete.** `scripts/campus/ai/host_openai_client.gd` is a host-only Responses API client, owned by `game.gd`, with an in-memory or environment API key. Settings → Host Server provides key entry, model, enable switch, token and request caps, connection check, and a prompt test. The client uses `store: false`, one in-flight request, persistent daily and rolling per-minute limits, and safe failure messages. A local API fixture passed success, auth and rate-limit errors, cap persistence and key non-persistence; an unauthenticated OpenAI TLS probe and the required menu routes passed. | A real authenticated response requires the host to supply their own OpenAI API key. The key is never saved to disk or replicated to peers. |
| 3. AI teacher lessons and free-speech interaction | `scripts/campus/academics/faculty_roster.gd`, `teacher_dialogue.gd`, `faculty.gd` and classroom event code provide fixed teachers, roster selection, offline dialogue and keyword-oriented intent. These do not establish generative lessons by course/week/personality, proximity speech-to-text, spoken Q&A, interruptions, whiteboard understanding or new teacher generation. | Depends on the host API connection, an approved speech input path, lesson/whiteboard context, moderation and multiplayer authority rules. Exact provider, cost and privacy behavior are unconfirmed. |
| 4. Distinct natural teacher voices | `scripts/campus/academics/teacher_speech_synth.gd` and `teacher_voice_profiles.gd` contain synthesis and profile plumbing. The audited 21 voice-profile model assignments are empty. | Requires usable voice assets, assignments and listening/latency validation. Existing plumbing is not evidence of 21 distinct audible voices. |
| 5. Host-connected browser assistant | No complete page-aware assistant is established by the current browser shell in `scripts/campus/computers/browser_surface.gd`. | Depends on items 1 and 2. Scope includes text/voice, current-page context and interaction, virtual file/image attachments, outputs and explicit downloads. Phone attachments must remain image-only. Page access, upload and download behavior are unconfirmed. |
| 6. Trusted classroom attribution and invention evaluation | `scripts/campus/academics/faculty.gd` contains classroom reactions, while existing circuit solver inspection does not prove that an invention met a requested objective. | Needs trusted host evidence of thrown-object/damage causality and an explicit objective/rubric evaluator. Attribution and rubric behavior are not confirmed. |
| 7. Integrated Invention Studio | Existing cores include `scripts/custom_circuit.gd`, `scripts/electronics/ic_pcb_editor/`, `scripts/pcb_design/` and `scripts/firmware_backends/`. They are not evidence of an integrated Studio. | Requires a room/table/editor, blueprints, part pricing, usable copies, material/electrical/mechanical parts, nested designs, configurable held controls and visible movement. Integration and gameplay acceptance remain unconfirmed. |

## Deferred or blocked

| Item | Source status and evidence | Dependency or uncertainty |
| --- | --- | --- |
| Cross-host atomic lost-and-found claims | `scripts/campus/lost_found/room.gd` covers the current room interaction. The audited client-local lifecycle conflicts with a cross-host atomic claim guarantee. | Requires an agreed shared authority/storage design before that guarantee can be claimed. |
| Native C/C++ compile pipeline | `scripts/firmware_toolchain/compile_service.gd` and `acceptance.gd` show a pipeline and acceptance gate. | The current trusted acceptance receipt was not verified in this audit. Do not treat source presence as proof that native compilation is currently accepted. |

## Conditional or example scope

Classroom physical exercises, persistent phone custody/confiscation and NPC crowd choreography appeared as conditional or illustrative scope. They are not automatically mandatory missing features. A product decision is needed before treating any of them as required work.

## Coded but unverified

The focus-switch assessment guard (`scripts/campus/academics/attention/focus_guard.gd`), core classroom events (`scripts/campus/academics/classroom_events/`), and recently added teacher routes and animations (`scripts/campus/academics/classroom_teacher_route.gd`, `faculty.gd`) are source work without current gameplay validation. The classroom feature gate remains off in `scripts/campus/academics/class_start/room_classes.gd:14` (`const CLASSROOM_EVENTS_ENABLED := false`); this audit does not change it.

Gym (`scripts/campus/facilities/gym_progress.gd` and related files), student chat (`scripts/campus/chat/chat.gd`), and IC/PCB/firmware systems (`scripts/electronics/ic_pcb_editor/`, `scripts/pcb_design/`, `scripts/firmware_backends/`) are also coded but unverified by this audit. Historical test reports, if any, do not validate later edits.
