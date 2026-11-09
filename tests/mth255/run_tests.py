"""Source-only MTH255 validation. Invoke against an integrated source checkout, never an export."""
import argparse,hashlib,json,os,pathlib,subprocess,sys,tempfile,time
SCRIPTS=['test_domains.gd','test_projection.gd','test_widgets.gd','test_preparer.gd','test_course_flow.gd','test_provider.gd','emit_samples.gd']
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--godot',required=True);parser.add_argument('--project',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[2]);parser.add_argument('--logs',type=pathlib.Path);args=parser.parse_args()
 project=args.project.resolve();logs=(args.logs or pathlib.Path(tempfile.mkdtemp(prefix='mth255-tests-'))).resolve();logs.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy()
 for key,folder in [('APPDATA','Roaming'),('LOCALAPPDATA','Local')]:
  destination=logs/'isolated-userdata'/folder;destination.mkdir(parents=True,exist_ok=True);env[key]=str(destination)
 result_rows=[];failed=False
 for script in SCRIPTS:
  command=[str(pathlib.Path(args.godot).resolve()),'--headless','--path',str(project),'--script','res://tests/mth255/'+script]
  if script=='emit_samples.gd':command+=['--',str(logs/'samples.jsonl')]
  start=time.monotonic();result=subprocess.run(command,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=55);text=result.stdout;filtered=text.replace('ERROR: Failed to read the root certificate store.','');ok=result.returncode==0 and 'SCRIPT ERROR' not in text and 'ERROR:' not in filtered and 'FAIL ' not in text
  (logs/(script+'.log')).write_text(text,encoding='utf-8');result_rows.append({'script':script,'ok':ok,'exit':result.returncode,'seconds':round(time.monotonic()-start,3)});failed|=not ok;print(script,'PASS' if ok else 'FAIL',flush=True)
 if (logs/'samples.jsonl').exists():
  result=subprocess.run([sys.executable,str(project/'tests/mth255/independent_oracle.py'),str(logs/'samples.jsonl')],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=55);(logs/'independent-oracle.log').write_text(result.stdout,encoding='utf-8');ok=result.returncode==0;result_rows.append({'script':'independent_oracle.py','ok':ok,'exit':result.returncode});failed|=not ok;print(result.stdout,flush=True)
 dependencies={}
 for folder in ['scripts/mth147','scripts/math_ui']:
  dependencies[folder]={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((project/folder).glob('*.gd'))}
 dependencies['scripts/ac_network.gd']=hashlib.sha256((project/'scripts/ac_network.gd').read_bytes()).hexdigest()
 (logs/'summary.json').write_text(json.dumps({'source_only':True,'project':str(project),'results':result_rows,'dependency_hashes':dependencies,'owned_hashes':{str(p.relative_to(project)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['scripts/mth255','assets/mth255','tests/mth255'] for p in sorted((project/folder).glob('*')) if p.is_file() and p.suffix in ['.gd','.json','.py']},'complete':not failed,'certificate_store_warning':'retained verbatim; only that exact environment initialization message is excluded from failure detection'},indent=2),encoding='utf-8')
 return 1 if failed else 0
if __name__=='__main__':raise SystemExit(main())
