"""Run classroom reconnect checks over real loopback ENet with isolated saves."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[3]
BUNDLED = (
    ROOT / "runtime" / "Godot_v4.5.1-stable_mono_win64"
    / "Godot_v4.5.1-stable_mono_win64_console.exe"
)
FIXTURES = {
    "events": (
        "test_classroom_events_network.gd", "CLASSROOM_RPC_HOST_READY",
        "CLASSROOM_RPC_HOST PASS", "CLASSROOM_RPC_CLIENT PASS",
    ),
    "live-events": (
        "test_classroom_event_rejoin_network.gd", "EVENT_REJOIN_HOST_READY",
        "EVENT_REJOIN_HOST PASS", "EVENT_REJOIN_CLIENT PASS",
    ),
    "assignment": (
        "test_room_assignment_rejoin.gd", "PAPER_REJOIN_HOST_READY",
        "PAPER_REJOIN_HOST PASS", "PAPER_REJOIN_CLIENT PASS",
    ),
}


def run_pair(godot, fixture):
    script, ready_marker, *pass_markers = FIXTURES[fixture]
    with tempfile.TemporaryDirectory(prefix="classroom-network-", dir=ROOT / ".godot",
                                     ignore_cleanup_errors=True) as work:
        peers = []
        try:
            for role in ("host", "client"):
                appdata = Path(work) / role
                appdata.mkdir()
                log = Path(work) / f"{role}.log"
                with log.open("w", encoding="utf-8") as output:
                    process = subprocess.Popen(
                        [str(godot), "--headless", "--path", str(ROOT), "--script",
                         f"res://tests/campus/academics/{script}", "--", role],
                        cwd=ROOT, env={**os.environ, "APPDATA": str(appdata)},
                        stdout=output, stderr=subprocess.STDOUT,
                    )
                peers.append((process, log))
                if role == "host":
                    ready_by = time.monotonic() + 90
                    while (time.monotonic() < ready_by and process.poll() is None
                           and ready_marker not in log.read_text(encoding="utf-8", errors="replace")):
                        time.sleep(.1)
                    if ready_marker not in log.read_text(encoding="utf-8", errors="replace"):
                        print(f"{fixture}: host did not become ready", flush=True)
                        return False
            deadline = time.monotonic() + 120
            for process, _ in peers:
                process.wait(timeout=max(.1, deadline - time.monotonic()))
            ok = True
            for (process, log), marker in zip(peers, pass_markers):
                content = log.read_text(encoding="utf-8", errors="replace")
                ok = ok and process.returncode == 0 and marker in content and "SCRIPT ERROR" not in content
            return ok
        except subprocess.TimeoutExpired:
            print(f"{fixture}: peer timed out", flush=True)
            return False
        finally:
            for process, log in peers:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                print(f"{fixture} {log.stem}: exit {process.returncode}", flush=True)
                print(log.read_text(encoding="utf-8", errors="replace"), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixtures", nargs="*", metavar="FIXTURE",
                        help=f"Choose from {', '.join(FIXTURES)} (default: events).")
    args = parser.parse_args()
    fixtures = args.fixtures or ["events"]
    for fixture in fixtures:
        if fixture not in FIXTURES:
            parser.error(f"Unknown fixture: {fixture}")
    godot = Path(os.environ.get("GODOT", str(BUNDLED)))
    if not godot.is_file():
        parser.error(f"Godot runtime missing: {godot}")
    (ROOT / ".godot").mkdir(exist_ok=True)
    results = [run_pair(godot, fixture) for fixture in fixtures]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
