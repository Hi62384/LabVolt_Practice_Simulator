#!/usr/bin/env python3
"""Run real ENet character checks with separate disposable host/client saves.

Requires Python 3.10+ and an imported/built Godot Mono project on Windows or
Linux. Fixtures use fixed local ports, so run one copy of this harness at a time.
No provider credentials or relay override are inherited. Full logs, isolated
saves and JSON results remain under --output, including on failure.

Example:
  python3 tests/campus/academics/run_character_network_checks.py \
    --godot /path/to/Godot_mono --dotnet-root /path/to/dotnet \
    --output /tmp/labvolt-network --cases human_discipline
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid


CASES = {
    "facing": ("tests/campus/academics/test_teacher_facing_network.gd", "FACING", ()),
    "classmate": ("tests/campus/academics/test_classmate_network.gd", "CLASSMATE", ()),
    "phone": ("tests/campus/computers/test_phone_network.gd", "PHONE", ("26364",)),
    "human_discipline": (
        "tests/campus/academics/test_human_discipline_network.gd", "HUMAN_DISCIPLINE", (),
    ),
}
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(
    r"\b(?:SCRIPT ERROR:|ERROR:|FATAL ERROR:|Fatal error|Unhandled [Ee]xception|"
    r"Assertion failed|Segmentation fault|FAIL\b)"
)
LINUX_GDCEF_ERRORS = (
    re.compile(
        r"ERROR: No GDExtension library found for current OS and architecture "
        r"\(linux\.[A-Za-z0-9_]+\) in configuration file: "
        r"res://cef_artifacts/gdcef\.gdextension"
    ),
    re.compile(r"ERROR: GDExtension dynamic library not found: 'res://cef_artifacts/gdcef\.gdextension'\."),
    re.compile(r"ERROR: Error loading extension: 'res://cef_artifacts/gdcef\.gdextension'\."),
)


def inspect_log(text: str, expected_pass: str) -> dict:
    lines = [ANSI.sub("", line).strip() for line in text.splitlines()]
    allowed: list[str] = []
    unexpected: list[str] = []
    for line in lines:
        if not ERROR.search(line):
            continue
        if sys.platform.startswith("linux") and any(rule.fullmatch(line) for rule in LINUX_GDCEF_ERRORS):
            allowed.append(line)
        else:
            unexpected.append(line)
    return {
        "expected_pass": expected_pass,
        "pass_found": expected_pass in lines,
        "pass_markers": [line for line in lines if re.search(r"\bPASS\b", line)],
        "unexpected_errors": unexpected,
        "allowed_environment_errors": allowed,
    }


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    try:
        process.terminate()
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
    except ProcessLookupError:
        process.wait(timeout=5)


def read_log(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def run_case(name: str, repository: Path, godot: str, base_env: dict[str, str], output: Path, timeout: float) -> dict:
    script, prefix, extra = CASES[name]
    directory = output / name
    directory.mkdir()
    started = time.monotonic()
    deadline = started + timeout
    peers: list[dict] = []
    issue = ""
    interrupted = False
    print("START " + name + " " + str(directory), flush=True)
    try:
        for role in ("host", "client"):
            profile = directory / (role + "-profile")
            profile.mkdir()
            log_path = directory / (role + ".log")
            env = base_env.copy()
            env.update(XDG_DATA_HOME=str(profile), APPDATA=str(profile),
                       LOCALAPPDATA=str(profile), LABVOLT_CHARACTER_TEST_ISOLATED="1")
            command = [godot, "--headless", "--path", str(repository),
                       "--script", "res://" + script, "--", role, *extra]
            with log_path.open("w", encoding="utf-8") as log:
                process = subprocess.Popen(command, cwd=repository, env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
            peer = {"role": role, "process": process, "log": log_path,
                    "profile": str(profile), "command": command,
                    "expected_pass": prefix + "_" + role.upper() + " PASS"}
            peers.append(peer)
            if role == "host":
                ready = prefix + "_HOST_READY"
                while True:
                    data = read_log(log_path)
                    if inspect_log(data, peer["expected_pass"])["unexpected_errors"]:
                        raise RuntimeError("Host reported an unexpected error before readiness")
                    if process.poll() is not None:
                        raise RuntimeError("Host exited before client launch: " + str(process.returncode))
                    if time.monotonic() >= deadline:
                        raise TimeoutError("Host did not become ready before the case deadline")
                    if ready in [ANSI.sub("", line).strip() for line in data.splitlines()]:
                        break
                    time.sleep(0.1)
        while True:
            finished = True
            for peer in peers:
                process = peer["process"]
                code = process.poll()
                checked = inspect_log(read_log(peer["log"]), peer["expected_pass"])
                if checked["unexpected_errors"]:
                    raise RuntimeError(peer["role"] + " reported an unexpected error")
                if code is None:
                    finished = False
                elif code != 0:
                    raise RuntimeError(peer["role"] + " exited with code " + str(code))
                elif not checked["pass_found"]:
                    raise RuntimeError(peer["role"] + " exited without " + peer["expected_pass"])
            if finished:
                break
            if time.monotonic() >= deadline:
                raise TimeoutError("Host/client processes did not finish before the case deadline")
            time.sleep(0.1)
    except KeyboardInterrupt:
        interrupted = True
        issue = "Interrupted by user"
    except Exception as error:
        issue = type(error).__name__ + ": " + str(error)
    finally:
        for peer in peers:
            try:
                stop_process(peer["process"])
            except Exception as error:
                issue += ("; " if issue else "") + peer["role"] + " cleanup failed: " + str(error)
    report = {"case": name, "script": script, "issue": issue,
              "interrupted": interrupted, "seconds": round(time.monotonic() - started, 2),
              "peers": []}
    for peer in peers:
        text = read_log(peer["log"])
        result = inspect_log(text, peer["expected_pass"])
        result.update(role=peer["role"], exit_code=peer["process"].returncode,
                      log=str(peer["log"]), profile=peer["profile"], command=peer["command"])
        result["passed"] = result["exit_code"] == 0 and result["pass_found"] and not result["unexpected_errors"]
        report["peers"].append(result)
        if not result["passed"]:
            print(peer["role"] + " LOG TAIL\n" + text[-5000:], flush=True)
    report["passed"] = not issue and len(peers) == 2 and all(peer["passed"] for peer in report["peers"])
    (directory / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", required=True, help="Godot Mono executable path or command on PATH")
    parser.add_argument("--dotnet-root", type=Path, help="Optional local .NET installation")
    parser.add_argument("--output", type=Path, help="Parent directory for unique runs, logs and isolated saves")
    parser.add_argument("--cases", nargs="+", choices=list(CASES), default=list(CASES))
    parser.add_argument("--timeout", type=float, default=95, help="Total seconds allowed per host/client case (default: 95)")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be a positive finite number")
    # These variables redirect Godot's native data directory on both supported
    # platforms. Do not risk real user saves on an unverified platform.
    if not (sys.platform.startswith("linux") or sys.platform == "win32"):
        parser.error("Isolated native user data is currently supported on Windows and Linux")
    repository = Path(__file__).resolve().parents[3]
    candidate = Path(args.godot).expanduser()
    godot = str(candidate.resolve()) if candidate.is_file() else shutil.which(args.godot)
    if not godot:
        parser.error("Godot executable not found: " + args.godot)
    godot = str(Path(godot).resolve())
    cases = list(dict.fromkeys(args.cases))
    for name in cases:
        if not (repository / CASES[name][0]).is_file():
            parser.error("Missing fixture: " + CASES[name][0])
    env = os.environ.copy()
    for key in ("LABVOLT_RELAY_URL", "OPENAI_API_KEY", "LABVOLT_CHARACTER_OFFLINE_TRACE",
                "LABVOLT_OPENAI_FIXTURE_PORT", "LABVOLT_OPENAI_BASE_URL"):
        env.pop(key, None)
    if args.dotnet_root:
        dotnet = args.dotnet_root.expanduser().resolve()
        if not dotnet.is_dir():
            parser.error(".NET root is not a directory: " + str(dotnet))
        env["DOTNET_ROOT"] = str(dotnet)
        env["PATH"] = str(dotnet) + os.pathsep + env.get("PATH", "")
    parent = (args.output or repository / ".godot" / "character-network-verification").expanduser().resolve()
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = parent / ("network-" + stamp + "-" + uuid.uuid4().hex[:8])
    output.mkdir(parents=True)
    summary = {"kind": "real native ENet peers; isolated host/client saves; no live provider",
               "repository": str(repository), "output": str(output), "selected_cases": cases,
               "timeout_seconds": args.timeout, "passed": False, "results": []}
    for name in cases:
        result = run_case(name, repository, godot, env, output, args.timeout)
        summary["results"].append(result)
        summary["passed"] = len(summary["results"]) == len(cases) and all(item["passed"] for item in summary["results"])
        serialized = json.dumps(summary, indent=2)
        (output / "summary.json").write_text(serialized, encoding="utf-8")
        (parent / "latest-results.json").write_text(serialized, encoding="utf-8")
        print(json.dumps(result), flush=True)
        if result["interrupted"]:
            return 130
    print("CHARACTER_NETWORK " + ("PASS" if summary["passed"] else "FAIL") + " " + str(output), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
