#!/usr/bin/env python3
"""Verify manual conversation RPC lifecycle in two actual Godot ENet peers."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--dotnet-root")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output = (args.output or Path(tempfile.mkdtemp(prefix="labvolt-manual-network-"))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    with socket.socket() as reserve:
        reserve.bind(("127.0.0.1", 0))
        port = reserve.getsockname()[1]
    processes: dict[str, subprocess.Popen] = {}
    logs = {}
    try:
        for role in ("host", "client"):
            profile = output / (role + "-user-data")
            profile.mkdir(exist_ok=True)
            env = dict(os.environ, XDG_DATA_HOME=str(profile), APPDATA=str(profile), LOCALAPPDATA=str(profile))
            env.pop("OPENAI_API_KEY", None)
            if args.dotnet_root:
                env["DOTNET_ROOT"] = args.dotnet_root
            logs[role] = (output / (role + ".log")).open("w", encoding="utf-8")
            processes[role] = subprocess.Popen([args.godot, "--headless", "--path", str(root), "--script",
                "res://tests/campus/academics/test_manual_conversation_network.gd", "--", role, str(port)],
                env=env, stdout=logs[role], stderr=subprocess.STDOUT)
            if role == "host":
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    text = (output / "host.log").read_text()
                    if "MANUAL_CONVERSATION_HOST_READY" in text:
                        break
                    if processes[role].poll() is not None or "SCRIPT ERROR" in text:
                        raise RuntimeError("Manual conversation host startup failed; see " + str(output / "host.log"))
                    time.sleep(.03)
                else:
                    raise TimeoutError("Manual conversation host readiness timed out")
        deadline = time.monotonic() + 25
        for process in processes.values():
            process.wait(timeout=max(.1, deadline - time.monotonic()))
        cases = []
        expected_cef = {
            "ERROR: No GDExtension library found for current OS and architecture (linux.x86_64) in configuration file: res://cef_artifacts/gdcef.gdextension",
            "ERROR: GDExtension dynamic library not found: 'res://cef_artifacts/gdcef.gdextension'.",
            "ERROR: Error loading extension: 'res://cef_artifacts/gdcef.gdextension'.",
        } if sys.platform.startswith("linux") else set()
        for role, process in processes.items():
            text = (output / (role + ".log")).read_text()
            errors = [line for line in text.splitlines() if line.startswith(("SCRIPT ERROR:", "ERROR:"))
                      and line not in expected_cef]
            passed = process.returncode == 0 and "MANUAL_CONVERSATION_" + role.upper() + " PASS" in text and not errors
            cases.append({"role": role, "passed": passed, "exit_code": process.returncode, "unexpected_errors": errors})
        report = {"transport": "real localhost ENet, two isolated processes", "live_api": False,
                  "hardware_verified": False, "cases": cases}
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"passed": all(case["passed"] for case in cases), "output": str(output), "cases": cases}))
        return int(any(not case["passed"] for case in cases))
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
        for process in processes.values():
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait()
        for log in logs.values():
            log.close()


if __name__ == "__main__":
    raise SystemExit(main())
