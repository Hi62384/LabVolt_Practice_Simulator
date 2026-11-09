"""One graphical correctness fixture; requires a fresh coordinator lease."""
import argparse,pathlib,os,subprocess
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--project',default='.');p.add_argument('--logs',required=True);a=p.parse_args();logs=pathlib.Path(a.logs).resolve();logs.mkdir(parents=True,exist_ok=True);env=os.environ.copy()
for key,folder in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('LAB_CHALLENGE_ARTIFACTS','artifacts')]:
 path=logs/folder;path.mkdir(exist_ok=True);env[key]=str(path)
log=logs/'rendered.log'
with log.open('w',encoding='utf-8') as output:
 process=subprocess.Popen([a.godot,'--path',str(pathlib.Path(a.project).resolve()),'--script','res://tests/lab_challenges/test_rendered.gd'],env=env,stdout=output,stderr=subprocess.STDOUT)
 try:code=process.wait(timeout=30)
 except subprocess.TimeoutExpired:process.kill();process.wait();code=-1
text=log.read_text(encoding='utf-8');errors=[s for s in text.splitlines() if ('SCRIPT ERROR' in s or 'Parse Error' in s or s.startswith('ERROR:')) and 'Failed to read the root certificate store.' not in s]
if code or errors or 'BASE_RENDERED_RESULT failures=0 captures=2' not in text:raise RuntimeError(f'Rendered check failed code={code} errors={errors}; inspect {log}')
print('BASE_RENDERED_RESULT failures=0 captures=2; inspect saved images offline. Window process exited.')
