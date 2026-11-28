# Character and speech regression gate

Verified on November 27, 2026 (America/Los_Angeles; November 28 UTC).

**52 cases passed; zero failed cases and zero unexpected engine, script, parse, or assertion errors.** `summary.json` retains every test name, elapsed time, pass marker and diagnostic count; the matching log files retain the native output.

## Execution and scope

The gate uses the production `run_one` implementation from `tests/campus/academics/run_character_regressions.py`, Godot 4.5.1 Mono and .NET 8.0.408. Up to three independent processes ran together. Each invocation had its own disposable `XDG_DATA_HOME`/`APPDATA`, and `OPENAI_API_KEY` was removed. The scheduler stopped launching new tests after a failure, then resumed failed and unrun cases after the cause was corrected. Already passing cases were retained. The recorded checkpoint base and working-tree qualification are in `summary.json`.

This set is the default character suite, excluding the separately exercised population corruption/binding/discipline cases and student discipline routes, plus the complete voice-pipeline cases and the AC-fault smoke. It covers interaction and evolution, beliefs and relationships, character memory and migration, public affect, facial composition, real ENet inspector traffic, actual Main academic/assignment paths, student voice turn gates, speech scheduling and retries, DSP, playback pause/resume/cancellation, stale speech, custom voice recovery, and the Character Voices approval flow.

These are deterministic local fixtures and native gameplay integration checks. They do not establish external provider availability, physical microphone or speaker behavior, or human-perceived voice identity. This gate uses the headless renderer; native Studio and gameplay screenshots are recorded separately.

The repository's Windows-only CEF extension produces three exact known loader diagnostics on this Linux runtime. They are retained in every log and explicitly enumerated in `summary.json`. All other error diagnostics are failures, even if a fixture also prints a PASS marker. No test was counted as a pass after an assertion or script error.

## Diagnosed fixture failures

- `test_character_inspector_network` held the provider's global `busy` flag, which does not hold the existing per-character/peer scheduler. The fixture now holds the actual guest request lane while queued-transit checks run, then releases it. Real ENet, privacy, authenticated history, target and stale-target assertions remain.
- `test_faculty_specialized_paths` held an outgoing request but its provider fixture returned success for the incoming request while the assertions required an unavailable service. The timeout scenario now explicitly returns a provider error while that request is held, then restores successful replies. The test still requires no invented opening or reply, no unheard memory, cancellation of the late opening, and exactly-once memory for a later delivered response.
- `test_teacher_class_call_prompt`, `test_teacher_events`, and `test_teacher_ac_fault` referenced removed world-space speech labels. They now assert the actual subtitle HUD content and that no floating speech label exists. Practice-answer privacy, cooldown, attention, selected-student and stale-turn checks remain.
- The older AC-fault smoke also skipped actual Singleplayer/profile initialization and used the former fixed teacher-root position. It now enters the real Singleplayer route, uses the authenticated local identity and current instructor position, verifies the actual fault incident, and checks the subtitle presentation.

No production behavior was changed to accommodate these fixture failures. The separate production stale-social-reply fix, seating fixes and speech restoration are documented in the adjacent verification reports.

## Reproduce

Build and import the project first. Set `GODOT_MONO` to the Godot 4.5.1 Mono executable and `DOTNET_ROOT` to the .NET installation, then run the following from the repository root. This runs the same exact case list through the existing sequential runner and audits its log diagnostics.

```python
import json
import os
from pathlib import Path
import subprocess
import sys

record = json.loads(Path(
    "docs/verification/npc-audio-repair/character-regressions/summary.json"
).read_text())
output = Path("/tmp/labvolt-character-recheck")
subprocess.run([
    sys.executable, "tests/campus/academics/run_character_regressions.py",
    "--godot", os.environ["GODOT_MONO"],
    "--dotnet-root", os.environ["DOTNET_ROOT"],
    "--output", str(output), "--tests", *record["requested"],
], check=True)
allowed = set(record["expected_platform_diagnostics"])
for case in record["requested"]:
    for line in (output / (case + ".log")).read_text().splitlines():
        if any(marker in line for marker in (
            "ERROR:", "Parse Error", "Assertion failed", " FAIL"
        )) and line not in allowed:
            raise AssertionError(f"{case}: {line}")
```

