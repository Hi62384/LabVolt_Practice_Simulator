"""Run actual Godot HTTP regressions against an isolated loopback fixture.

Example (Godot Mono must have its matching DOTNET_ROOT in the environment):
    python3 tests/campus/ai/run_character_http_tests.py --godot /path/to/godot

Use --project /path/to/a/minimal/test/project when testing the shared scripts
without platform-specific editor extensions. --only-character is useful while
diagnosing this suite. Logs and exact fake request bodies are saved to --output.
This is deterministic transport evidence, not a live OpenAI acceptance test.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer

sys.dont_write_bytecode = True
from openai_fixture_server import Handler


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN") or shutil.which("godot"))
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--port", type=int, default=0, help="0 chooses an unused loopback port")
    parser.add_argument("--only-character", action="store_true")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Pass --godot or set GODOT_BIN")
    output = (args.output or Path(tempfile.mkdtemp(prefix="labvolt-character-http-"))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    tests = [] if args.only_character else ["test_host_openai_client", "test_teacher_ai", "test_openai_evaluation"]
    tests.append("test_character_http_transport")
    summary = {"source": "actual loopback HTTP, authored provider fixture; not live AI", "tests": []}
    try:
        for test in tests:
            env = os.environ.copy()
            env.pop("OPENAI_API_KEY", None)
            env.pop("LABVOLT_TEST_OPENAI_TLS", None)
            env["LABVOLT_OPENAI_FIXTURE_PORT"] = str(server.server_port)
            with tempfile.TemporaryDirectory(prefix=test + "-", dir=output) as userdata:
                env["XDG_DATA_HOME"] = userdata
                command = [args.godot, "--headless", "--path", str(args.project), "--script", f"res://tests/campus/ai/{test}.gd"]
                try:
                    result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90, check=False)
                    text, code = result.stdout, result.returncode
                except subprocess.TimeoutExpired as exc:
                    text = exc.stdout or ""
                    if isinstance(text, bytes):
                        text = text.decode("utf-8", errors="replace")
                    text += "\nHARNESS_TIMEOUT\n"
                    code = 124
            log_path = output / (test + ".log")
            log_path.write_text(text)
            script_errors = bool(re.search(r"SCRIPT ERROR:|Parse Error:|Compile Error:|Parse JSON failed", text))
            passed = code == 0 and not script_errors
            summary["tests"].append({"test": test, "exit_code": code, "passed": passed, "script_errors": script_errors, "log": str(log_path)})
            print(f"{test}: {'PASS' if passed else 'FAIL'} (exit={code}, script_errors={script_errors})", flush=True)
            if not passed:
                print(text[-8000:], flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        with Handler.request_lock:
            (output / "fixture_requests.json").write_text(json.dumps({"source": summary["source"], "requests": Handler.requests}, indent=2))
        (output / "summary.json").write_text(json.dumps(summary, indent=2))
    print(f"HTTP fixture evidence: {output}", flush=True)
    return 0 if all(item["passed"] for item in summary["tests"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
