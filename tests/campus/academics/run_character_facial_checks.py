#!/usr/bin/env python3
"""Run production facial modules in an isolated Godot project.

This avoids the game's Windows-only browser extension without replacing any
facial implementation. Native runs require an actual X11/Windows/macOS display;
dummy headless images never count as rendered verification.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[3]
RENDER = "tests/campus/academics/render_character_faces.gd"
TESTS = [
    "tests/campus/academics/test_character_facial_compositor.gd",
    "tests/campus/academics/test_teacher_speech_player.gd",
]
PRELOAD = re.compile(r'preload\("res://([^"\n]+)"\)')


def prepare(destination: Path, seeds: list[str], ref: str | None = None) -> dict[str, str]:
    import hashlib

    destination.mkdir(parents=True, exist_ok=True)
    (destination / "project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="Facial verification"\n'
        '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
        '[display]\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=1060\n'
    )
    pending = list(seeds)
    hashes: dict[str, str] = {}
    while pending:
        path = pending.pop()
        if path in hashes:
            continue
        # The same newly added measurement scene is used for both revisions.
        if ref and path != RENDER:
            content = subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=REPO)
        else:
            content = (REPO / path).read_bytes()
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        hashes[path] = hashlib.sha256(content).hexdigest()
        pending.extend(PRELOAD.findall(content.decode("utf-8")))
    return hashes


def run(godot: str, project: Path, script: str, output: Path, env: dict[str, str], native: bool = False, image: Path | None = None) -> dict:
    command = [godot, "--path", str(project), "--audio-driver", "Dummy"]
    command += ["--rendering-method", "gl_compatibility"] if native else ["--headless"]
    command += ["--script", f"res://{script}"]
    if image:
        command += ["--", str(image)]
    started = time.monotonic()
    result = subprocess.run(command, cwd=REPO, env=env, capture_output=True, text=True, timeout=60)
    elapsed = time.monotonic() - started
    log = result.stdout + result.stderr
    output.write_text(log)
    passed = result.returncode == 0 and " PASS" in log and "SCRIPT ERROR" not in log and "ERROR:" not in log
    if image:
        passed = passed and image.exists() and image.stat().st_size > 1000 and "display=headless" not in log
    print(f"{script}: {'PASS' if passed else 'FAIL'} ({elapsed:.3f}s)", flush=True)
    if not passed:
        print(log, flush=True)
    return {"script": script, "passed": passed, "exit_code": result.returncode, "seconds": elapsed, "log": output.name, "image": image.name if image else None}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--output", type=Path, default=REPO / "docs/verification/character-dossiers")
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--baseline-ref", help="Render the same scene with production files from this Git revision")
    parser.add_argument("--xorg-display", type=int, help="Optional isolated Xorg TCP display when no desktop display exists")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    report: dict = {"kind": "executed production geometry and speech tests; native images are render probes, not full-game acceptance", "tests": [], "sources": {}}
    with tempfile.TemporaryDirectory(prefix="labvolt-facial-") as temporary:
        scratch = Path(temporary)
        project = scratch / "current"
        report["sources"]["after"] = prepare(project, TESTS + [RENDER])
        env["XDG_DATA_HOME"] = str(scratch / "user")
        for test in TESTS:
            report["tests"].append(run(args.godot, project, test, args.output / (Path(test).stem + ".log"), env))
        server = None
        try:
            if args.native:
                if args.xorg_display is not None:
                    if not shutil.which("Xorg"):
                        raise RuntimeError("Requested Xorg is not installed")
                    server = subprocess.Popen(
                        ["Xorg", f":{args.xorg_display}", "-config", "/etc/X11/xorg.conf", "-noreset", "-ac", "-listen", "tcp", "-nolisten", "unix", "-nolisten", "local", "-logfile", str(scratch / "xorg.log")],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
                    env["DISPLAY"] = f"127.0.0.1:{args.xorg_display}"
                    env["LIBGL_ALWAYS_SOFTWARE"] = "1"
                    time.sleep(1)
                    if server.poll() is not None:
                        raise RuntimeError("Xorg could not start; no rendered result was accepted")
                if args.baseline_ref:
                    baseline = scratch / "baseline"
                    report["baseline_ref"] = args.baseline_ref
                    report["sources"]["before"] = prepare(baseline, [RENDER], args.baseline_ref)
                    report["tests"].append(run(args.godot, baseline, RENDER, args.output / "facial-before.log", env, True, args.output / "facial-before.png"))
                report["tests"].append(run(args.godot, project, RENDER, args.output / "facial-after.log", env, True, args.output / "facial-after.png"))
        finally:
            if server is not None:
                server.terminate()
                server.wait(timeout=5)
    report["passed"] = all(test["passed"] for test in report["tests"])
    (args.output / "facial-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
