"""Run deterministic voice pipeline regressions with isolated Godot user data.

Requires a built Mono game project. This suite does not audition voices, contact
OpenAI, use microphone hardware or claim acoustic echo-cancellation coverage.
"""
from __future__ import annotations
import argparse
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time

SPAWN_CASES = ("test_faculty", "test_npc_spawn_smoke")

CASES = (
    "test_voice_meter_input",
    "test_subtitle_audibility",
    "test_realtime_stream_buffer",
    "test_character_worldviews",
    "test_teacher_personality_isolated",
    "test_character_interaction_pipeline",
    "test_character_request_timing",
    "test_character_voice_identity",
    "test_character_voice_studio",
    "test_custom_voice_recovery",
    "test_teacher_speech_player",
    "test_teacher_speech_synth",
    "test_teacher_speech_long_delivery",
    "test_voice_audio_transport",
    "test_voice_playback_lifecycle",
    "test_voice_speech_scheduler",
    "test_voice_audio_dsp",
    "test_student_voice_turns",
    "test_voice_lecture_deadline",
    "test_voice_route_lifecycle",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--logs", required=True)
    parser.add_argument("--cases", nargs="+", choices=CASES + SPAWN_CASES, default=CASES)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    logs = Path(args.logs).resolve()
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    for case in args.cases:
        with tempfile.TemporaryDirectory(prefix=case + "-", dir=logs) as profile:
            env = dict(os.environ, XDG_DATA_HOME=profile, APPDATA=profile)
            command = [args.godot, "--headless", "--path", str(root), "--script", f"res://tests/campus/academics/{case}.gd"]
            began = time.monotonic()
            try:
                run = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     encoding="utf-8", errors="replace", timeout=60)
                output, code = run.stdout, run.returncode
            except subprocess.TimeoutExpired as error:
                output = error.stdout or b""
                if isinstance(output, bytes):
                    output = output.decode("utf-8", errors="replace")
                output += "\nTEST TIMEOUT\n"
                code = 124
            (logs / f"{case}.log").write_text(output, encoding="utf-8")
            failed = code != 0 or not re.search(r"\bPASS\b", output) or any(
                marker in output for marker in ("SCRIPT ERROR", "Parse Error", "ERROR:", "Assertion failed", "TEST TIMEOUT")
            )
            results.append({"case": case, "passed": not failed, "exit_code": code,
                            "elapsed_seconds": round(time.monotonic() - began, 3),
                            "warnings": [line for line in output.splitlines() if line.startswith("WARNING:")]})
            print(("FAIL " if failed else "PASS ") + case, flush=True)
            if failed:
                # Make actionable errors visible immediately in CI, not only in
                # a ZIP uploaded after the entire suite finishes.
                print("\n".join(output.splitlines()[-50:]), flush=True)
    report = {"kind": "deterministic native audio pipeline regression", "live_api": False,
              "microphone_hardware": False, "voice_listening": False, "cases": results}
    (logs / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return int(any(not item["passed"] for item in results))


if __name__ == "__main__":
    raise SystemExit(main())
