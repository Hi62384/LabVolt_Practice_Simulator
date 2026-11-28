# Final character and classroom regression verification

## Result and evidence

**58 distinct regression suites passed: all 45 default suites and 13 additional
classroom and teacher suites.** None of these selected final results was
skipped. The complete assertions and output markers are preserved in
`regressions/summary.json` and the 58 adjacent, unmodified test logs.

The comparison baseline was commit
`7ec6c95241fca70e724783d6234dc3f445a6630c`. All 33 default suites present on
that baseline passed before implementation. The baseline result list is
`startup/baseline-regressions.json`. Current results cover the expanded suite;
this is a regression comparison, not a claim that 58 new tests all existed
on the baseline or that synthetic response quality has been established.

Verification used actual Godot 4.5.1 Mono, .NET SDK 8.0.428, the real game
modules and isolated user-data directories. Tests that load the full game use
the actual `Main.tscn` and Singleplayer flow. Provider fixtures are explicitly
authored local fixtures. Network coverage includes the real local ENet
transport and production authorization paths. No live model credentials were
available, so none of these results proves natural generated conversation,
live student biography quality or live TTS delivery.

## Covered behavior

| Area | Verified behavior |
| --- | --- |
| Dossier generation and identity | Validated publication contracts, canonical identity, retained intended teacher design, bounded generation pipeline behavior and truthful offline status |
| Fictional life ledger | Established facts, linked records, source separation, chronological updates and local indexed lookup across 2,001 stored records |
| Conversation consistency | Combined structured turn validation, conflicting spoken claims and proposed changes, protected observations, retry and delivery accounting |
| Relationships and emotion | Different teacher dispositions, persistent relationship decisions, context and beliefs, public affect without private trait exposure |
| Silence and physical actions | Actual Main dispatch accepts supported actions, rejects invalid ones and produces no speech or invented narration for intentional silence |
| Persistence and recovery | Legacy versions, save/profile isolation, corruption recovery, original damaged-byte preservation, canonical population binding and memory summaries |
| Actual classroom operation | Actual graders, academic provenance, assignment behavior, discipline, helper participation, station actions, world movement and class events |
| Speech lifecycle | Playback start signals, stale/cancelled requests, long speech, synchronous and asynchronous synthesis contracts and expression restoration |
| Inspection and privacy | Real UI navigation, selected-character state, read-only requests, bounded/cached packets, replay protection, authorized ENet transport and text/microphone selection guards |
| Local numerical decisions | Independent disposition values, attention, escalation, hearing authority and consistency with intended identity |
| Facial geometry | 4,878 assertions covering semantic parts, symmetric eye hierarchy, rest poses, animation ownership, brow anchors, teeth and UV streams |
| Additional classroom coverage | Shared work, surprises, escalation, hearing, projectiles, solution challenges, apologies, demonstrations, quizzes, participation and practice panel behavior |

Numerical facial assertions are accompanied by separate **native rendered**
verification. See `FACIAL_VERIFICATION.md` for the isolated expression matrix,
baseline comparison and 18 inspected captures of actual faculty models in
the real campus scene. Native inspector layouts and the mandatory real
Singleplayer/Host Game startup gates have their own reports.

## Corrections made during regression verification

The new architecture intentionally removes generic canned dialogue from
ordinary offline social turns. Older tests that asserted those exact strings
were updated to assert the underlying host state, required information,
behavioral intention, safe technical failure and actual delivered output.
Tests needing historical students now seed explicit saved legacy fixtures;
these fixtures do not stand in for live AI generation.

Meaningful assertions were retained: permission boundaries, exact supported
actions, verified academic facts, assessment integrity, stale-request guards,
relationship persistence, actual class membership and save recovery still
have to pass. A shared-work fixture also had a preexisting baseline mismatch:
eight members create four teams under the production team size, so its old
two-team expectation was corrected while preserving same-team access and
privacy assertions.

The full Main classroom test exposed a real new integration defect. NPC
helpers belong to shared group work without being graded human participants.
The asynchronous validity guard had checked the graded roster and therefore
discarded valid helper contributions. The implementation now checks the NPC's
actual shared membership, current actor, seated state and pending removal;
the human teammate still must be present in the active graded round. Both
the focused stale-actor/membership test and the actual Main helper interaction
passed after this correction.

Other implementation defects found and corrected during the wider integration
included public character projections being mistaken for private canonical
identities, stale migration state injecting legacy biography into a fresh
identity, and low teaching motivation incorrectly suppressing an otherwise
sociable teacher's willingness to talk. The respective authoritative-state,
restart, numeric disposition and gameplay tests are retained.

## Final source and run provenance

The selected results combine a complete 45-suite gate, 13 extra suites and
targeted retakes after confirmed corrections. The first gate ran while the
last integration changes were landing. Thirty affected default suites were
therefore rerun after the production freeze; corrected group, summary,
class-call and actual Main classmate cases were separately rerun. All 13
extra suites were rerun. Eleven unaffected passing suites from the first
gate were retained. Every result records its exact source run, captured log
timestamp, log hash and test-source hash; failed intermediate results have
not been relabeled as passing.

`regressions/source-manifest.json` records SHA-256 hashes for **684 production
`.gd`, `.cs` and `.gdshader` files**, captured at 2026-11-28 01:30:19 UTC before
the final affected-suite retakes. All 684 hashes were checked again after
those tests and were unchanged. This was the working tree after checkpoint
`d55cd873841e4c5dc299d58075766f07e2bcba48`; the manifest deliberately does not
claim that a later publication commit had already existed during the runs.

The logs contain no unexpected engine or GDScript errors. Full-game tests
emit the same three errors seen on the baseline because the repository's
CEF extension is packaged for Windows and cannot load on Linux. Startup
verification explicitly enumerates these three errors and fails on any
additional error. Browser rendering through that Windows extension remains
unverified here.

## Measured performance and limits

The final local life-ledger fixture retrieved from 2,001 records in an average
**0.37336 ms** and serialized those records to **426,810 bytes**, with zero
remote requests. These are measured synthetic local-storage results, not
live biography generation time or a multiplayer capacity benchmark.

The real interaction-controller accounting fixture demonstrates one combined
semantic/dialogue provider call for an ordinary turn, compared with two
sequential semantic/dialogue calls in the baseline. Required input and output
moderation calls remain. `REQUEST_ACCOUNTING.md` records this comparison and
the context byte measurements. Bytes are not reported as tokens. Actual
provider input/output token usage remains unavailable without a live call.

The request-timing suite checks the real queue and playback-start accounting
paths with an authored transcript and synthetic audio. It verifies where
timing comes from; it does not provide a live microphone-to-character latency
or audio-device benchmark. The startup process durations are separately
reported in `MENU_STARTUP_VERIFICATION.md` and are not treated as model latency
or game frame-rate performance.

Live acceptance remains necessary for multiple newly generated students,
natural teacher transcripts, ordinary personal improvisation, mood-sensitive
wording and vocal delivery, actual input/output token use, generation cost,
remote latency and simultaneous live multiplayer conversations. The live
acceptance tooling and its explicit credential limitation are documented in
the dossier architecture report.

## Reproduction

Run `tests/campus/academics/run_character_regressions.py` with the configured
Mono Godot executable, `--dotnet-root`, a fresh `--output` directory and
`--keep-going`. Its defaults are the 45 current suites. The 13 additional
suite names and all selected individual outcomes are in
`regressions/summary.json`; pass their names with `--tests` to reproduce the
additional coverage. Do not provide a live API key unless intentionally
running the separate live acceptance tests.
