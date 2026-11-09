"""Source-only UI tests. --rendered requires a coordinated graphical test window."""
import argparse, os, pathlib, subprocess, time
parser=argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--project', default='.')
parser.add_argument('--logs',required=True)
parser.add_argument('--network',action='store_true')
parser.add_argument('--rendered',action='store_true')
args=parser.parse_args()
logs=pathlib.Path(args.logs).resolve(); logs.mkdir(parents=True,exist_ok=True)
env=os.environ.copy()
artifacts=logs/"artifacts";artifacts.mkdir(exist_ok=True);env["LABVOLT_UI_ARTIFACTS"]=str(artifacts)
for name,folder in [('APPDATA','appdata'),('LOCALAPPDATA','localappdata')]:
 p=logs/folder;p.mkdir(exist_ok=True);env[name]=str(p)
base=[args.godot,'--path',str(pathlib.Path(args.project).resolve())]
def valid(name,text,rc,marker):
 errors=[line for line in text.splitlines() if ('SCRIPT ERROR' in line or 'Parse Error' in line or line.startswith('ERROR:')) and 'Failed to read the root certificate store.' not in line]
 if rc or errors or marker not in text: raise RuntimeError(f'{name} failed rc={rc} errors={errors}; see {logs/name}')
 print(name,marker)
def run(script,marker,rendered=False):
 cmd=base+([] if rendered else ['--headless'])+['--script','res://tests/campus/ui/'+script+'.gd']
 proc=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=45)
 text=proc.stdout+proc.stderr;(logs/(script+'.log')).write_text(text,encoding='utf-8');valid(script,text,proc.returncode,marker)
run('test_ui','UI_TEST_RESULT failures=0')
run('test_dashboard','UI_DASHBOARD_INTERACTION_RESULT failures=0')
if args.network:
 processes=[]
 try:
  for role in ['server','client']:
   file=open(logs/('network-'+role+'.log'),'w',encoding='utf-8')
   cmd=base+['--headless','--script','res://tests/campus/ui/test_network.gd','--',role]
   process=subprocess.Popen(cmd,env=env,stdout=file,stderr=subprocess.STDOUT);processes.append((role,process,file));time.sleep(.4)
  for role,process,file in processes:
   rc=process.wait(timeout=20);file.close();text=(logs/('network-'+role+'.log')).read_text(encoding='utf-8');valid('network-'+role,text,rc,'UI_NETWORK_'+('HOST' if role=='server' else 'CLIENT')+'_PASS')
 finally:
  for role,process,file in processes:
   if process.poll() is None:process.kill();process.wait()
   if not file.closed:file.close()
if args.rendered:
 run('test_dashboard','UI_DASHBOARD_INTERACTION_RESULT failures=0',True)
 run('test_graphics_rendered','UI_GRAPHICS_RENDERED_RESULT failures=0',True)
print('All requested UI tests passed. Environmental certificate-store messages, if any, remain in logs.')
