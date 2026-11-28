# NPC audio, presentation, seating and persistent students

## Scope and verified starting point

Work starts from `windows-launcher` commit `5190d08d90592f0e3f382574ddb5f309193969fd`. Recovery checkpoints are published to `dev/npc-audio-population-repair` and independently read back from GitHub. The established destination for completed changes is `windows-launcher`.

| Published checkpoint | Scope |
| --- | --- |
| `ada012b7d2aedeee56c26b72af052c2d206df6b4` | Common voice-profile loading failure and audition completion |
| `9982735c604bf7390d35d7fedfd13fa4b89d40bd` | Speech-only providers and rebuilt local voice studio |
| `85084a27309a5af84ab86082ef5ec7cb5b8d5ddb` | Recorded microphone turns, shared seating and portable populations |
| `7f83fcb8a897b4e429868d4de623437dfcf8ccba` | Preserve equation grouping and SI unit case during transcript validation |

The first confirmed common cause was a GDScript inference failure in `teacher_voice_profiles.gd`: an untyped Dictionary method result was assigned with inferred typing. It prevented dependent voice profiles, synthesis and the Character Voices interface from compiling. The fix was executed in Godot, and the actual interface now populates all 21 established faculty without API access.

## Implementation

- NPC microphone interaction uses local recording, completed-recording transcription, the existing character intelligence/memory pipeline, selected speech generation, and spatial playback. The active continuous Live conversation bridge and its separate settings control are retired. Compatibility entry points cannot reactivate microphone streaming.
- Live and Realtime remain selectable speech providers. A short-lived render session receives the already authored dialogue, voice identity and performance instructions. Live receives only protocol silence, never player microphone packets. Audio Chat and operational legacy TTS use their appropriate endpoints. Existing catalog pricing, lifecycle information and explicit model/voice compatibility remain intact.
- Speech transcript validation recognizes deterministic numeric, unit, contraction and punctuation equivalents. It still rejects changed values, signs, operators, negations, mathematical grouping and case-sensitive SI prefixes. For example, milliwatts cannot become megawatts, and `2*(3+4)` cannot become `2*3+4`. Unknown spoken forms remain conservative failures. Genuine failures remain visible and recovery stays bounded on the selected provider.
- The Character Voices interface loads local faculty/students first, has a persistent searchable/filterable left roster and a themed scrollable detail area, appearance preview, voice design, model selection, candidate/audition/approval controls and a collapsed advanced section. Opening it performs no paid voice request. Approved custom IDs, allocation records and auditions are retained.
- Shared capture has independent consumer subscriptions for human voice, NPC turns, manual questions and microphone testing. A unity-gain capture bus precedes a muted monitor sink. PCM processing, device state, frame counts, sensitivity, drain-on-release, two-second utterance silence and short-noise cleanup are exercised in the actual engine. Natural targeting uses real character head positions and sticky conversational targets; private calls remain excluded.
- NPC dialogue uses the existing single screen-space subtitle queue. Nameplates contain names only. Captions have a dark padded background, measured HUD avoidance, pagination and playback-position timing. The layout is recomputed after viewport/HUD changes.
- Classroom students retain chair orientation while an attention/emotion compositor turns the head within limits. Their generated rig gains a knee pivot for seated posture; imported/player cosmetic rigs keep their original hierarchy.
- Actual chair objects carry stable seat IDs, human/NPC occupancy, arrival/vacating state and human reservations. A request reserves the source and NPC destination, executes collision-checked movement, and grants the human seat only after clearance. Blocked routes, concurrent requests, expired reservations, class teardown and disconnection release pending state. Moving a destination chair aborts in place; a seated student can approach and return while excluding only their own claimed chair. Other standing/walking students also block the path, and a chair rolled outside its classroom cannot become a spawn location.
- Persistent populations use unique identities, origin-qualified legacy aliases, authoritative program/course eligibility, bounded on-demand multiplayer contributions and recurring weighted selection. Own relationships, significant experiences and redacted global emotional state travel in validated causal receipts. Bounded NPC course/week capability continues on a new host; official marks stay local. Identity/biography conflicts retain established facts, and unrelated private conversations, credentials and audio are excluded. See `docs/PERSISTENT_STUDENT_POPULATION.md` for reconciliation rules.
- Local population selection uses a lightweight index. Complete dossiers are individually loaded from validated content-addressed files and cached when requested. The manifest is committed only after its files; legacy monolithic saves and corrupt evidence are retained during migration/recovery. Opening or filtering the Studio does not hydrate every student.
- A normal leave/quit waits for a bounded, reliable ordered persistence acknowledgment before closing the transport. Host exit, client exit, a paused session and missing acknowledgments have separate process tests. Connection loss still saves locally; no protocol can deliver after the physical link has disappeared.
- Delayed student social replies now validate phase/profile ownership before waiting for earlier playback. A changed host or phase cannot leave a stale reply queued or canonize a line nobody heard.

