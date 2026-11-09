"""One-time source-only V11 adaptation; writes exclusively the assigned successor."""
import ast,hashlib,json,shutil
from pathlib import Path
B=Path(r'C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v11_current')
OLD=B.parent/'eight_participants_v10_final_live'
LIVE=Path(r'C:\Users\User1\Documents\GodotProjects\LabVolt_Practice_Simulator')
BASELINE=Path(r'C:\Users\User1\AppData\Local\Temp\labvolt-startup-menu-fixed-1be402c30d5a47fa8a4535d2644f5527\project')
PARSER='CLASSROOM-EIGHT-V11-PARSER1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8')
def edit(name,old,new):
 p=B/name;t=p.read_text(encoding='utf-8');assert old in t,(name,old);p.write_text(t.replace(old,new),encoding='utf-8')

# Preserve historical control records, including prepared PARSER2, without activating them.
for folder in ('plans','root-grants'):
 for p in (OLD/folder).glob('*.json'):
  dest=B/'history'/folder/p.name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
for name in ('FINAL-LIVE-PACKET.json','SOURCE-CACHE-LOCK.json'):
 shutil.copy2(OLD/name,B/'history'/('V10-'+name))

# Freeze the successful imported private baseline, never mutable production imports.
shutil.copytree(BASELINE,B/'project')
for name in ('path_contract.py','admission_contract.py','run_driver.py','run_j.py'):
 p=B/name;t=p.read_text();t=t.replace('CLASSROOM-EIGHT-V10-','CLASSROOM-EIGHT-V11-')
 t=t.replace(str(LIVE).replace('\\','\\\\'),str(B/'project').replace('\\','\\\\'))
 t=t.replace(str(LIVE),str(B/'project'));p.write_text(t,encoding='utf-8')
edit('admission_contract.py',"    name,port,week,kind,previous=row", "    name,port,week,kind,previous=row\n    if type(plan.get('difficulty')) is not int or plan['difficulty']!=0:raise ValueError('exact integer difficulty zero required')")
edit('path_contract.py',"if plan.get('previous_result') is not None or plan.get('answer_fixture') is not None:","if any(plan.get(k) is not None for k in ('parser_result','previous_result','previous_name','answer_fixture')):")
edit('run_driver.py',"if source.is_file():shutil.copy2(source,runtime_project/source.relative_to(overlay))", "if source.is_file():\n                        target=runtime_project/source.relative_to(overlay)\n                        target.parent.mkdir(parents=True,exist_ok=True)\n                        shutil.copy2(source,target)")

# Restore missing reviewed peer implementation as a fixture input, not a runtime baseline.
fixture=OLD.parent/'eight_participants_v7/project/tests/acceptance/classroom_network/mth147_base_peer.gd'
dest=B/'overlay/tests/acceptance/classroom_network/mth147_base_peer.gd';shutil.copy2(fixture,dest)
# Passive submit observer inserted into CURRENT baseline source, with exact preimage pin.
source=B/'project/scripts/school_session.gd';raw=source.read_bytes();text=raw.decode();nl='\r\n' if '\r\n' in text else '\n'
changes=[('extends Node','extends Node'+nl+'signal assessment_submit_observed(observation: Dictionary)'),('\t\t\t"submit":','\t\t\t"submit":'+nl+'\t\t\t\tvar observed_marked_before := not paper.mark.is_empty()'),('\t\t\t\telse:_mark(paper,false)','\t\t\t\telse:_mark(paper,false)'+nl+'\t\t\t\tassessment_submit_observed.emit({"peer":peer,"action_sha256":var_to_bytes(a).hex_encode().sha256_text(),"paper_id":paper.id,"assessment_id":str(paper.get("assessment_id","")),"profile_sha256":str(paper.identity).sha256_text(),"course":str(paper.project.get("course_id","")),"duplicate":observed_marked_before,"revision_before":paper.revision,"host_processed":true})')]
for old,new in changes:assert text.count(old)==1; text=text.replace(old,new,1)
out=B/'overlay/scripts/school_session.gd';out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(text.encode())
dump(B/'OBSERVER-PROVENANCE.json',{'preimage_sha256':sha(source),'instrumented_sha256':sha(out),'passive_insertion_only':True,'fixture_base_sha256':sha(fixture)})

# Earnings suppression is separate from durable acknowledgement/event uniqueness.
edit('run_driver.py',"        self.all({'op':'request','selector':'official','action':{'op':'submit'}})","        from copy import deepcopy\n        balances_before_mark=deepcopy(self.latest)\n        self.all({'op':'request','selector':'official','action':{'op':'submit'}})")
edit('run_driver.py',"        from copy import deepcopy\n        remote='client7'", "        from evidence import zero_earnings\n        for role in self.roles:zero_earnings(balances_before_mark[role],self.latest[role],self.plan['course'])\n        from copy import deepcopy\n        remote='client7'")
with (B/'evidence.py').open('a',encoding='utf-8') as f:f.write('''\n\ndef zero_earnings(before,after,course):
    need(type(before['dollars']) is int and before['dollars']>=0,'saved integer balance required')
    need(after['dollars']==before['dollars'],'suppressed earnings changed saved balance')
    records=[r for r in after['gradebook'].values() if not r.get('lesson',True) and r.get('course_id')==course and r.get('assessment_id')==after['assessment_id']]
    need(len(records)==1,'one actual official grade event required independently of balance')
    need(records[0]['id'] in after['reward_ids'],'durable grade-event acknowledgement missing; zero balance is not acknowledgement')
''')

