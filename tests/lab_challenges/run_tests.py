"""Light source-only tests; no editor import, rendered or multiprocess launch."""
import argparse,os,pathlib,subprocess
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--project',default='.');p.add_argument('--logs',required=True);a=p.parse_args()
logs=pathlib.Path(a.logs).resolve();logs.mkdir(parents=True,exist_ok=True);env=os.environ.copy()
for key,folder in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
 path=logs/folder;path.mkdir(exist_ok=True);env[key]=str(path)
for name,marker in [('test_scenarios','BASE_SCENARIOS_RESULT'),('test_host','BASE_HOST_RESULT'),('test_presentation','BASE_PRESENTATION_RESULT'),('test_hooks','BASE_HOOKS_RESULT'),('test_composition','BASE_COMPOSITION_RESULT')]:
 log=logs/(name+'.log')
 with log.open('w',encoding='utf-8') as out:
  process=subprocess.Popen([a.godot,'--headless','--path',str(pathlib.Path(a.project).resolve()),'--script','res://tests/lab_challenges/'+name+'.gd'],env=env,stdout=out,stderr=subprocess.STDOUT)
  try:code=process.wait(timeout=30)
  except subprocess.TimeoutExpired:process.kill();process.wait();code=-1
 text=log.read_text(encoding='utf-8');errors=[s for s in text.splitlines() if ('SCRIPT ERROR' in s or 'Parse Error' in s or s.startswith('ERROR:')) and 'Failed to read the root certificate store.' not in s];result=next((s for s in text.splitlines() if s.startswith(marker)),None)
 if code or errors or result is None or 'failures=0' not in result:raise RuntimeError(f'{name} failed code={code} errors={errors}; inspect {log}')
 print(result)
print('All requested base challenge light tests passed. Certificate-store environment messages remain in raw logs.')
