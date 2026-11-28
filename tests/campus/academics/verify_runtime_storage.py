#!/usr/bin/env python3
"""Run a game/test command with isolated saves and detect repository writes.

Run after asset import and managed build. Pass the actual executable and args
after ``--``. No provider call is added by this wrapper; the supplied command
determines the workload. Keep other editors/builds stopped during the check.

Example:
  python tests/campus/academics/verify_runtime_storage.py --output /tmp/storage-check -- \
    /path/to/Godot_mono --headless --path . \
    --script res://tests/campus/academics/test_student_population_portable.gd

On Windows the same wrapper can launch an exported LabVolt.exe from a separate
install folder. It reports the actual command's exit code, save-file names and
content-hash differences; it never infers successful gameplay from a clean Git
status. Arguments, environment values, file contents and API keys are not logged.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def git_paths(repository: Path, *arguments: str) -> list[str]:
    result = subprocess.run(["git", "-C", str(repository), "ls-files", "-z", *arguments],
                            check=True, stdout=subprocess.PIPE)
    return [os.fsdecode(value) for value in result.stdout.split(b"\0") if value]


def fingerprint(path: Path) -> str:
    if path.is_symlink():
        return "symlink:" + hashlib.sha256(os.readlink(path).encode()).hexdigest()
    if not path.is_file():
        return "missing"
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=float, default=300.)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("Supply the exact game/test command after --")
    repository = args.project.resolve()
    output = (args.output or Path(tempfile.mkdtemp(prefix="labvolt-runtime-storage-"))).resolve()
    if output.is_relative_to(repository):
        parser.error("Keep verification output outside the repository being checked")
    output.mkdir(parents=True, exist_ok=True)
    save_root = output / "isolated-user-data"
    save_root.mkdir(exist_ok=True)
    tracked = git_paths(repository)
    before = {name: fingerprint(repository / name) for name in tracked}
    untracked_before = set(git_paths(repository, "--others", "--exclude-standard"))
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(save_root), APPDATA=str(save_root), LOCALAPPDATA=str(save_root))
    started = time.monotonic()
    timed_out = False
    with (output / "runtime.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=repository, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            exit_code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.terminate()
            try:
                exit_code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                exit_code = process.wait(timeout=5)
    modified = [name for name, digest in before.items() if fingerprint(repository / name) != digest]
    created = sorted(set(git_paths(repository, "--others", "--exclude-standard")) - untracked_before)
    new_tracked = sorted(set(git_paths(repository)) - set(tracked))
    text = (output / "runtime.log").read_text(encoding="utf-8", errors="replace")
    expected_cef = {
        "ERROR: No GDExtension library found for current OS and architecture (linux.x86_64) in configuration file: res://cef_artifacts/gdcef.gdextension",
        "ERROR: GDExtension dynamic library not found: 'res://cef_artifacts/gdcef.gdextension'.",
        "ERROR: Error loading extension: 'res://cef_artifacts/gdcef.gdextension'.",
    } if sys.platform.startswith("linux") else set()
    errors = [line for line in text.splitlines() if line.startswith(("ERROR:", "SCRIPT ERROR:")) and line not in expected_cef]
    report = {
        "repository_unchanged": not modified and not created and not new_tracked,
        "command_exit_code": exit_code,
        "timed_out": timed_out,
        "unexpected_engine_errors": len(errors),
        "expected_windows_only_cef_messages": sum(line in expected_cef for line in text.splitlines()),
        "duration_seconds": round(time.monotonic() - started, 3),
        "tracked_files_checked": len(tracked),
        "modified_tracked_paths": modified,
        "new_untracked_paths": created,
        "new_tracked_paths": new_tracked,
        "isolated_save_files": sorted(str(path.relative_to(save_root)) for path in save_root.rglob("*") if path.is_file()),
        "scope": "Content hashes of tracked files and newly untracked files; ignored engine build/import caches are outside the runtime-data assertion.",
        "hardware_or_provider_verified": False,
    }
    (output / "storage-report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    passed = report["repository_unchanged"] and exit_code == 0 and not timed_out and not errors
    print(json.dumps({"passed": passed, "repository_unchanged": report["repository_unchanged"],
                      "save_files": len(report["isolated_save_files"]), "report": str(output / "storage-report.json")}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
