"""Light, source-only unit suites. No editor import, renderer or multiplayer.

The integrator runs this with its existing trusted Godot runtime; no user setup.
Every SCRIPT ERROR and unexpected ERROR is a failure regardless of exit status.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--godot')
    parser.add_argument('--samples',type=int,default=20)
    parser.add_argument('--logs',type=Path)
    args=parser.parse_args()
    project=Path(__file__).resolve().parents[2]
    logs=(args.logs or project.parent/'work'/'mth147-tests').resolve();logs.mkdir(parents=True,exist_ok=True)
    runtime=args.godot or shutil.which('godot') or shutil.which('godot4')
    if not runtime:
        candidate=Path.home()/'Documents/GodotProjects/LabVolt_Practice_Simulator/runtime/Godot_v4.5.1-stable_win64_console.exe'
        if candidate.is_file():runtime=str(candidate)
    if not runtime:raise SystemExit('Trusted existing Godot runtime not found; integrator supplies --godot. No download attempted.')
    env=os.environ.copy()
    for key,name in [('APPDATA','Roaming'),('LOCALAPPDATA','Local')]:
        folder=logs/'isolated-runtime'/name;folder.mkdir(parents=True,exist_ok=True);env[key]=str(folder)
    results=[]
    for script,marker in [('test_core.gd','CORE_CHECKS'),('test_behaviour.gd','BEHAVIOUR_CHECKS'),('test_projection.gd','PROJECTION_CHECKS'),('test_generation.gd','GENERATION_CASES')]:
        command=[runtime,'--headless','--path',str(project),'--script','res://tests/mth147/'+script,'--log-file',str(logs/(script+'.engine.log'))]
        preflight=subprocess.run(command+['--check-only'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30)
        (logs/(script+'.preflight.log')).write_text(preflight.stdout,encoding='utf-8')
        preflight_errors=[line for line in preflight.stdout.splitlines() if 'ERROR:' in line and line.strip()!='ERROR: Failed to read the root certificate store.']
        if preflight.returncode or preflight_errors:
            results.append({'suite':script,'ok':False,'summary':'Compilation preflight failed','errors':preflight_errors});print('FAIL compile',script,preflight.stdout,flush=True);continue
        if script=='test_generation.gd':command+=['--',str(max(1,min(100,args.samples)))]
        try:
            completed=subprocess.run(command,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=420)
            output=completed.stdout;code=completed.returncode
        except subprocess.TimeoutExpired as exc:
            output=(exc.stdout or b'').decode(errors='replace') if isinstance(exc.stdout,bytes) else str(exc.stdout or '')
            output+='\nHARNESS TIMEOUT';code=-1
        (logs/(script+'.log')).write_text(output,encoding='utf-8')
        # This environment emits a Windows certificate-store initialization warning.
        errors=[line for line in output.splitlines() if ('ERROR:' in line and line.strip()!='ERROR: Failed to read the root certificate store.') or line.startswith('FAIL ') or 'HARNESS TIMEOUT' in line]
        ok=code==0 and marker in output and 'FAILURES 0' in output and not errors
        summary=next((line for line in output.splitlines() if line.startswith(marker)),output[-500:])
        results.append({'suite':script,'ok':ok,'exit':code,'summary':summary,'certificate_store_warning':'Failed to read the root certificate store.' in output,'errors':errors})
        print(summary,flush=True)
    fixture=project/'tests/mth147/generated-fixtures.jsonl'
    oracle=subprocess.run([sys.executable,str(project/'tests/mth147/independent_oracle.py'),str(fixture)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    (logs/'independent-oracle.log').write_text(oracle.stdout,encoding='utf-8')
    results.append({'suite':'independent_oracle.py','ok':oracle.returncode==0 and 'FAILURES 0' in oracle.stdout,'summary':oracle.stdout.strip()})
    print(oracle.stdout,flush=True)
    (logs/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    return 0 if all(row['ok'] for row in results) else 1
if __name__=='__main__':raise SystemExit(main())
