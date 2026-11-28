#!/usr/bin/env python3
"""Reopen a complete dossier and interrupted generation job in two Godot processes."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--dotnet-root")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = args.output or Path(tempfile.mkdtemp(prefix="labvolt-dossier-restart-"))
    output.mkdir(parents=True, exist_ok=True)
    user_data = output / "user-data"
    user_data.mkdir(exist_ok=True)
    env = os.environ.copy()
    env.pop("OPENAI_API_KEY", None)
    env.update(XDG_DATA_HOME=str(user_data.resolve()), APPDATA=str(user_data.resolve()), LABVOLT_CHARACTER_TEST_ISOLATED="1")
    if args.dotnet_root:
        env["DOTNET_ROOT"] = args.dotnet_root
        env["PATH"] = args.dotnet_root + os.pathsep + env.get("PATH", "")
    repository = Path(__file__).resolve().parents[4]
    results = []
    for phase in ("write", "read"):
        env["LABVOLT_DOSSIER_RESTART_MODE"] = phase
        result = subprocess.run([args.godot, "--headless", "--path", str(repository), "--script", "res://tests/campus/academics/dossier/test_dossier_process_restart.gd"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        (output / (phase + ".log")).write_text(result.stdout, encoding="utf-8")
        passed = result.returncode == 0 and "DOSSIER_PROCESS_RESTART PASS" in result.stdout and "SCRIPT ERROR" not in result.stdout
        record = {"phase": phase, "exit_code": result.returncode, "passed": passed, "evidence": [line for line in result.stdout.splitlines() if "DOSSIER_PROCESS_RESTART" in line]}
        results.append(record)
        print(json.dumps(record), flush=True)
        if not passed: break
    passed = len(results) == 2 and all(item["passed"] for item in results)
    (output / "summary.json").write_text(json.dumps({"passed": passed, "synthetic_fixture_not_live_AI": True, "results": results}, indent=2), encoding="utf-8")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
