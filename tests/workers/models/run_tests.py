"""Run only local, non-network model tests with isolated Godot user directories."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("--runtime", default=r"C:\Users\User1\Documents\GodotProjects\LabVolt_Practice_Simulator\runtime\Godot_v4.5.1-stable_win64_console.exe")
parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[3])
parser.add_argument("--work", type=Path)
args = parser.parse_args()
project = args.project.resolve()
work = (args.work or project.parent / "work").resolve() / ("model-tests-" + uuid.uuid4().hex)
work.mkdir(parents=True)
env = os.environ.copy()
for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP"):
    folder = work / key.lower()
    folder.mkdir()
    env[key] = str(folder)
suites = ["tests/workers/models/test_models.gd", "tests/electronics/test_stateful.gd", "tests/electronics/test_bjt.gd", "tests/electronics/test_opamp.gd", "tests/electronics/test_shift_register.gd"]
failed = False
for suite in suites:
    log = work / (Path(suite).stem + ".log")
    command = [args.runtime, "--headless", "--path", str(project), "--script", "res://" + suite, "--log-file", str(log)]
    result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=90)
    output = result.stdout + result.stderr
    (work / (Path(suite).stem + ".console.txt")).write_text(output, encoding="utf-8")
    errors = re.findall(r"(?:SCRIPT ERROR:|ERROR:|FAIL(?:URES)?[: ]).*", output)
    errors = [line for line in errors if "Failed to read the root certificate store" not in line and not re.search(r"FAILURES: 0$", line)]
    ok = result.returncode == 0 and not errors
    if suite.endswith("test_models.gd"):
        ok = ok and re.search(r"MODELS: \d+ checks, 0 failures", output) is not None
    failed |= not ok
    print(("PASS " if ok else "FAIL ") + suite)
    if not ok:
        print(output)
print("Logs: " + str(work))
raise SystemExit(1 if failed else 0)
