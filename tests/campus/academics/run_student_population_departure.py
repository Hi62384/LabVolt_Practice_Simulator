#!/usr/bin/env python3
"""Exercise real ENet Session exits and inspect final recipient persistence."""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--mode", action="append", choices=("host", "client", "paused", "timeout"))
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[3]
    output = Path(tempfile.mkdtemp(prefix="labvolt-population-departure-"))
    passed = True
    for mode in args.mode or ("host", "client", "paused", "timeout"):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        processes = []
        logs = []
        try:
            for role, identity in (("server", "a" * 48), ("client", "b" * 48)):
                data = output / mode / role
                data.mkdir(parents=True)
                env = os.environ.copy()
                env.pop("OPENAI_API_KEY", None)
                env.pop("LABVOLT_OPENAI_BASE_URL", None)
                env.update(XDG_DATA_HOME=str(data), APPDATA=str(data),
                           GODOT_SILENCE_ROOT_WARNING="1", LABVOLT_POP_ROLE=role,
                           LABVOLT_POP_PORT=str(port), LABVOLT_POP_ID=identity,
                           LABVOLT_DEPARTURE_MODE=mode)
                log = (output / mode / (role + ".log")).open("w", encoding="utf-8")
                logs.append(log)
                processes.append(subprocess.Popen([
                    args.godot, "--headless", "--path", str(repository), "--script",
                    "res://tests/campus/academics/test_student_population_departure_peer.gd",
                ], env=env, stdout=log, stderr=subprocess.STDOUT))
                if role == "server":
                    time.sleep(.6)
            codes = [process.wait(timeout=22) for process in processes]
            passed = passed and all(code == 0 for code in codes)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
            for log in logs:
                log.close()
        for role in ("server", "client"):
            text = (output / mode / (role + ".log")).read_text(encoding="utf-8")
            expected_errors = (
                "ERROR: No GDExtension library found for current OS and architecture (linux.x86_64) in configuration file: res://cef_artifacts/gdcef.gdextension",
                "ERROR: GDExtension dynamic library not found: 'res://cef_artifacts/gdcef.gdextension'.",
                "ERROR: Error loading extension: 'res://cef_artifacts/gdcef.gdextension'.",
            )
            unexpected = [line for line in text.splitlines()
                          if line.startswith("ERROR:") and line not in expected_errors]
            marker = f"STUDENT_DEPARTURE_{mode.upper()}_{role.upper()} PASS"
            bad = "SCRIPT ERROR" in text or "FAIL:" in text or bool(unexpected) or marker not in text
            passed = passed and not bad
            for line in text.splitlines():
                if bad or line.startswith(("STUDENT_DEPARTURE", "DEPARTURE_TIMING")):
                    print(mode + "/" + role + ": " + line)
    print("STUDENT_POPULATION_DEPARTURE " + ("PASS" if passed else "FAIL") + " " + str(output))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
