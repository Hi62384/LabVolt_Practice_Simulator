"""Guarded three-peer transport check for classroom whiteboard strokes and text."""
import ctypes
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
GODOT = ROOT / "runtime" / "Godot_v4.5.1-stable_win64_console.exe"
SCRIPT = "res://tests/campus/academics/test_physical_whiteboard_network.gd"
MIN_AVAILABLE_MB = 3000


class MemoryStatus(ctypes.Structure):
    _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong),
               ("total_physical", ctypes.c_ulonglong), ("available_physical", ctypes.c_ulonglong),
               ("total_page_file", ctypes.c_ulonglong), ("available_page_file", ctypes.c_ulonglong),
               ("total_virtual", ctypes.c_ulonglong), ("available_virtual", ctypes.c_ulonglong),
               ("available_extended", ctypes.c_ulonglong)]


def available_mb():
    status = MemoryStatus()
    status.length = ctypes.sizeof(status)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
        raise OSError("Could not read available memory")
    return status.available_physical // (1024 * 1024)


def main():
    if os.name != "nt" or not GODOT.exists():
        print("Bundled Windows Godot runtime required", file=sys.stderr)
        return 2
    free = available_mb()
    if free < MIN_AVAILABLE_MB:
        print(f"DEFERRED: {free} MiB free; two peers require {MIN_AVAILABLE_MB} MiB")
        return 3
    with tempfile.TemporaryDirectory(prefix="physical-board-network-", dir=ROOT / ".godot") as work:
        processes = []
        outputs = []
        try:
            for role in ("host", "client", "observer"):
                appdata = Path(work) / role
                appdata.mkdir()
                log = open(Path(work) / f"{role}.log", "w+", encoding="utf-8")
                outputs.append((role, log))
                env = os.environ.copy()
                env["APPDATA"] = str(appdata)
                proc = subprocess.Popen([str(GODOT), "--headless", "--path", str(ROOT), "--script", SCRIPT, "--", role],
                                        cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
                processes.append((role, proc))
                if role in ("host", "client"):
                    ready_by = time.monotonic() + 10
                    marker = f"PHYSICAL_BOARD_{role.upper()}_READY"
                    while time.monotonic() < ready_by:
                        log.flush()
                        if marker in Path(log.name).read_text(encoding="utf-8"):
                            break
                        if proc.poll() is not None:
                            break
                        time.sleep(.1)
                    else:
                        print("Host readiness timed out")
                        return 1
            deadline = time.monotonic() + 35
            while time.monotonic() < deadline and any(p.poll() is None for _, p in processes):
                time.sleep(.2)
            ok = True
            for role, proc in processes:
                if proc.poll() is None:
                    proc.terminate()
                    ok = False
                proc.wait(timeout=5)
                print(f"{role}: exit {proc.returncode}")
                ok = ok and proc.returncode == 0
            for role, log in outputs:
                log.flush(); log.seek(0)
                content = log.read()
                ok = ok and f"PHYSICAL_BOARD_{role.upper()} PASS" in content and "SCRIPT ERROR" not in content
                if len(content) > 12000:
                    content = content[:4000] + "\n... log truncated ...\n" + content[-8000:]
                print(f"{role} log:\n{content}")
            return 0 if ok else 1
        finally:
            for _, proc in processes:
                if proc.poll() is None:
                    proc.kill(); proc.wait()
            for _, log in outputs:
                log.close()


if __name__ == "__main__":
    raise SystemExit(main())
