# Process restart, network identity, and final consistency review

The final targeted checks used Godot **4.5.1 Mono** and the production Main scene, C# worker, host persistence, ENet transport, and character UI. Each process used disposable user data. The wrapper removed provider credentials. Authored provider fixtures were used only where a complete spoken response was required to test delivery; these results do not establish live model quality or voice synthesis quality.

## Actual process restart

[The two-process summary](restart-network/process-restart/summary.json) records writer PID 5 and reader PID 25 using the same isolated save. The writer passed **45 checks** in 13.61 seconds and the fresh reader passed **93 checks** in 12.08 seconds. These are whole-process harness durations, including Main startup, not conversation latency or a startup optimization benchmark.

The writer enters actual Singleplayer, retains 31 saved students, customizes one saved identity and an independent trait, and exercises personal stories, conflict, an apology, and student conversation through the Faculty entry point. A deferred synthetic biography response goes through structured validation, appears in the actual selected Mr Bro conversation panel, and becomes canonical only after delivery. The fresh reader compares all relationships, conversations, legacy biography maps, the new biography-record ledger, processed-event receipts, belief revisions, every resident profile, and the allocator index. It also verifies listener privacy, long-conversation retrieval, saved conversation willingness, all 16 emotion values, and recovery consistent with a real elapsed interval.

This check exposed an actual migration problem: a version-8 host with a new conversation was receiving old authored teacher biography defaults on its next launch. The migration condition now uses the loaded pre-version-8 source version. New histories remain free to establish their own facts; older saves preserve their authored anchors. The final full-map comparison passes, including absence of a newly injected fixed bench record.

The fixture was also updated to represent the intended APIs: it supplies the combined structured response schema, opens the real selected teacher instead of bypassing the selection guard, and resolves historical student fixtures through their authoritative dossier projection before comparing runtime profiles. No persistence assertion was removed.

## Actual ENet host/client verification

[The combined network summary](restart-network/network-summary.json) contains four passing cases, with separate host and client logs for each. Facing, phone and human-discipline cases passed in the initial sweep; the classmate case was rerun after fixing the public-profile boundary. The summary records both source runs rather than claiming all cases came from one unchanged run.

| Case | Observed result | Whole case duration |
| --- | --- | ---: |
| Teacher facing | Host and client PASS | 36.98 s |
| Classmate conversation | Host and client PASS | 29.93 s |
| Phone interaction | Host and client PASS | 32.73 s |
| Human discipline | Host and client PASS | 32.02 s |

The classmate test sends a genuine authenticated question between two processes, rejects a stale class target, delivers two ordered speech payloads, preserves the full emotional payload and gesture, and runs the real client affect-recovery loop. It checks that public animation traits remain usable without exposing biography, worldview, private markers, or additional personality values. The first spoken line is an explicitly labeled structured provider fixture; the second is an explicit transport payload.

The first classmate run found a production error: a redacted public profile still contained a small public trait dictionary and was mistakenly hydrated through a local private dossier. Besides missing-trait errors, a same-ID local save could have supplied unrelated private data. Authenticated public snapshots now carry `identity_scope: public`; reception assigns that scope even for an older snapshot. Store creation, projection, direct dossier projection and generation queuing all respect the boundary. Public views remain the authorized public view and never create a private incomplete dossier. The [schema regression](restart-network/schema.log) includes same-ID collision and no-persistence/no-generation checks and passes.

## Persistent decisions and asynchronous group work

The independent review found that permanent disengagement read an obsolete `grudge_holding` key while the authoritative trait schema uses `grudges`. The corrected path is covered by an unchanged authored Brian profile, alongside explicit state-transition fixtures. The root verification suite separately covers persistence, optional reconsideration after verified experiences, official safety communication, and delivery-time commitment of a reconsidered decision.

The review also found that the source memory version was not included in the bounded unsaved-profile cache. That version now resets and restores with the selected host, preventing one owner's migration status from carrying into another owner's recovered session. The separate memory-resilience test exercises the actual legacy-version/corrupt-profile switch.

Group contribution generation now requires the same current actor to remain seated and present in shared work, with no pending removal, both before scheduling and after the awaited response. NPC helpers remain outside the graded round's human participant list. The actual Main regression caught an overly broad initial guard that required the NPC in both lists; the corrected fixture now reproduces production's solo-human group with an ungraded NPC helper. The human teammate's eligibility still uses the graded round's presence list.

These guards close a concrete route race: removal marks a student as leaving before they reach the door and become fully removed. A delayed group note can no longer overwrite that active movement with “discussing group work.” The [group test](restart-network/group-intent.log) passes **18 checks**, including bounded scheduling, released-content privacy, offline silence, phase changes, pending removal, lost shared presence, actor replacement and ungraded helper membership. It uses an explicit held-response scheduling fixture.

## Evidence limits and reproducibility

Passing runs have no unexpected script or engine errors. They retain the three known baseline Linux errors for the repository's Windows-only CEF extension. Earlier failing attempts remain in the isolated working output; the committed evidence contains the successful targeted results and explains the confirmed defects that preceded them.

[Source hashes](restart-network/source-hashes.json) identify the code and test files at completion of the targeted review. Full logs are stored next to the summaries. Real model inference, actual token averages, TTS quality and simultaneous multiplayer model-load performance still require configured live credentials.
