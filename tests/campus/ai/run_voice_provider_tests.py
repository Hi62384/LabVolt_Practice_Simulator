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
        for script in ["test_model_catalog.gd","test_streaming_transcription.gd","test_catalog_voice_http.gd","test_voice_provider_protocol.gd","test_npc_live_bridge.gd"]:
            result=subprocess.run([args.godot,"--headless","--path",str(repo),"--script","res://tests/campus/ai/"+script],env=env,timeout=45)
            code=max(code,result.returncode)
        stats=urllib.request.urlopen(f"http://127.0.0.1:{port}/stats",timeout=1).read().decode()
        print("Fixture observations:",stats)
        raise SystemExit(code)
    finally:
        fixture.terminate()
        try:fixture.wait(timeout=3)
        except subprocess.TimeoutExpired:fixture.kill();fixture.wait()
