"""Render the actual microphone settings at two viewport sizes with isolated data.

Uses an existing native display, or --xorg-display N with the available Linux
Xorg dummy configuration. Software rendering and Dummy audio are not hardware
or audible-output verification. Inspect the emitted PNGs after the assertions.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from run_character_regressions import run_one


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot",required=True)
    parser.add_argument("--output",required=True,type=Path)
    parser.add_argument("--xorg-display",type=int)
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[3]
    output=args.output.resolve();output.mkdir(parents=True,exist_ok=True)
    env=dict(os.environ,XDG_DATA_HOME=str(output/"user"),APPDATA=str(output/"user"),LABVOLT_MIC_RENDER_OUTPUT=str(output))
    env.pop("OPENAI_API_KEY",None)
    display=None
    try:
        if args.xorg_display is not None:
            display=subprocess.Popen(["Xorg",f":{args.xorg_display}","-config","/etc/X11/xorg.conf","-noreset","-ac","-listen","tcp","-nolisten","unix","-nolisten","local","-logfile",str(output/"xorg.log")],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            env.update(DISPLAY=f"127.0.0.1:{args.xorg_display}",LIBGL_ALWAYS_SOFTWARE="1")
            time.sleep(1)
            if display.poll() is not None:raise RuntimeError("Native display unavailable")
        result=run_one([args.godot,"--path",str(repo),"--rendering-method","gl_compatibility","--audio-driver","Dummy","--script","res://tests/campus/academics/render_microphone_settings.gd"],env,110)
        (output/"engine.log").write_text(result.pop("output"),encoding="utf-8")
        result["physical_microphone"]=False;result["audible_output"]=False
        (output/"runner.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
        print(json.dumps(result,indent=2))
        return 0 if result["passed"] else 1
    finally:
        if display is not None:
            display.terminate()
            try:display.wait(timeout=3)
            except subprocess.TimeoutExpired:display.kill();display.wait()


if __name__=="__main__":raise SystemExit(main())