# Rebuild exact effective source/import union and all local tool/fixture pins.
files={}
for root in (B/'project',B/'overlay'):
 for p in root.rglob('*'):
  if p.is_file():files[p.relative_to(root).as_posix()]={'sha256':sha(p),'bytes':p.stat().st_size}
dump(B/'SOURCE-CACHE-LOCK.json',{'schema':'classroom-source-cache-lock-v11','project':str(B/'project'),'imported_baseline':str(BASELINE),'test_instrumented_host':True,'files':files})
binding=json.loads((B/'BACKEND-BINDING.json').read_text())
for row in binding['files']:row['copied_path']=str(B/'backend'/row['name']);assert sha(row['copied_path'])==row['sha256']
dump(B/'BACKEND-BINDING.json',binding)
critical=list(B.glob('*.py'))+list((B/'backend').glob('*.py'))+list((B/'overlay').rglob('*'))+[B/'SOURCE-CACHE-LOCK.json',B/'BACKEND-BINDING.json',B/'OBSERVER-PROVENANCE.json']
bound={str(p):sha(p) for p in critical if p.is_file()}
plans=[];previous=None
for course in ('ELM253','ETY155','MTH147','MTH255'):
 p=json.loads(next((OLD/'plans').glob('*-'+course+'-LIFECYCLE1.json')).read_text());p.update(name='CLASSROOM-EIGHT-V11-'+course+'-LIFECYCLE1',project=str(B/'project'),runner=str(B/'run_j.py'),fixture_overlay=str(B/'overlay'),source_cache_lock=str(B/'SOURCE-CACHE-LOCK.json'),backend_binding=str(B/'BACKEND-BINDING.json'),source_cache_lock_sha256=sha(B/'SOURCE-CACHE-LOCK.json'),backend_binding_sha256=sha(B/'BACKEND-BINDING.json'),runner_sha256=sha(B/'run_j.py'),bound_files=dict(bound),snapshot='V11-current-imported-private',previous_name=previous,previous_result=str(B/'run-data'/previous/'RESULT.json') if previous else None,parser_result=str(B/'run-data'/PARSER/'RESULT.json'),answer_fixture=str(B/'fixtures'/(course+'.json')),authorized_now=False)
 p['answer_fixture_sha256']=sha(p['answer_fixture']);p['bound_files'][p['answer_fixture']]=p['answer_fixture_sha256'];p['output']=str(B/'run-data'/p['name']);p['required_root_grant']=str(B/'root-grants'/(p['name']+'.json'));p['source_sha256']={k:v['sha256'] for k,v in files.items() if not k.startswith('.godot/')};p['cache_sha256']={k[7:]:v['sha256'] for k,v in files.items() if k.startswith('.godot/')};plans.append(p);previous=p['name']
parser=dict(plans[0]);parser.update(name=PARSER,scenario='parser',scope='ENGINE_ONLY_CLASSROOM_EIGHT_PARSER',participants=1,total_engine_jobs=1,budget_seconds=30,engine_limit_seconds=8,port=None,course=None,kind=None,arguments=['--headless','--check-only','--script','res://tests/acceptance/classroom_network/peer.gd'],previous_name=None,previous_result=None,parser_result=None,answer_fixture=None,answer_fixture_sha256=None,parser_plan_sha256=None,output=str(B/'run-data'/PARSER),required_root_grant=str(B/'root-grants'/(PARSER+'.json')))
dump(B/'plans'/(PARSER+'.json'),parser);parser_sha=sha(B/'plans'/(PARSER+'.json'));commands=[]
for p in [parser]+plans:
 if p['scenario']!='parser':p['parser_plan_sha256']=parser_sha
 path=B/'plans'/(p['name']+'.json');dump(path,p);digest=sha(path);commands.append({'name':p['name'],'plan_sha256':digest,'argv':[p['python'],str(B/'run_j.py'),'--execute','--plan',str(path),'--plan-sha256',digest,'--grant',p['required_root_grant']]})
# Old plan files are historical inputs only; active plans are listed exclusively by COMMANDS.
dump(B/'COMMANDS.json',commands)
for p in B.glob('*.py'):ast.parse(p.read_text(encoding='utf-8-sig'))
print(json.dumps({'parser_sha256':parser_sha,'commands_sha256':sha(B/'COMMANDS.json'),'entries':len(files)},indent=2))
