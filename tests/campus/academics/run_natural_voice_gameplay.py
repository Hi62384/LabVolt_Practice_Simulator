"""Exercise real scene voice turns with synthetic PCM and a loopback HTTP provider.

A different authored response per turn prevents the character repetition guard
from correctly rejecting the old fixture's one constant response. This test
never uses a real provider key, microphone device or recording of a person.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from http.server import ThreadingHTTPServer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    path = repo / "tests/campus/ai/openai_fixture_server.py"
    spec = importlib.util.spec_from_file_location("voice_http_fixture", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    class TurnHandler(module.Handler):
        turn = 0
        responses = (
            "The board shows a current path.",
            "Current follows the connected conductors around this closed circuit.",
            "Increasing resistance reduces current when the voltage stays constant.",
            "An ammeter measures the current flowing through its branch.",
            "Voltage describes the difference in electric potential between two points.",
            "A complete loop allows charge to move through the load.",
        )

        @classmethod
        def _character_details(cls, body, character_input, speech):
            with cls.request_lock:
                speech = cls.responses[cls.turn % len(cls.responses)]
                cls.turn += 1
            return super()._character_details(body, character_input, speech)

    server = ThreadingHTTPServer(("127.0.0.1", 0), TurnHandler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    try:
        with tempfile.TemporaryDirectory(prefix="labvolt_turn_voice_") as user:
            env = dict(os.environ, XDG_DATA_HOME=user, APPDATA=user,
                       LABVOLT_OPENAI_FIXTURE_PORT=str(server.server_address[1]))
            env.pop("OPENAI_API_KEY", None)
            result = subprocess.run(
                [args.godot, "--headless", "--path", str(repo), "--script",
                 "res://tests/campus/academics/test_natural_voice_gameplay.gd"],
                env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace", timeout=90,
            )
            log = repo / ".godot/test_logs/natural_voice_gameplay.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text(result.stdout, encoding="utf-8")
            lines = result.stdout.splitlines()
            print("\n".join(lines if len(lines) <= 180 else lines[:80] + ["... repeated engine output omitted; complete log: " + str(log)] + lines[-20:]), flush=True)
            return 1 if (result.returncode or "SCRIPT ERROR:" in result.stdout
                         or "NATURAL_VOICE_GAMEPLAY PASS" not in result.stdout) else 0
    finally:
        server.shutdown()
        server.server_close()
        worker.join(timeout=3)


if __name__ == "__main__":
    raise SystemExit(main())