## Verification performed during implementation

Tests run with isolated user data. Godot Mono 4.5.1 matches the project's .NET SDK; the C# build completed with zero warnings and zero errors. Known Linux-only CEF extension errors are reported separately because the repository packages its browser extension for Windows.

| Area | Executed evidence | Limits |
| --- | --- | --- |
| Voice Studio | Actual Godot widget construction, all faculty, local student filter, candidate lifecycle, audition completion, approvals and saved voice identity | Provider responses in automation are simulated |
| Voice Studio rendering | Actual native OpenGL render at 1280x720 and resized 720x520; visual inspection of roster, preview, detail and controls | Linux software renderer, not the Windows exported build |
| Provider adapters | Real loopback HTTP/WebSocket fixtures exercise production Live/Realtime/Audio Chat request/event/audio paths, cancellation and usage | No real OpenAI account was called |
| Transcript equivalence | Numeric/unit/contraction equivalents and factual mismatch cases | Deterministic conservative equivalence, not a semantic proof |
| Shared microphone | Synthetic audio through real AudioServer capture/effect bus and C# PCM processing; independent subscribers, mute, settings lifecycle, silence segmentation | Synthetic source, not physical microphone hardware |
| Natural conversation | Actual Main scene, local HTTP service, opt-in, no-E approach, follow-up turns, switching targets, input-event push-to-talk, manual recording with UI open, same character memory route | Authored fixture replies/audio, not live AI or human listening |
| Seating/presentation | `test_seating_presentation.gd` executes actual Main chairs/navigation, concurrent claims, NPC relocation, human handoff, seated rig, HUD avoidance and cleanup | Additional platform/human playtesting remains useful |
| Seating/presentation rendering | Native classroom screenshot visually verifies bent knees, chair alignment, name-only label and unobstructed captions | No GPU performance claim |
| Persistent population | Portable identity/eligibility/restart/conflict/privacy tests; separate real ENet host/client processes exchange manifest, dossiers, own relationships and disconnect updates | Uses synthetic coherent historical dossiers, not paid AI generation |
| Session lifecycle | Host/client role changes with the same stable profile, replaced runtime objects, failed initialization, leaving flush and teardown | Automated process lifecycle |
| Lazy local storage | 36 checks for migration, zero eager loads, selected-only loads, original-byte preservation, blob backup repair, double corruption without reroll, manifest backup and interrupted migration | Real local files; synthetic coherent dossiers |
| Population robustness | 107 portability checks, 208 corruption checks, 46 adversarial nested-payload/authentication/lifecycle checks | Malformed and conflicting input is exercised locally and over real ENet |
| Graceful departure | Separate real Session/ENet processes verify the final same-frame relationship event survives into a fresh client disk read; host/client/paused/timeout scenarios | Successful loopback acknowledgments about 50–63 ms; a missing receipt stops waiting after approximately two seconds |
| Academic behavior | Real grading/learning tests and 566 assignment checks preserve privacy, intent, canon, cancellation and own-student progression | Simulated dialogue services, actual character pipeline and game state |

The required Singleplayer and Host Game startup smoke is rerun after integration. The first run found only stale expectations that local settings must disappear without an API key; the updated gate verifies the local roster remains available while paid controls and Accept stay disabled until valid credentials are supplied. Final gate results are recorded below after the final source changes.

## Official API references checked

- https://developers.openai.com/api/reference/resources/live/primary-websocket
- https://developers.openai.com/api/docs/guides/live-conversations
- https://developers.openai.com/api/docs/guides/text-to-speech
- https://developers.openai.com/api/docs/deprecations

Live's documented startup-text mechanism does not guarantee exact speech or any speech. The application therefore collects and validates the generated clip and handles failure explicitly. Legacy `tts-1`, `tts-1-hd` and `gpt-4o-mini-tts` remain deprecated but operational until their documented January 6, 2027 shutdown; no replacement is selected silently.

## Not verified in this environment

The connected Windows command service reported that its tunnel client was offline. No usable live API credentials or physical microphone were available here. Consequently, this work does not claim successful real-account Live/custom-voice synthesis, subjective voice/emotion quality, physical Windows microphone capture, speaker/headset echo performance, or exported Windows end-to-end multiplayer audio. These remain required live acceptance checks; fixture/provider transport success is not a substitute.
