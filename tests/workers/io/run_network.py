"""Independent isolated adapter/ENet test; never starts or edits the live project."""
import os
import pathlib
import subprocess
import sys
import time

project = pathlib.Path(__file__).resolve().parents[3]
workspace = project.parent
runtime = pathlib.Path(r"C:\Users\User1\Documents\GodotProjects\LabVolt_Practice_Simulator\runtime\Godot_v4.5.1-stable_win64_console.exe")
logs = workspace / "work" / "logs"
logs.mkdir(parents=True, exist_ok=True)
processes = []
handles = []

def start(role):
    env = os.environ.copy()
    data = workspace / "work" / ("network-appdata-" + role)
    data.mkdir(parents=True, exist_ok=True)
    env["APPDATA"] = str(data)
    handle = (logs / ("network-" + role + ".log")).open("w", encoding="utf-8")
    handles.append(handle)
    process = subprocess.Popen([str(runtime), "--headless", "--path", str(project),
        "--script", "res://tests/workers/io/network_runner.gd", "--", role],
        cwd=workspace, env=env, stdout=handle, stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NO_WINDOW)
    processes.append(process)
    return process

try:
    host = start("host")
    deadline = time.monotonic() + 10
    while "IO HOST READY" not in (logs / "network-host.log").read_text(encoding="utf-8"):
        if host.poll() is not None or time.monotonic() > deadline:
            raise RuntimeError("Host did not become ready")
        time.sleep(.05)
    client = start("client")
    assert client.wait(timeout=15) == 0, "first client failed"
    late = start("late")
    assert late.wait(timeout=15) == 0, "late client failed"
    assert host.wait(timeout=15) == 0, "host failed"
    print("IO NETWORK: PASS host + client + late client; port 25201")
except Exception as error:
    print("IO NETWORK: FAIL", error)
    sys.exit(1)
finally:
    for process in processes:
        if process.poll() is None:
            process.terminate()  # only a child created by this exact test invocation
            process.wait(timeout=5)
    for handle in handles:
        handle.close()
