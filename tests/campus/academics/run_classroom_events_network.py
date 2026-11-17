"""Run the lightweight classroom ENet fixture as two isolated Godot peers."""
import ctypes
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[3]
GODOT = ROOT / "runtime" / "Godot_v4.5.1-stable_win64_console.exe"
SCRIPT = "res://tests/campus/academics/test_classroom_events_network.gd"
MIN_AVAILABLE_MB = 2300
MAX_WAIT_SECONDS = 35


class MemoryStatus(ctypes.Structure):
    _fields_ = [
        ("length", ctypes.c_ulong),
        ("load", ctypes.c_ulong),
        ("total_physical", ctypes.c_ulonglong),
        ("available_physical", ctypes.c_ulonglong),
        ("total_page_file", ctypes.c_ulonglong),
        ("available_page_file", ctypes.c_ulonglong),
        ("total_virtual", ctypes.c_ulonglong),
        ("available_virtual", ctypes.c_ulonglong),
        ("available_extended", ctypes.c_ulonglong),
    ]


def available_mb():
    status = MemoryStatus()
    status.length = ctypes.sizeof(status)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
        raise OSError("Could not read available memory")
    return status.available_physical // (1024 * 1024)


def main():
    if os.name != "nt":
        print("This fixture uses the bundled Windows Godot runtime", file=sys.stderr)
        return 2
    if not GODOT.exists():
        print(f"Godot runtime missing: {GODOT}", file=sys.stderr)
        return 2
    available = available_mb()
    if available < MIN_AVAILABLE_MB:
        print(f"DEFERRED: {available} MiB free; two peers require {MIN_AVAILABLE_MB} MiB", file=sys.stderr)
        return 3
    with tempfile.TemporaryDirectory(prefix="classroom-network-", dir=ROOT / ".godot") as work:
        processes = []
        files = []
        try:
            for role in ("host", "client"):
                appdata = Path(work) / role
                appdata.mkdir()
                output = open(Path(work) / f"{role}.log", "w+", encoding="utf-8")
                files.append(output)
                env = os.environ.copy()
                env["APPDATA"] = str(appdata)
                process = subprocess.Popen(
                    [str(GODOT), "--headless", "--path", str(ROOT), "--script", SCRIPT, "--", role],
                    cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT,
                )
                processes.append((role, process))
                if role == "host":
                    time.sleep(1)
            deadline = time.monotonic() + MAX_WAIT_SECONDS
            while time.monotonic() < deadline and any(p.poll() is None for _, p in processes):
                time.sleep(.2)
            success = True
            for role, process in processes:
                if process.poll() is None:
                    process.terminate()
                    success = False
                process.wait(timeout=5)
                print(f"{role}: exit {process.returncode}")
                if process.returncode != 0:
                    success = False
            for output in files:
                output.flush()
                output.seek(0)
                print(output.read())
            return 0 if success else 1
        finally:
            for _, process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
            for output in files:
                output.close()


if __name__ == "__main__":
    raise SystemExit(main())
