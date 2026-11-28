# Student continuity, manual conversations and runtime storage

Verification date: 2026-11-27 (America/Los_Angeles). Native checks used Godot 4.5.1 Mono on Linux with isolated Godot user data. Authored provider fixtures are explicitly identified below; these checks do not establish microphone-device behavior, live model quality, Windows CEF behavior or exported Windows runtime behavior.

## Confirmed defects and repairs

### Student memory durability

`student_social_archive.gd` previously changed its in-memory digest even when its atomic save failed. An identical later observation then looked unchanged and could report a receipt without retrying the write. Switching player profiles could also abandon that unsaved state. The new regression reproduces this through an actual filesystem obstruction at the staging-file path, rather than mocking `save()`.

The archive now tracks dirty state, retries unchanged observations until they are durable, refuses an ownership change that would discard unsaved observations, and validates the complete merged record before replacing healthy data. A failed save returns no durable observation receipt. Unconfigured archives cannot create a relative temporary file in the working directory.

`student_population_sync.gd` now distinguishes sending an update from receiving an authenticated durable-save receipt. A sent dossier fingerprint is committed only after the peer acknowledges the matching update token. Failed writes leave the update available for bounded retry. The production ENet test obstructs the client's real archive staging path, verifies that the write remains unsaved, removes the obstruction, and verifies that a retransmission becomes durable and reloadable. Disconnect and profile-binding cleanup keep those receipts associated with their original owner.

The population's eligible student selection, existing identity keys, host-scoped memories and persistent learning remain in place. No broad roster or memory reset was used to resolve these failures.

### Optional classroom AI

Ordinary student movement, studying, seating and mood progression use local gameplay logic. The audit found that optional greetings, classmate exchanges and generated discipline comments could still request AI while no player could observe them.

`classroom_students.gd` now requires a connected human identity in the same room, within 16 metres of an arrived, present classmate. The campus shares a budget of four optional generated turns per rolling 60 seconds. Both sides of a classmate exchange consume a turn. Pending player questions, active character conversations and an occupied provider suppress new optional work. Direct player questions retain their independent admission path. Delayed optional replies are rejected after the audience, phase or ownership changes; local consequences and already perceived memories remain.

A second cost defect was found in the shared interaction pipeline: `listen_only` was checked in `generate()`, after `prepare()` had already called moderation and either character response or assessment interpretation. Consequently, hearing an NPC reply could generate an unused full response, and the exhausted-budget fallback could still make a provider call. The shared pipeline repair moves listening-only perception before remote work. This is distinct from moderation of actual player input and generated spoken output.

### Manual typed and microphone conversations

The inspector's typed and recorded questions previously used an empty voice context. Closing and reopening the same NPC therefore preserved enough identity/class information for an old transcription or model result to enter the new conversation. Repeated microphone requests also lacked a turn-level deduplication key.

The actual inspector path now establishes a per-peer random conversation nonce, an increasing turn number and a unique request ID. The host validates the current identity, selected room, class and actor before queueing. Reliable ordered RPCs carry begin, question and end operations. Duplicate requests cannot enter transcription or character generation twice, and repeating a begin does not reset the accepted turn counter. Retired nonces are bounded to 32 per peer and removed when that peer disconnects.

Closing, changing the selected NPC, invalidating the selection or replacing the peer's identity invalidates the old context. Transcription and model calls receive a live guard. Canceled queued work is removed; an active reservation stays occupied until its original coroutine exits so an old completion cannot release a newer request. Reply statuses also carry the nonce and request ID, preventing a delayed status from overwriting a reopened inspector.

Each spoken reply is associated with its owning conversation and exact channel/serial. Closing cancels that utterance in synthesis, transport and playback without canceling another player's unrelated synthesis listener. A reliable registration arrives before a speech envelope; a closed client tombstones that serial so an envelope already in transit cannot resurrect it. Explicit captured microphone targets are checked against the current selection before sending.

Compatibility entry points used by existing trusted internal callers and older tests remain available. Natural proximity voice retains its own routing context and hearing range. The manual UI continues to enforce its shorter interaction range.

## Native verification

