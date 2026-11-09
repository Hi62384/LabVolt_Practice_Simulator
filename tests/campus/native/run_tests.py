"""Native programming regressions; no export, networking or player-code compiler."""
import argparse, pathlib, subprocess, os, sys
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--node',required=True);p.add_argument('--logs',required=True);p.add_argument('--render',action='store_true');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[3];logs=pathlib.Path(a.logs).resolve();logs.mkdir(parents=True,exist_ok=True)
cases=[('timing',[a.node,str(root/'tests/campus/native/test_timing.cjs')]),('programming',[a.godot,'--headless','--path',str(root),'--script','res://tests/campus/native/test_programming.gd'])]
if a.render:cases.append(('render',[a.godot,'--path',str(root),'--script','res://tests/campus/native/test_ui_render.gd']))
failed=0
for name,command in cases:
 env=dict(os.environ,APPDATA=str(logs/(name+'-appdata')),LABVOLT_NATIVE_CAPTURE=str(logs/'native-ui.png'))
 pathlib.Path(env['APPDATA']).mkdir(exist_ok=True)
 run=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env,timeout=40,encoding='utf-8',errors='replace')
 (logs/(name+'.log')).write_text(run.stdout,encoding='utf-8');(logs/(name+'-command.txt')).write_text(subprocess.list2cmdline(command),encoding='utf-8')
 errors=[line for line in run.stdout.splitlines() if line.startswith('ERROR:') and line!='ERROR: Failed to read the root certificate store.']
 bad=bool(run.returncode or errors or any(marker in run.stdout for marker in ['SCRIPT ERROR','Parse Error','FAIL ']))
 failed+=bad;print(('FAIL ' if bad else 'PASS ')+name)
sys.exit(bool(failed))
