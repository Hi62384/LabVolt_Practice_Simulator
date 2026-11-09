"""Record verified independent repairs and hold obsolete lifecycle acceptance."""
import hashlib,json
from pathlib import Path
B=Path(r'C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v11_current')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8')
dump(B/'LIFECYCLE-HOLD.json',{'status':'BLOCKED_PENDING_PRODUCTION_LIFECYCLE_HANDOFF','reason':'Leaving an active class fails the assignment; unfinished assignment restoration is forbidden. Existing stable_paper restoration assertions must be replaced after the actual production API handoff. Completed marks/profile/inventory persistence remains required.','source_static_tests':{'tests':2,'seconds':24.155,'result':'PASS','scope':'five canonical plan/hash/effective-union preflights and zero-earnings/event-acknowledgement negatives'},'runtime_executed':False})
# Do not allow the superseded recovery oracle to run under a fresh grant.
p=B/'run_j.py';t=p.read_text();old="    if plan['scenario']=='lifecycle':\n        from course_fixture_contract import load_fixture";new="    if plan['scenario']=='lifecycle':\n        raise RuntimeError('V11 lifecycle acceptance held: production leave-fails-assignment handoff pending; old unfinished-assignment restoration oracle forbidden')\n        from course_fixture_contract import load_fixture";assert old in t;t=t.replace(old,new,1);p.write_text(t,encoding='utf-8')
commands=json.loads((B/'COMMANDS.json').read_text())
for c in commands:
 p=Path(c['argv'][4]);v=json.loads(p.read_text());v['runner_sha256']=sha(B/'run_j.py')
 for f in v['bound_files']:v['bound_files'][f]=sha(f)
 if v['scenario']!='parser':v['parser_plan_sha256']=commands[0]['plan_sha256']
 dump(p,v);c['plan_sha256']=sha(p);c['argv'][6]=sha(p)
dump(B/'COMMANDS.json',commands)
with (B/'HANDOFF.md').open('a',encoding='utf-8') as f:f.write('\n## Superseding lifecycle hold\nThe new user rule forbids unfinished-class recovery. The real caller now rejects lifecycle execution before grant loading. Canonical path, imported-baseline, materialization, and zero-earnings work passed two focused source/mock tests (24.155s). The old stable-paper/rejoin acceptance is NOT approved; await the production lifecycle handoff and replace those assertions using actual APIs. Parser remains check-only and does not establish lifecycle acceptance.\n')
manifest={p.relative_to(B).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size} for p in B.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name not in ('OWNERSHIP.json','STATIC-RESULT.json')}
dump(B/'OWNERSHIP.json',{'schema':'eight-v11-private','files':manifest})
dump(B/'STATIC-RESULT.json',{'status':'INDEPENDENT_REPAIRS_VERIFIED_LIFECYCLE_HELD','tests':2,'test_result':'PASS before lifecycle hold insertion; final bindings rehashed','runtime_executed':False,'network_executed':False,'commands_sha256':sha(B/'COMMANDS.json'),'ownership_sha256':sha(B/'OWNERSHIP.json'),'parser':commands[0],'lifecycle_hold_sha256':sha(B/'LIFECYCLE-HOLD.json')})
print(json.dumps({'parser':commands[0],'commands_sha256':sha(B/'COMMANDS.json'),'ownership_sha256':sha(B/'OWNERSHIP.json')},indent=2))
