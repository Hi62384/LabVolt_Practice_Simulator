"""Seal V9 after all three file-only suites pass."""
import hashlib,json
from pathlib import Path
BASE=Path(__file__).resolve().parent
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
for name,count in (('V7-REGRESSION.log',11),('V8-REGRESSION.log',11),('V9-STATIC.log',6)):
    text=(BASE/name).read_text(encoding='utf-8')
    if f'Ran {count} tests' not in text or '\nOK\n' not in text or 'FAILED' in text or 'ERROR:' in text:raise SystemExit(name+' is not successful')
commands=json.loads((BASE/'COMMANDS.json').read_text());parser=commands[0]
correction={'schema':'eight-participants-v9-reviewer-correction','owner_v8_preserved':True,'changes':['lifecycle admission tuple binds difficulty exactly to integer 0 for every course','parser path guard forbids parser_result, previous_result, previous_name, and answer_fixture'],'actual_call_path':'run_j.py calls validate_paths and envelope before fixture/grant loading','valid_plans':5,'v7_tests':11,'v8_tests':11,'v9_tests':6,'behavioral_acceptance':'UNRUN'}
(BASE/'REVIEW-CORRECTION.json').write_text(json.dumps(correction,indent=2)+'\n',encoding='utf-8')
manifest={}
for path in sorted(BASE.rglob('*')):
    if path.is_file() and path.name not in ('OWNERSHIP.json','STATIC-RESULT.json'):
        manifest[path.relative_to(BASE).as_posix()]={'sha256':sha(path),'bytes':path.stat().st_size}
(BASE/'OWNERSHIP.json').write_text(json.dumps({'schema':'eight-participants-v9-ownership','project_reused_readonly':r'C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v7\project','owner_v8_preserved':True,'live_or_shared_changed':False,'files':manifest},indent=2)+'\n',encoding='utf-8')
result={'status':'PASS_FILE_ONLY_PREFLIGHT','tests':28,'v7_tests':11,'v8_tests':11,'v9_tests':6,'runtime_executed':False,'network_executed':False,'grants_created':False,'ports_reserved':False,'behavioral_acceptance':'UNRUN','source_cache_lock_sha256':sha(BASE/'SOURCE-CACHE-LOCK.json'),'backend_binding_sha256':sha(BASE/'BACKEND-BINDING.json'),'commands_sha256':sha(BASE/'COMMANDS.json'),'run_j_sha256':sha(BASE/'run_j.py'),'path_contract_sha256':sha(BASE/'path_contract.py'),'admission_contract_sha256':sha(BASE/'admission_contract.py'),'review_correction_sha256':sha(BASE/'REVIEW-CORRECTION.json'),'ownership_sha256':sha(BASE/'OWNERSHIP.json'),'next_parser':parser}
(BASE/'STATIC-RESULT.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2))