| Check | Observed result | Scope |
|---|---|---|
| `test_student_social_durability.gd` | 11 checks passed | Real failed-save staging path, retry, ownership change, invalid merge and reload |
| `test_student_population_portable.gd` | 107 checks passed | Persistent portable student state |
| `test_student_sync_adversarial.gd` | 46 checks passed | Adversarial sync validation |
| `run_student_population_network.py` | Both peers passed, including `--storage-failure` | Separate actual ENet host/client processes and durable retry |
| Student departure harness | Host, paused host and client saved successfully; missing receipt timed out with `saved=false` | Four actual network lifecycle modes |
| `test_student_background_budget.gd` | 13 checks passed | 1,200 unobserved ticks produce no optional exchange; remote audience, human priority and rolling ceiling |
| `test_student_voice_turns.gd` | Passed | Existing presentation order with audience policy isolated in its own test |
| `test_assignment_student_behavior.gd` | 553 checks passed | Actual Main assessment behavior and delayed-memory cancellation with an authored provider |
| `test_classmate_lab_and_dialogue.gd` | Passed after manual-session integration | Actual Main interactions, rendered classmates and live simulation solvers; authored provider |
| `test_seating_presentation.gd` | Passed | Current actual Main chair collisions, seat handoff, seated rig and HUD behavior |
| `test_student_world_integration.gd` | Passed | Actual Main world/student integration |
| `test_student_discipline_routes.gd` | Passed | Actual discipline movement and route execution |
| `test_manual_conversation_lifecycle.gd` | 36 checks passed | Actual Main UI and character pipeline held across teacher/student close, reopen and switch; STT duplicate, stale completion, peer isolation and exact cancellation |
| `run_manual_conversation_network.py` | Both peers passed | Separate actual ENet peers; duplicate WAV, ordered close/reopen, stale upload/cancel, authenticated queues, stale UI and speech envelope |
| `test_character_inspector_network.gd` | Passed | Existing actual ENet target/identity/range guards, updated to perform a real new selection after invalidation |
| `test_character_request_timing.gd` | 19 checks passed | Existing queue/STT/playback timing behavior remains measured by real scheduling signals |

The assessment and classroom-dialogue fixtures compress separate meetings into one wall-clock minute. They reset the optional-work budget between those independent scenarios. The dedicated budget regression verifies the production rolling ceiling without resetting it. Fixture provider subclasses explicitly override contextual moderation so a local regression cannot accidentally use a live service.

## Storage destinations and launch behavior

The audited production NPC persistence and voice paths write under Godot `user://`, including host-scoped character memories, student populations and social archives, generated dossiers, voice selections, speech temporary data and usage/preferences. Authored `res://` voice-profile data is read as a bundled default; it is not the runtime profile save destination. Existing launcher installation/cache paths use Windows Local Application Data, separately from Godot saves.

The editor-only campus visual preview plugin writes its temporary packed scene under `.godot` while the editor is playing a scene. It is not a production memory writer or a source PNG generator. `Run Game.cmd` still performs its import/build bootstrap: no confirmed tracked source mutation justified removing necessary bootstrap behavior. A blanket ignore rule was not added.

`verify_runtime_storage.py` supplies the runtime write check. It takes an exact game/test command, isolates user data, hashes tracked files before and after execution, and reports new untracked files, actual process status and unexpected engine errors. Its report explicitly excludes ignored engine import/build caches and does not claim that a clean repository proves correct gameplay. Run it after imports/builds and while other repository editors are stopped. The same harness can wrap a separately installed Windows export; that Windows/exported check still needs execution in the appropriate environment.

Two consecutive guarded workloads passed after production edits stopped. Each checked the content hashes of **6,920 tracked files** and reported **zero modified tracked files, zero newly untracked files, zero newly tracked files, zero unexpected engine errors and process exit 0**.

| Guarded workload | Native behavior verified | Duration | Files under isolated user data |
|---|---|---:|---:|
| Actual Main manual-conversation lifecycle | All 36 checks passed; UI, character memory and held transcription/model completion lifecycle | 14.262 seconds | 101 |
| Consecutive persistence and speech checks | Portable students: 107 checks; portable voice profiles; actual speech temporary-file cleanup with process adapters; speech-player cache lifecycle | 4.419 seconds | 68 |

The file counts include ordinary engine logs and generated user data. They do not include a claim that every file is a player save. The second workload ran four successive native Godot processes, with three known Windows-only CEF extension messages per process; no other engine errors were accepted. Profile filenames, keys and contents remain outside the committed report. This verifies native Linux runtime writes under the exercised workloads, not an exported Windows executable.

```sh
python tests/campus/academics/verify_runtime_storage.py --output /tmp/labvolt-storage-check -- \
  /path/to/Godot_mono --headless --path . \
  --script res://tests/campus/academics/test_manual_conversation_lifecycle.gd

python tests/campus/academics/run_manual_conversation_network.py \
  --godot /path/to/Godot_mono --dotnet-root /path/to/dotnet \
  --output /tmp/labvolt-manual-network
```

Linux runs distinguish the existing three Windows-only CEF extension-load messages from unexpected script/engine errors. Native microphone permission, physical input/output devices, acoustic echo, Windows export/launcher execution and live external-provider latency require separate device/provider acceptance. Those results must not be inferred from the authored fixture completions or headless native checks above.
