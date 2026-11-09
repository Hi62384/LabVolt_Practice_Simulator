"""Rebind the reviewer-owned V9 stage without touching V8 or the frozen V7 project."""
import hashlib,json
from pathlib import Path
BASE=Path(__file__).resolve().parent
V7_PROJECT=Path(r'C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v7\project')
COURSES=('ELM253','ETY155','MTH147','MTH255');PARSER='CLASSROOM-EIGHT-V7-PARSER1'
MATRIX={course:f'CLASSROOM-EIGHT-V7-{course}-LIFECYCLE1' for course in COURSES}
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def emit(path,value):path.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n',encoding='utf-8')

binding=json.loads((BASE/'BACKEND-BINDING.json').read_text())
for row in binding['files']:
    row['copied_path']=str((BASE/'backend'/row['name']).resolve())
    row['sha256']=sha(row['copied_path']);row['copied_identically']=True
emit(BASE/'BACKEND-BINDING.json',binding)

critical=['run_j.py','run_driver.py','path_contract.py','admission_contract.py','backend_adapter.py','course_fixture_contract.py','eight_evidence.py','evidence.py','guards.py','proposed_guards.py','proposed_v2.py','proposed_v3.py','SOURCE-CACHE-LOCK.json','BACKEND-BINDING.json']
critical += [path.relative_to(BASE).as_posix() for path in sorted((BASE/'backend').glob('*.py'))]
bound={str((BASE/name).resolve()):sha(BASE/name) for name in critical}
names=(PARSER,*[MATRIX[course] for course in COURSES])
for name in names:
    path=BASE/'plans'/(name+'.json');plan=json.loads(path.read_text())
    plan['project']=str(V7_PROJECT.resolve());plan['runner']=str((BASE/'run_j.py').resolve())
    plan['source_cache_lock']=str((BASE/'SOURCE-CACHE-LOCK.json').resolve());plan['backend_binding']=str((BASE/'BACKEND-BINDING.json').resolve())
    plan['output']=str((BASE/'run-data'/name).resolve());plan['required_root_grant']=str((BASE/'root-grants'/(name+'.json')).resolve())
    plan['runner_sha256']=sha(BASE/'run_j.py');plan['source_cache_lock_sha256']=sha(BASE/'SOURCE-CACHE-LOCK.json');plan['backend_binding_sha256']=sha(BASE/'BACKEND-BINDING.json');plan['bound_files']=dict(bound)
    if plan['scenario']=='parser':
        for field in ('parser_result','previous_result','previous_name','answer_fixture'):plan[field]=None
    else:
        plan['answer_fixture']=str((BASE/'fixtures'/(plan['course']+'.json')).resolve());plan['answer_fixture_sha256']=sha(plan['answer_fixture']);plan['bound_files'][plan['answer_fixture']]=plan['answer_fixture_sha256']
        plan['parser_result']=str((BASE/'run-data'/PARSER/'RESULT.json').resolve())
        if plan.get('previous_name'):plan['previous_result']=str((BASE/'run-data'/plan['previous_name']/'RESULT.json').resolve())
        else:plan['previous_result']=None
    emit(path,plan)
parser_hash=sha(BASE/'plans'/(PARSER+'.json'))
for course in COURSES:
    path=BASE/'plans'/(MATRIX[course]+'.json');plan=json.loads(path.read_text());plan['parser_plan_sha256']=parser_hash;emit(path,plan)
commands=[]
for name in names:
    path=BASE/'plans'/(name+'.json');plan=json.loads(path.read_text());digest=sha(path)
    commands.append({'name':name,'plan_sha256':digest,'budget_seconds':plan['budget_seconds'],'total_engine_jobs':plan['total_engine_jobs'],'port':plan['port'],'argv':[plan['python'],str((BASE/'run_j.py').resolve()),'--execute','--plan',str(path.resolve()),'--plan-sha256',digest,'--grant',plan['required_root_grant']]})
emit(BASE/'COMMANDS.json',commands)
print(json.dumps({'plans':len(names),'commands_sha256':sha(BASE/'COMMANDS.json'),'parser_plan_sha256':parser_hash},indent=2))
