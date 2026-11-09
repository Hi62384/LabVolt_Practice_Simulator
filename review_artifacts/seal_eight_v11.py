import hashlib,json
from pathlib import Path
B=Path(r'C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v11_current')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,v):p.write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8')
p=B/'path_contract.py';t=p.read_text();t=t.replace("target=(root/rel).resolve()","target=(root/rel).resolve()\n            if field=='source_sha256' and (base/'overlay'/rel).is_file():target=(base/'overlay'/rel).resolve();root_check=(base/'overlay').resolve()\n            else:root_check=root") .replace('target.is_relative_to(root)','target.is_relative_to(root_check)');p.write_text(t,encoding='utf-8')
commands=json.loads((B/'COMMANDS.json').read_text())
for c in commands:
 p=Path(c['argv'][4]);v=json.loads(p.read_text())
 for f in v['bound_files']:v['bound_files'][f]=sha(f)
 if v['scenario']!='parser':v['parser_plan_sha256']=commands[0]['plan_sha256']
 dump(p,v);c['plan_sha256']=sha(p);c['argv'][6]=sha(p)
dump(B/'COMMANDS.json',commands)
(B/'HANDOFF.md').write_text('''# V11 retained four-course packet
Source/static preparation only. Runtime UNRUN. Exact argv and plan hashes are in COMMANDS.json. Five independent windows: parser one engine, 30 seconds, no UDP; then ELM253, ETY155, MTH147, MTH255, eight actual engines/Jobs each, one process per Job, 300 seconds per course. Ports 27096–27099 are historical proposed endpoints, not reservations. Later courses require accepted predecessor and eight Job0 cleanup plus the accepted parser receipt. Fresh grants and output directories are absent.

The private imported baseline is frozen in project; effective overlay precedence retains the passive submit callback and reviewed peer inheritance. Both parser and lifecycle materializers create overlay parent directories. Each role has isolated project/userdata. Current zero-earnings assertion requires unchanged integer saved balances AND one durable official grade event acknowledgement. Existing full-gradebook/reward acknowledgement duplicate comparisons remain intact. Zero balance change alone proves no event uniqueness.

Extra network coverage remains required for avatar ownership/foreign mutation rejection, dorm assignment/door access/room privacy, true automatic 120-second class start and assigned work, and host-authoritative unlimited shop purchases with unchanged saved balances. The retained classroom fixture still explicitly advances teaching and is not evidence for those behaviors. Weighted-course aggregation, retake-highest and the >=50 pass boundary need dedicated repeated-attempt network cases; this packet checks actual individual course marks only.

History retains V10 prepared plans/grants, failed PARSER1 result and the primary materializer correction report. No historical receipt establishes V11 runtime acceptance.
''',encoding='utf-8')
manifest={p.relative_to(B).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size} for p in B.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name not in ('OWNERSHIP.json','STATIC-RESULT.json')}
dump(B/'OWNERSHIP.json',{'schema':'eight-v11-private','files':manifest})
dump(B/'STATIC-RESULT.json',{'status':'PENDING_FINAL_STATIC_READBACK','runtime_executed':False,'network_executed':False,'commands_sha256':sha(B/'COMMANDS.json'),'ownership_sha256':sha(B/'OWNERSHIP.json'),'parser':commands[0]})
print(json.dumps(commands[0],indent=2))
