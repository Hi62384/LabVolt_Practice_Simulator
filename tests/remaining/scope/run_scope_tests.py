"""Source-only scope tests. Use --only-rendered only inside a fresh coordinator lease."""
import argparse, pathlib, os, subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--godot',required=True)
parser.add_argument('--project',default='.')
parser.add_argument('--logs',required=True)
parser.add_argument('--require-integrated',action='store_true',help='Fail if production DCStation lacks scope v2; otherwise proposals are tested in memory only')
parser.add_argument('--only-rendered',action='store_true',help='One graphical control scene; coordinator lease required')
args=parser.parse_args()
logs=pathlib.Path(args.logs).resolve();logs.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
for variable,directory in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata'),('LABVOLT_SCOPE_ARTIFACTS','artifacts')]:
 path=logs/directory;path.mkdir(exist_ok=True);env[variable]=str(path)
scripts=[('test_controls','SCOPE_CONTROLS_RESULT')] if args.only_rendered else [('test_models','SCOPE_MODELS_RESULT'),('test_core','SCOPE_CORE_RESULT'),('test_controls','SCOPE_CONTROLS_RESULT')]
for script,marker in scripts:
 command=[args.godot,'--path',str(pathlib.Path(args.project).resolve())]
 if not args.only_rendered:command+=['--headless']
 command+=['--script','res://tests/remaining/scope/'+script+'.gd']
 if args.require_integrated:command+=['--','require-integrated']
 process=subprocess.run(command,env=env,capture_output=True,text=True,timeout=30)
 output=process.stdout+process.stderr
 (logs/(script+'.log')).write_text(output,encoding='utf-8')
 errors=[line for line in output.splitlines() if ('SCRIPT ERROR' in line or 'Parse Error' in line or line.startswith('ERROR:')) and 'Failed to read the root certificate store.' not in line]
 result=next((line for line in output.splitlines() if line.startswith(marker)),None)
 if process.returncode or errors or result is None or 'failures=0' not in result:raise RuntimeError(f'{script} FAILED rc={process.returncode} errors={errors}; inspect {logs}')
 print(result)
 print('mode: production integrated' if args.require_integrated else 'mode: owned models + in-memory proposed host hooks; core source untouched')
print('Requested scope tests passed. Raw logs retain environmental certificate-store messages if present.')
