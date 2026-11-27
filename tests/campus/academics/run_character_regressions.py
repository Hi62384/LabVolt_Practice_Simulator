#!/usr/bin/env python3
"""Run native character regressions with disposable saves and fail-fast logs.

Requires an imported/built Godot Mono project. HTTP and multiplayer tests have
their own server harnesses. Live-provider acceptance is opt-in and billable.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
import uuid


DEFAULT_TESTS = [
    "test_character_interaction_pipeline", "test_character_evolution_pipeline",
    "test_character_worldviews", "test_character_reactions", "test_character_beliefs",
    "test_character_memory_v5", "test_character_memory_migration",
    "test_character_memory_resilience", "test_character_public_affect",
    "test_character_memory_summaries", "test_character_prior_learning",
    "test_student_population_corruption", "test_student_population_binding",
    "test_student_population_and_discipline", "test_student_discipline_routes",
    "test_character_academic_memory", "test_character_human_academic_memory",
    "test_assignment_student_behavior", "test_assignment_npc_discipline",
    "test_faculty_specialized_paths", "test_character_gameplay_overhaul",
    "test_student_world_integration", "test_classmate_lab_and_dialogue",
    "test_teacher_speech_player", "test_teacher_speech_synth",
    "test_teacher_speech_long_delivery", "test_teacher_speech_integration",
    "test_teacher_voice_stale", "test_teacher_class_call_prompt",
    "test_teacher_events", "test_teacher_relationships", "test_teacher_dialogue", "test_faculty",
]


def run_one(command: list[str], env: dict[str, str], timeout: float) -> dict:
    started = time.monotonic()
    process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines: queue.Queue[str | None] = queue.Queue()

    def read_output() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            lines.put(line)
        lines.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    output: list[str] = []
    stopped_for = ""
    while True:
        if time.monotonic() - started > timeout and not stopped_for:
            stopped_for = "timeout"
            process.terminate()
        try:
            line = lines.get(timeout=0.2)
        except queue.Empty:
            if stopped_for and process.poll() is None:
                process.kill()
            continue
        if line is None:
            break
        output.append(line)
        if "SCRIPT ERROR:" in line and not stopped_for:
            stopped_for = "script_error"
            process.terminate()
    code = process.wait(timeout=5)
    reader.join(timeout=1)
    text = "".join(output)
    markers = [line for line in text.splitlines()
               if any(word in line for word in ("PASS", "FAIL", "SKIP"))]
    skipped = code == 2 and any("SKIP" in line for line in markers)
    passed = not stopped_for and code == 0 and any("PASS" in line for line in markers)
    return {"exit_code": code, "passed": passed, "skipped": skipped,
            "stopped_for": stopped_for, "seconds": round(time.monotonic() - started, 2),
            "markers": markers, "output": text}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot Mono executable")
    parser.add_argument("--dotnet-root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--trace-output", type=Path)
    parser.add_argument("--tests", nargs="+", default=DEFAULT_TESTS)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--live-timeout", type=float, default=7500,
                        help="Seconds allowed for the opt-in multi-turn live harness")
    parser.add_argument("--keep-going", action="store_true")
    parser.add_argument("--include-live", action="store_true",
                        help="Also run billable live acceptance if OPENAI_API_KEY is set")
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[3]
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (args.output or repository / ".godot" / "character-verification" / stamp).resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    if args.dotnet_root:
        env["DOTNET_ROOT"] = str(args.dotnet_root.resolve())
        env["PATH"] = env["DOTNET_ROOT"] + os.pathsep + env.get("PATH", "")
    tests = list(args.tests)
    if args.include_live and "test_live_character_acceptance" not in tests:
        tests.append("test_live_character_acceptance")
    results: list[dict] = []
    for name in tests:
        script = repository / "tests" / "campus" / "academics" / (name + ".gd")
        if not name.startswith("test_") or Path(name).name != name or not script.is_file():
            parser.error("Unknown test: " + name)
        if name == "test_live_character_acceptance" and not args.include_live:
            parser.error("Live acceptance requires --include-live")
        test_env = env.copy()
        if name != "test_live_character_acceptance":
            test_env.pop("OPENAI_API_KEY", None)
        isolated = output / (name + "-" + uuid.uuid4().hex[:12])
        test_env.update(XDG_DATA_HOME=str(isolated), APPDATA=str(isolated),
                        LABVOLT_CHARACTER_TEST_ISOLATED="1")
        test_env.pop("LABVOLT_CHARACTER_OFFLINE_TRACE", None)
        if name == "test_character_gameplay_overhaul":
            trace = (args.trace_output or output / "offline-dialogue-traces.json").resolve()
            trace.parent.mkdir(parents=True, exist_ok=True)
            test_env["LABVOLT_CHARACTER_OFFLINE_TRACE"] = str(trace)
        command = [args.godot, "--headless", "--path", str(repository),
                   "--script", "res://tests/campus/academics/" + name + ".gd"]
        timeout = args.live_timeout if name == "test_live_character_acceptance" else args.timeout
        result = run_one(command, test_env, timeout)
        (output / (name + ".log")).write_text(result.pop("output"), encoding="utf-8")
        result["test"] = name
        results.append(result)
        (output / "summary.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(json.dumps(result), flush=True)
        if not result["passed"] and not result["skipped"] and not args.keep_going:
            break
    return int(any(not item["passed"] and not item["skipped"] for item in results))


if __name__ == "__main__":
    raise SystemExit(main())
