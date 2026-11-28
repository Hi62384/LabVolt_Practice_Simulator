"""Run opt-in microphone/recorded/NPC voice acceptance with isolated saved data.

No credentials are accepted as command-line arguments or stored in reports.
Use OPENAI_API_KEY in the child process environment with --live for provider
verification. --capture-only exercises AudioServer capture without any API call.
"""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import tempfile
import time
from run_character_regressions import run_one


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--source", choices=("fixtures", "microphone"), default="fixtures")
    parser.add_argument("--device", default="Default")
    parser.add_argument("--seconds", type=float, default=6)
    parser.add_argument("--turns", type=int, choices=(1, 2, 3), default=2)
    parser.add_argument("--teacher", choices=("mr_bro", "dr_volts"), default="mr_bro")
    parser.add_argument("--text-model", default="")
    parser.add_argument("--stt-model", default="")
    parser.add_argument("--tts-model", default="")
    parser.add_argument("--live", action="store_true", help="Authorize actual provider requests for this diagnostic")
    parser.add_argument("--capture-only", action="store_true")
    parser.add_argument("--stt-only", action="store_true")
    parser.add_argument("--load-only", action="store_true")
    parser.add_argument("--fixture-port", type=int, help="Editor-only loopback fixture; never reports real provider verification")
    parser.add_argument("--headless", action="store_true", help="Only for fixtures/load checks; never claims physical capture or audible output")
    args = parser.parse_args()
    if args.capture_only and args.stt_only:
        parser.error("Choose capture-only or stt-only, not both")
    if not 3 <= args.seconds <= 30:
        parser.error("Recording length must be 3–30 seconds")
    if args.source == "microphone" and args.headless and not args.load_only:
        parser.error("Physical microphone verification requires a native audio/window driver")
    if args.fixture_port is not None and (not 1024 <= args.fixture_port <= 65535 or args.live):
        parser.error("A loopback fixture needs a valid high port and cannot be combined with --live")
    repo = Path(__file__).resolve().parents[3]
    output = (args.output or Path(tempfile.mkdtemp(prefix="labvolt-voice-acceptance-"))).resolve()
    if output == repo or repo in output.parents:
        parser.error("Choose an output directory outside the source repository")
    output.mkdir(parents=True, exist_ok=True)
    profile = output / "isolated-user-data"
    env = dict(os.environ, XDG_DATA_HOME=str(profile), APPDATA=str(profile),
               LABVOLT_ACCEPTANCE_SOURCE=args.source, LABVOLT_ACCEPTANCE_DEVICE=args.device,
               LABVOLT_ACCEPTANCE_SECONDS=str(args.seconds), LABVOLT_ACCEPTANCE_TURNS=str(args.turns),
               LABVOLT_ACCEPTANCE_TEACHER=args.teacher, LABVOLT_ACCEPTANCE_TEXT_MODEL=args.text_model,
               LABVOLT_ACCEPTANCE_STT_MODEL=args.stt_model, LABVOLT_ACCEPTANCE_TTS_MODEL=args.tts_model,
               LABVOLT_ACCEPTANCE_LIVE="1" if args.live else "0",
               LABVOLT_ACCEPTANCE_CAPTURE_ONLY="1" if args.capture_only else "0",
               LABVOLT_ACCEPTANCE_STT_ONLY="1" if args.stt_only else "0",
               LABVOLT_ACCEPTANCE_LOAD_ONLY="1" if args.load_only else "0")
    env.pop("LABVOLT_ACCEPTANCE_FIXTURE_PORT", None)
    if args.fixture_port is not None:env["LABVOLT_ACCEPTANCE_FIXTURE_PORT"]=str(args.fixture_port)
    if args.capture_only or args.load_only or args.fixture_port is not None:
        env.pop("OPENAI_API_KEY", None)
    cmd = [args.godot]
    if args.headless:cmd.append("--headless")
    else:cmd += ["--rendering-method", "gl_compatibility"]
    cmd += ["--path", str(repo), "--script", "res://tests/campus/academics/verify_voice_acceptance.gd"]
    started = time.monotonic()
    executed = run_one(cmd, env, 1100)
    log, code = executed["output"], executed["exit_code"]
    (output / "engine.log").write_text(log, encoding="utf-8")
    reports = list(profile.rglob("voice-acceptance.json"))
    evidence = json.loads(reports[-1].read_text(encoding="utf-8")) if reports else {"status":"no_report"}
    evidence.update(exit_code=code, elapsed_seconds=round(time.monotonic()-started, 3))
    if "SCRIPT ERROR:" in log or "Parse Error:" in log:
        evidence["status"]="script_error";code=1
    (output / "result.json").write_text(json.dumps(evidence, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))
    print("Evidence:", output)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
