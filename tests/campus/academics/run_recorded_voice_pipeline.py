"""Exercise the opt-in voice-acceptance harness against authored local providers.

Intelligible speech fixtures traverse actual AudioServer capture and NPC routing.
Provider outputs are authored; this does not verify live recognition or quality.
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
from http.server import ThreadingHTTPServer


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[3]
    spec=importlib.util.spec_from_file_location("voice_acceptance_fixture", repo/"tests/campus/ai/openai_fixture_server.py")
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    manifest=json.loads((Path(__file__).with_name("voice_fixtures")/"manifest.json").read_text())

    class Handler(module.Handler):
        transcriptions=0
        prior_nickname_seen=False
        def do_POST(self):
            if self.path=="/v1/audio/transcriptions":
                raw=self.rfile.read(int(self.headers.get("Content-Length",0)))
                if not self._authorized() or b"RIFF" not in raw or b"WAVE" not in raw:
                    return self._reply(400,{"error":{"message":"Invalid recorded fixture upload"}})
                index=type(self).transcriptions
                type(self).transcriptions+=1
                if index>=len(manifest["fixtures"]):
                    return self._reply(429,{"error":{"message":"Unexpected duplicate transcription"}})
                return self._reply(200,{"text":manifest["fixtures"][index]["text"]})
            return super().do_POST()
        @classmethod
        def _character_details(cls,body,character_input,speech):
            request=character_input["player_dialogue"].lower()
            if "please remember" in request:speech="Copper Comet. I will remember that project nickname."
            elif "what is my project nickname" in request:
                cls.prior_nickname_seen="copper comet" in json.dumps(character_input["context"]).lower()
                speech="Your project nickname is Copper Comet."
            else:speech="Voltage is a difference in electric potential, and current is the rate of charge flow."
            return super()._character_details(body,character_input,speech)

    server=ThreadingHTTPServer(("127.0.0.1",0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        env=dict(os.environ);env.pop("OPENAI_API_KEY",None)
        process=subprocess.run([sys.executable,str(Path(__file__).with_name("run_voice_acceptance.py")),
            "--godot",args.godot,"--output",str(args.output),"--headless","--turns","3",
            "--fixture-port",str(server.server_address[1])],env=env,timeout=210)
        report=json.loads((args.output/"result.json").read_text())
        checks={"status":report.get("status")=="fixture_pipeline_pass",
                "one_transcription_per_turn":Handler.transcriptions==3,
                "prior_nickname_in_actual_context":Handler.prior_nickname_seen,
                "resources_released":report.get("resources_released",False),
                "no_live_provider":report.get("provider_requests") is False}
        (args.output/"fixture_checks.json").write_text(json.dumps(checks,indent=2)+"\n")
        print("RECORDED_VOICE_PIPELINE", "PASS" if all(checks.values()) and process.returncode==0 else "FAIL",json.dumps(checks))
        return 0 if all(checks.values()) and process.returncode==0 else 1
    finally:
        server.shutdown();server.server_close();thread.join(timeout=3)


if __name__=="__main__":raise SystemExit(main())
