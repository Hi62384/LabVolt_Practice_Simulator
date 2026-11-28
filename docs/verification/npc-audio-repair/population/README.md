# Persistent population verification

The final targeted suites passed on the project-matching **Godot 4.5.1.stable.mono.official.f62fdbde1**, Linux x86_64, with `/tmp/labvolt-runtime/dotnet` configured through `DOTNET_ROOT` and `PATH`. Each targeted test used separate disposable Godot user data. The eight population/dossier compatibility suites were rerun after the final ownership and storage-validator fixes; the final 4.5.1 binding and memory logs were reused from the main integration run. No production source changes were needed for compatibility.

The separate-process evidence below was collected with Godot 4.7.2 on Linux x86_64 and retains that runtime label in `process-summary.json`. Network tests used actual separate host/client processes and ENet loopback transport. The dossiers, player identities, dialogue and provider responses were synthetic fixtures.

This directory contains passing logs and summaries only. No isolated save directories, credentials, microphone data or private player records are included.

## Targeted assertions

The eight suites that report assertion counts completed **572 checks on Godot Mono 4.5.1**. The two additional targeted suites passed without reporting an assertion count. Machine-readable results are in `targeted-summary.json`; each row has a corresponding latest 4.5.1 log. `mono451-compatibility-summary.json` records the eight suites rerun specifically for engine compatibility, including **495 counted checks** plus lifecycle and generation passes.

| Suite | Result | Coverage |
| --- | --- | --- |
| Lazy dossier store | 38 checks passed | Version-1 migration, preserved original bytes, cold manifest loading, selection-only hydration, foreign origin recovery, blob/manifest backups, double corruption without regeneration, interrupted migration |
| Portable population | 107 checks passed | Random stable IDs and legacy aliases, authoritative eligibility and explicit elective enrollment, fixed generation seeds, attendance deduplication, bounded learning, duplicate/conflicting identities, private own relationships, redacted moods and causal reconciliation |
| Population corruption | 208 checks passed | Byte preservation, backup recovery, known identity retention, unsaved session state, profile isolation, bounded fallback caches |
| Classroom binding | 23 checks passed | Real classroom controller ownership, learning migration, continuing practice after host change, official marks excluded from portable progress |
| Dossier scope failures | 56 checks passed | Cache exhaustion, failed outgoing writes, failed target migration, repeated and recovered handoffs, stale owner objects, malformed generation/subjects/revisions, blocked mutation during transition |
| Adversarial synchronization | 46 checks passed | Malformed nested records, nonfinite values, bounded revisions, expired requests, same-profile transport changes and immediate peer-cache cleanup |
| Canon race | 40 checks passed | An actual memory update during a synthetic held generation request prevents stale biography publication and preserves completed valid work |
| Memory resilience | 54 checks passed | Existing persistence, malformed snapshot and recovery behavior |
| Synchronization lifecycle | Passed | Missing runtime nodes, initialization retries, host/client transitions, exact population/brain instance binding and teardown |
| Dossier generation | Passed | Existing synthetic generation, repair and publication contracts |

The lazy fixture contains 24 complete dossiers. Opening its manifest and population loads no full dossiers; selecting three students hydrates exactly those three. The manifest is asserted to be less than one-eighth the size of the original full collection. Existing incomplete legacy migration seeds remain supported.

## Separate-process verification

Results, runner paths and the Godot 4.7.2 runtime are recorded in `process-summary.json`. These process runs were retained from the preceding final verification; the later 4.5.1 compatibility pass was scoped to the targeted suites above.

| Run | Result | Observed behavior |
| --- | --- | --- |
| Population ENet host/client | Passed | Client population contribution, returned own friendship, course/week learning, global mood, a second incremental state update and retained identity after origin disconnect |
| Dossier process restart | Both write and read passed | A different operating-system process restores the same identity, biography, traits, speech, voice and interrupted generation job |
| Host graceful departure | Both peers passed | Final recipient memory was saved before receipt; observed drain time 61 ms |
| Client graceful departure | Both peers passed | Leaving client requested the authoritative final state and retained it on disk |
| Paused-world departure | Both peers passed | The checkpoint completed while the world was paused; observed drain time 57 ms |
| Missing receipt | Both peers passed | The deliberately absent acknowledgement produced `saved=false` and returned after 2,021 ms; host durable state remained available |

The departure fixture reopens recipient files to assert that the final interaction reached durable local storage. Timings are observations from this local run, not a latency guarantee. The configured deadline is two seconds; completion is checked on engine frames, so the observed timeout can exceed it by a frame.

## Reproduction

Use the project-matching Godot 4.5.1 Mono executable with its .NET runtime configured. Use disposable `XDG_DATA_HOME`/`APPDATA` directories for standalone Godot scripts, especially tests with fixed fixture profile names. With that executable available as `godot`, run a targeted script with:

```sh
godot --headless --path . --script res://tests/campus/academics/dossier/test_dossier_lazy_store.gd
```

The process runners create their own isolated data:

```sh
python3 tests/campus/academics/run_student_population_network.py
python3 tests/campus/academics/run_student_population_departure.py
python3 tests/campus/academics/dossier/run_dossier_process_restart.py
```

## Scope and limits

The repository's Windows CEF extension is unavailable in these Linux headless runs. Logs therefore contain the three known extension-loading errors before the tests start; no GDScript errors or other unexpected engine errors occurred in the passing runs. Deliberate invalid IEEE-number fixtures can emit Godot conversion warnings, and the binding fixture deliberately emits a warning when rejecting an invalid profile selection.

These results establish the actual GDScript storage, migration, reconciliation and ENet behavior exercised by the fixtures. They do not establish live AI dossier quality, custom voice access on another account, Windows hardware behavior, or reliability under every packet-loss or sudden-process-termination scenario. Graceful leave/quit waits for a bounded durable receipt; an abrupt failure can prevent an in-flight update from reaching another device. The authoritative host retains its saved record for later reconciliation.

Menu Singleplayer/Host startup, native presentation, voice hardware and broader application checks are recorded separately by the main integration verification.
