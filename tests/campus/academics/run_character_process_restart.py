#!/usr/bin/env python3
"""Verify character persistence across two real Main/Singleplayer processes.

Example (imported/built Mono project required):
  python3 tests/campus/academics/run_character_process_restart.py \
    --godot /path/to/Godot_mono --dotnet-root /path/to/dotnet \
    --output /tmp/labvolt-character-restart

Only synthetic fixture content is saved. Real provider credentials are removed;
one biography uses authored fixture output, with no TTS or live-quality claim.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import time
import uuid

from run_character_regressions import run_one


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--dotnet-root", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=90)
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[3]
    output = (args.output / ("restart-" + uuid.uuid4().hex[:12])).resolve()
    output.mkdir(parents=True)
    user_data = output / "user-data"
    user_data.mkdir()
    env = os.environ.copy()
    for name in ("OPENAI_API_KEY", "LABVOLT_CHARACTER_OFFLINE_TRACE",
                 "LABVOLT_OPENAI_FIXTURE_PORT", "LABVOLT_OPENAI_BASE_URL"):
        env.pop(name, None)
    if args.dotnet_root:
        env["DOTNET_ROOT"] = str(args.dotnet_root.resolve())
        env["PATH"] = env["DOTNET_ROOT"] + os.pathsep + env.get("PATH", "")
    env.update(XDG_DATA_HOME=str(user_data), APPDATA=str(user_data),
               LABVOLT_CHARACTER_TEST_ISOLATED="1",
               LABVOLT_CHARACTER_RESTART_EXPECTED=str(output / "expected.json"))
    command = [args.godot, "--headless", "--path", str(repository), "--script",
               "res://tests/campus/academics/test_character_process_restart.gd"]
    results: list[dict] = []
    for phase in ("write", "read"):
        env["LABVOLT_CHARACTER_RESTART_MODE"] = phase
        result = run_one(command, env, args.timeout)
        log = result.pop("output")
        (output / (phase + ".log")).write_text(log, encoding="utf-8")
        result.update(phase=phase, pid=None)
        for line in log.splitlines():
            if line.startswith("CHARACTER_RESTART_PROCESS "):
                identity = json.loads(line.split(" ", 1)[1])
                if identity.get("phase") == phase:
                    result["pid"] = identity.get("pid")
        results.append(result)
        print(json.dumps(result), flush=True)
        if not result["passed"]:
            break
        if phase == "write":
            # Guarantee a real offline interval even on very fast machines.
            time.sleep(1.2)
    distinct = (len(results) == 2 and all(isinstance(item["pid"], int) and item["pid"] > 0
                                        for item in results)
                and results[0]["pid"] != results[1]["pid"])
    passed = distinct and all(item["passed"] for item in results)
    summary = {"kind": "two native processes; actual Main and Singleplayer; synthetic data",
               "passed": passed, "distinct_processes": distinct,
               "same_disposable_user_data": True, "results": results}
    (output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("CHARACTER_PROCESS_RESTART " + ("PASS" if passed else "FAIL") + " " + str(output), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
