"""Exercise the real Godot HTTP/WebSocket adapters against a local fixture."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

parser=argparse.ArgumentParser()
parser.add_argument("--godot",default=os.environ.get("GODOT_BIN","godot"))
args=parser.parse_args()
repo=Path(__file__).resolve().parents[3]
with socket.socket() as listener:
    listener.bind(("127.0.0.1",0))
    port=listener.getsockname()[1]
with socket.socket() as listener:
    listener.bind(("127.0.0.1",0))
    network_port=listener.getsockname()[1]
with tempfile.TemporaryDirectory(prefix="labvolt_voice_protocol_") as user_dir:
    fixture=subprocess.Popen([sys.executable,str(Path(__file__).with_name("voice_protocol_fixture.py")),"--port",str(port)],stdout=subprocess.DEVNULL)
    try:
        for attempt in range(100):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/stats",timeout=.2).close()
                break
            except OSError:
                if fixture.poll() is not None:raise RuntimeError("Voice fixture failed to start")
                time.sleep(.05)
        else:raise RuntimeError("Voice fixture did not become ready")
        env=dict(os.environ,XDG_DATA_HOME=user_dir,APPDATA=user_dir,LABVOLT_VOICE_FIXTURE_PORT=str(port),LABVOLT_LIVE_NETWORK_PORT=str(network_port))
        env.pop("OPENAI_API_KEY",None)
        code=0
        cases={
            "test_model_catalog.gd":"MODEL_CATALOG_REGRESSION PASS",
            "test_streaming_transcription.gd":"STREAMING_TRANSCRIPTION_REGRESSION PASS",
            "test_catalog_voice_http.gd":"CATALOG_VOICE_HTTP PASS",
            "test_voice_provider_protocol.gd":"VOICE_PROVIDER_PROTOCOL PASS",
            "test_npc_live_bridge.gd":"NPC_LIVE_BRIDGE PASS",
        }
        for script,marker in cases.items():
            result=subprocess.run([args.godot,"--headless","--path",str(repo),"--script","res://tests/campus/ai/"+script],env=env,timeout=45,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding="utf-8",errors="replace")
            print(result.stdout,flush=True)
            if result.returncode or marker not in result.stdout or "SCRIPT ERROR:" in result.stdout:
                code=1
        stats=urllib.request.urlopen(f"http://127.0.0.1:{port}/stats",timeout=1).read().decode()
        print("Fixture observations:",stats)
        raise SystemExit(code)
    finally:
        fixture.terminate()
        try:fixture.wait(timeout=3)
        except subprocess.TimeoutExpired:fixture.kill();fixture.wait()
