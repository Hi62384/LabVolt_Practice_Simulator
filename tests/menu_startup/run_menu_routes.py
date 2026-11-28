#!/usr/bin/env python3
"""Run the actual menu routes with the repository's real local Worker relay.

Uses an already installed Wrangler and a built/imported Godot Mono project.
Relay and game are children of one process so restricted execution environments
do not split their loopback network namespaces. Saves and logs are disposable.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import urllib.request

REPO = Path(__file__).resolve().parents[2]
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
CEF_ERRORS = (
    "ERROR: No GDExtension library found for current OS and architecture (linux.x86_64) in configuration file: res://cef_artifacts/gdcef.gdextension",
    "ERROR: GDExtension dynamic library not found: 'res://cef_artifacts/gdcef.gdextension'.",
    "ERROR: Error loading extension: 'res://cef_artifacts/gdcef.gdextension'.",
)


def stop(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def inspect(log: str, expected_pass: str) -> dict:
    lines = [ANSI.sub("", line).strip() for line in log.splitlines()]
    errors = [line for line in lines if re.search(r"(?:SCRIPT ERROR:|ERROR:|Assertion failed|FATAL ERROR:|MENU_ROUTES FAIL)", line)]
    allowed = [line for line in errors if line in CEF_ERRORS and os.name != "nt"]
    unexpected = [line for line in errors if line not in allowed]
    return {"pass_found": expected_pass in lines, "expected_pass": expected_pass, "unexpected_errors": unexpected, "known_environment_errors": allowed}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--dotnet-root", type=Path)
    parser.add_argument("--wrangler", type=Path, required=True, help="Installed wrangler/bin/wrangler.js")
    parser.add_argument("--repository", type=Path, default=REPO)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--inspector-port", type=int, default=9229)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--xorg-display", type=int)
    parser.add_argument("--script", default="tests/menu_startup/test_menu_routes.gd")
    parser.add_argument("--expected-pass", default="MENU_ROUTES PASS")
    args = parser.parse_args()
    repository = args.repository.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    profile = output / "user-data"
    profile.mkdir(exist_ok=True)
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(profile), APPDATA=str(profile), LOCALAPPDATA=str(profile), WRANGLER_SEND_METRICS="false", CI="true")
    env.update(LABVOLT_RELAY_URL=f"ws://127.0.0.1:{args.port}", LABVOLT_STARTUP_CAPTURE=str(output))
    if args.dotnet_root:
        env["DOTNET_ROOT"] = str(args.dotnet_root.resolve())
        env["PATH"] = env["DOTNET_ROOT"] + os.pathsep + env.get("PATH", "")
    relay = display = None
    results: dict = {"repository": str(repository), "relay": "actual relay/worker.mjs through local Wrangler and DurableObject", "headless": not args.native}
    started = time.monotonic()
    try:
        with (output / "relay.log").open("w") as relay_log:
            relay = subprocess.Popen(
                [shutil.which("node") or "node", str(args.wrangler.resolve()), "dev", "--config", str(repository / "relay/wrangler.jsonc"), "--ip", "127.0.0.1", "--port", str(args.port), "--inspector-port", str(args.inspector_port), "--local", "--persist-to", str(output / "relay-state")],
                cwd=repository, env=env, stdout=relay_log, stderr=subprocess.STDOUT,
            )
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            deadline = time.monotonic() + 40
            ready = False
            while relay.poll() is None and time.monotonic() < deadline:
                try:
                    with opener.open(f"http://127.0.0.1:{args.port}/health", timeout=.5) as response:
                        ready = response.read() == b"LabVolt relay v1"
                        if ready:
                            break
                except (OSError, TimeoutError):
                    time.sleep(.2)
            results["relay_ready"] = ready
            if not ready:
                raise RuntimeError("Production relay did not become healthy; game test was not reported as passed")
            if args.native and args.xorg_display is not None:
                display = subprocess.Popen(
                    ["Xorg", f":{args.xorg_display}", "-config", "/etc/X11/xorg.conf", "-noreset", "-ac", "-listen", "tcp", "-nolisten", "unix", "-nolisten", "local", "-logfile", str(output / "xorg.log")],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                env.update(DISPLAY=f"127.0.0.1:{args.xorg_display}", LIBGL_ALWAYS_SOFTWARE="1")
                time.sleep(1)
                if display.poll() is not None:
                    raise RuntimeError("Native display did not start")
            command = [args.godot, "--path", str(repository), "--audio-driver", "Dummy"]
            command += ["--rendering-method", "gl_compatibility"] if args.native else ["--headless"]
            command += ["--script", "res://" + args.script]
            game_started = time.monotonic()
            with (output / "menu-routes.log").open("w") as game_log:
                game = subprocess.Popen(command, cwd=repository, env=env, stdout=game_log, stderr=subprocess.STDOUT)
                with (output / "menu-routes.log").open() as monitor:
                    while game.poll() is None:
                        if "SCRIPT ERROR:" in monitor.read():
                            results["stopped_for"] = "script_error"
                            stop(game)
                            break
                        if time.monotonic() - game_started > args.timeout:
                            stop(game)
                            raise subprocess.TimeoutExpired(command, args.timeout)
                        time.sleep(.1)
            results.update(inspect((output / "menu-routes.log").read_text(errors="replace"), args.expected_pass))
            results.update(exit_code=game.returncode, game_seconds=time.monotonic() - game_started)
            results["passed"] = game.returncode == 0 and results["pass_found"] and not results["unexpected_errors"]
    except (RuntimeError, subprocess.TimeoutExpired, OSError) as error:
        results.update(passed=False, failure=str(error))
    finally:
        stop(display)
        stop(relay)
        results["total_seconds"] = time.monotonic() - started
        (output / "result.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))
    return 0 if results.get("passed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