## Exact passing cases

Times are individual elapsed seconds under the concurrent verification workload, not performance acceptance thresholds.

| Case | Result | Seconds |
| --- | --- | ---: |
| `test_character_dossier_pipeline` | PASS | 1.21 |
| `test_character_life_ledger` | PASS | 0.72 |
| `test_character_relationship_decisions` | PASS | 0.94 |
| `test_character_group_intent` | PASS | 0.92 |
| `test_character_silent_dispatch` | PASS | 13.84 |
| `test_character_request_timing` | PASS | 2.02 |
| `test_character_request_accounting` | PASS | 1.11 |
| `test_character_inspector` | PASS | 1.0 |
| `test_character_inspector_transport` | PASS | 0.35 |
| `test_character_inspector_network` | PASS | 3.98 |
| `test_teacher_numeric_disposition` | PASS | 0.53 |
| `test_character_facial_compositor` | PASS | 0.71 |
| `test_character_interaction_pipeline` | PASS | 1.0 |
| `test_character_evolution_pipeline` | PASS | 1.08 |
| `test_character_worldviews` | PASS | 0.9 |
| `test_character_reactions` | PASS | 1.02 |
| `test_character_beliefs` | PASS | 1.0 |
| `test_character_memory_v5` | PASS | 0.82 |
| `test_character_memory_migration` | PASS | 0.62 |
| `test_character_memory_resilience` | PASS | 0.71 |
| `test_character_public_affect` | PASS | 0.81 |
| `test_character_memory_summaries` | PASS | 0.9 |
| `test_character_prior_learning` | PASS | 0.9 |
| `test_character_academic_memory` | PASS | 12.64 |
| `test_character_human_academic_memory` | PASS | 12.08 |
| `test_assignment_student_behavior` | PASS | 13.1 |
| `test_assignment_npc_discipline` | PASS | 12.54 |
| `test_faculty_specialized_paths` | PASS | 13.32 |
| `test_character_gameplay_overhaul` | PASS | 13.56 |
| `test_student_world_integration` | PASS | 13.04 |
| `test_classmate_lab_and_dialogue` | PASS | 17.15 |
| `test_teacher_speech_player` | PASS | 0.33 |
| `test_teacher_speech_synth` | PASS | 0.43 |
| `test_teacher_speech_long_delivery` | PASS | 1.67 |
| `test_teacher_speech_integration` | PASS | 11.52 |
| `test_teacher_voice_stale` | PASS | 0.34 |
| `test_teacher_class_call_prompt` | PASS | 1.75 |
| `test_teacher_events` | PASS | 13.4 |
| `test_teacher_relationships` | PASS | 0.73 |
| `test_teacher_dialogue` | PASS | 12.18 |
| `test_faculty` | PASS | 11.54 |
| `test_character_voice_identity` | PASS | 0.84 |
| `test_character_voice_studio` | PASS | 3.34 |
| `test_custom_voice_recovery` | PASS | 0.43 |
| `test_voice_audio_transport` | PASS | 0.25 |
| `test_voice_playback_lifecycle` | PASS | 0.34 |
| `test_voice_speech_scheduler` | PASS | 1.01 |
| `test_voice_audio_dsp` | PASS | 0.35 |
| `test_student_voice_turns` | PASS | 0.72 |
| `test_voice_lecture_deadline` | PASS | 1.75 |
| `test_voice_route_lifecycle` | PASS | 1.66 |
| `test_teacher_ac_fault` | PASS | 13.3 |
