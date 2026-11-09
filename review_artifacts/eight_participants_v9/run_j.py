"""Exact J caller. --execute requires a new root-coordinated exclusive resource window.
No Windows job-start connector, alternate launcher, old-process inventory, receipt mutation,
compiler, helper or device implementation. Backend modules are source-verified before import.
"""
from pathlib import Path
import argparse,hashlib,json,sys,time,shutil
from types import SimpleNamespace
BASE=Path(__file__).resolve().parent
sys.dont_write_bytecode=True

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def pairs_unique(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError('Duplicate JSON key: '+key)
        result[key]=value
    return result

def strict_json(text):
    def invalid(value):raise ValueError('Nonfinite JSON constant: '+value)
    return json.loads(text,object_pairs_hook=pairs_unique,parse_constant=invalid)

def emit(path,value):path.write_text(json.dumps(value,indent=2,allow_nan=False),encoding='utf-8')

def validate_grant(plan,plan_hash,grant,*,now=None,full_budget=True):
    now=time.time() if now is None else now
    expected={'name':plan['name'],'status':'GRANTED','scope':plan['scope'],
        'plan_sha256':plan_hash,'source_cache_lock_sha256':plan['source_cache_lock_sha256'],
        'engine_sha256':plan['engine_sha256'],'per_job_process_limit':1,
        'total_engine_jobs':plan['total_engine_jobs'],'budget_seconds':plan['budget_seconds'],
        'exclusive_engine_window':True,'previous_owned_cleanup_verified':True}
    for key,value in expected.items():
        if type(grant.get(key)) is not type(value) or grant[key]!=value:raise RuntimeError('Exact root resource grant mismatch: '+key)
    for key in ('issued_unix','not_before_unix','expires_unix'):
        if type(grant.get(key)) not in (int,float):raise RuntimeError('Typed root grant timestamp required')
    if not 0<=now-grant['issued_unix']<=300 or now<grant['not_before_unix'] or now>=grant['expires_unix']:
        raise RuntimeError('Fresh active root resource grant required')
    if full_budget and grant['expires_unix']-now<plan['budget_seconds']:raise RuntimeError('Full bounded case budget unavailable')

def inventory(project,lock):
    expected=lock['files'];actual={p.relative_to(project).as_posix() for p in project.rglob('*') if p.is_file()}
    if actual!=set(expected):raise RuntimeError('Unlisted or missing J staged source/cache file')
    for relative,row in expected.items():
        target=project/relative
        if not target.resolve().is_relative_to(project.resolve()) or sha(target)!=row['sha256']:raise RuntimeError('Locked J source/cache drift: '+relative)
    return len(expected)


def parser_case(plan,project,lock,out,deadline,check_lease,stage,on_launch):
    """Parse the fixture in a verified disposable project; never start Main here."""
    out.mkdir(parents=True)
    disposable=out/'parser-project'
    shutil.copytree(project,disposable)
    inventory(disposable,lock)
    check_lease()
    args=SimpleNamespace(project=disposable,godot=Path(plan['engine']))
    on_launch()
    record=stage(args,plan,out/'engine',plan['arguments'],deadline,plan['engine_limit_seconds'])
    return record,disposable


def run(args):
    started=time.monotonic()
    if not args.plan.resolve().is_relative_to((BASE/'plans').resolve()):raise RuntimeError('Plan must be in frozen J plans directory')
    if sha(args.plan)!=args.plan_sha256:raise RuntimeError('Reviewed exact plan SHA256 required')
    plan=strict_json(args.plan.read_text(encoding='utf-8'))
    from path_contract import validate_paths
    validate_paths(plan,BASE)
    from admission_contract import envelope,require_parser
    envelope(plan)
    if plan['scenario']=='lifecycle':
        from course_fixture_contract import load_fixture
        load_fixture(plan)
    if Path(args.grant).resolve()!=Path(plan['required_root_grant']).resolve():raise RuntimeError('Unexpected root grant path')
    grant=strict_json(args.grant.read_text(encoding='utf-8'));validate_grant(plan,args.plan_sha256,grant)
    if plan['scenario']=='lifecycle':require_parser(plan,grant)
    # Prior course evidence is a prerequisite, never an automatic next launch.
    if plan.get('previous_result'):
        previous=Path(plan['previous_result'])
        if grant.get('previous_result_sha256')!=sha(previous):raise RuntimeError('Previous result not bound by fresh grant')
        prior=strict_json(previous.read_text(encoding='utf-8'))
        if prior.get('name')!=plan['previous_name'] or prior.get('accepted') is not True or prior.get('resource_hold_remains') is not False:
            raise RuntimeError('Previous course acceptance/cleanup prerequisite missing')
        if prior.get('cleanup',{}).get('owned_engine_jobs')!=8 or prior.get('cleanup',{}).get('owned_job_zero_verified') is not True:
            raise RuntimeError('Previous eight owned Jobs have no Job0 proof')
    if Path(sys.executable).resolve()!=Path(plan['python']).resolve() or sha(sys.executable)!=plan['python_sha256']:raise RuntimeError('Python byte identity changed')
    for path,digest in plan['bound_files'].items():
        if sha(path)!=digest:raise RuntimeError('Bound source/tool/fixture changed: '+path)
    if sha(plan['engine'])!=plan['engine_sha256'] or Path(plan['engine']).stat().st_size!=plan['engine_bytes']:raise RuntimeError('Pinned actual engine identity changed')
    project=Path(plan['project']).resolve()
    if project!=Path('C:\\Users\\User1\\Documents\\Codex\\2026-11-05\\task-6\\eight_participants_v7\\project').resolve():raise RuntimeError('Only the frozen V7 test-instrumented project is allowed')
    lock=strict_json(Path(plan['source_cache_lock']).read_text(encoding='utf-8'))
    inventory(project,lock)
    out=Path(plan['output']);deadline=started+plan['budget_seconds']
    if out.exists():raise RuntimeError('Fresh case output is required; preserve previous evidence')
    result={'name':plan['name'],'snapshot':plan['snapshot'],'snapshot_manifest_sha256':plan['snapshot_manifest_sha256'],
        'engine_sha256':plan['engine_sha256'],'backend_binding_sha256':plan['backend_binding_sha256'],
        'plan_sha256':args.plan_sha256,'source_cache_lock_sha256':plan['source_cache_lock_sha256'],
        'per_job_process_limit':1,'total_engine_jobs':plan['total_engine_jobs'],'errors':[],'resource_hold_remains':False,
        'Godot_result':'NOT_EXECUTED','external_process_state':'unknown; no inventory, old-engine exit or clean-environment claim'}
    binding=strict_json(Path(plan['backend_binding']).read_text(encoding='utf-8'))
    def check_lease():
        current=strict_json(args.grant.read_text(encoding='utf-8'))
        if current!=grant:raise RuntimeError('Root resource grant changed; no further launch/action')
        validate_grant(plan,args.plan_sha256,current,full_budget=False)
        if time.monotonic()>=deadline:raise RuntimeError('Global source/tool/case/cleanup deadline exceeded')
    try:
        if plan['scenario']=='parser':
            from backend_adapter import load_backend,cleanup_proven,launch_proven
            modules=load_backend(binding)
            def mark_parser_launch():result['resource_hold_remains']=True
            record,parser_project=parser_case(plan,project,lock,out,deadline,check_lease,modules['run_engine_only'].stage,mark_parser_launch)
            result['parser_scope']='FIXTURE_PARSE_ONLY'
            result['main_startup_tested']=False
            result['parser_disposable_project']=str(parser_project)
            result['backend']=record;emit(out/'core-engine-backend.json',record)
            result['resource_hold_remains']=not cleanup_proven(record)
            if record['errors'] or record.get('normal_exit')!=0 or result['resource_hold_remains'] or not launch_proven(record):
                raise RuntimeError('Parser normal0/core backend Job0 proof failed: '+str(record['errors']))
            result['parser_copy_entries_verified_after']=inventory(parser_project,lock)
        else:
            from run_driver import Run
            runtime_plan=dict(plan,root_lease_id=plan['name'],wall_seconds=plan['budget_seconds'],_lease_check=check_lease)
            driver=Run(runtime_plan)
            result['resource_hold_remains']=True
            driver.start()
            cleanup=strict_json((out/'owned-job-cleanup.json').read_text(encoding='utf-8'))
            result['cleanup']=cleanup;result['resource_hold_remains']=cleanup['resource_hold_remains']
            if not cleanup['normal_zero_all'] or not cleanup['owned_job_zero_verified'] or result['resource_hold_remains']:
                raise RuntimeError('Every actual engine normal0 and every exact owned Job0 are required')
        result['Godot_result']='PASS_FOR_THIS_EXACT_CASE_ONLY'
    except BaseException as error:
        result['errors'].append(str(error))
        cleanup_path=out/'owned-job-cleanup.json'
        if cleanup_path.exists():
            result['cleanup']=strict_json(cleanup_path.read_text(encoding='utf-8'))
            result['resource_hold_remains']=result['cleanup']['resource_hold_remains']
    finally:
        try:result['source_cache_entries_verified_after']=inventory(project,lock)
        except BaseException as error:result['errors'].append(str(error))
        result['elapsed_seconds']=time.monotonic()-started;result['overrun']=time.monotonic()>deadline
        if result['overrun']:result['errors'].append('Exact bounded resource window exceeded')
        result['accepted']=not result['errors'] and not result['resource_hold_remains'] and result['Godot_result']=='PASS_FOR_THIS_EXACT_CASE_ONLY'
        if out.exists():emit(out/'RESULT.json',result)
        print(json.dumps({'case':plan['name'],'accepted':result['accepted'],'resource_hold_remains':result['resource_hold_remains'],'elapsed_seconds':result['elapsed_seconds']}),flush=True)
    return 0 if result['accepted'] else 1

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--execute',action='store_true',required=True)
    p.add_argument('--plan',type=Path,required=True);p.add_argument('--plan-sha256',required=True);p.add_argument('--grant',type=Path,required=True)
    raise SystemExit(run(p.parse_args()))
