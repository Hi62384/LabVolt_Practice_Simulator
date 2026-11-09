"""ENGINE-ONLY CORE GRAPHICS. New grant/lock required for each mode.
25s parser/one-engine kill admission, then separately granted<=100s practice.
No Node/helper/native/firmware/compiler/import/multiprocess case is admitted.
"""
from pathlib import Path
import argparse,hashlib,json,os,time
from engine_process import EngineSpec,pin_engine_file
from engine_environment import build
from windows_engine_job import WindowsEngineJob
from engine_job_controller import EngineJobController

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def inventory(project):
    return {p.relative_to(project).as_posix():sha(p) for p in sorted(project.rglob('*')) if p.is_file() and not any(s in ('.godot','.git','__pycache__','runtime') for s in p.relative_to(project).parts)}
def validate(a):
    lock=json.loads(a.lock.read_text())
    if lock['scope']!='ENGINE_ONLY_CORE_GRAPHICS' or lock['max_processes']!=1:raise RuntimeError('Wrong receipt/job scope')
    if a.mode!=lock['mode'] or a.lease!=lock['name'] or a.budget!=lock['budget_seconds']:raise RuntimeError('Unreviewed mode/lease/budget')
    for role,value in lock['roles'].items():
        if Path(getattr(a,role)).resolve()!=Path(value).resolve():raise RuntimeError('Wrong locked path: '+role)
    if a.project.resolve()==a.main.resolve() or a.main.resolve() in a.project.resolve().parents:raise RuntimeError('Main read-only')
    if inventory(a.project)!=json.loads(a.freeze.read_text()):raise RuntimeError('Source drift')
    for path,value in lock['bound_files'].items():
        if sha(path)!=value:raise RuntimeError('Tool/plan/harness/source binding drift')
    for path,value in lock['cache'].items():
        if sha(a.project/'.godot'/path)!=value:raise RuntimeError('Imported cache drift')
    ready=a.readiness.read_text()
    if a.lease not in ready or 'READY' not in ready.upper() or not -10<=time.time()-a.readiness.stat().st_mtime<=600:raise RuntimeError('Fresh named readiness missing; no launch')
    if a.mode=='practice':
        receipt_path=Path(lock['required_engine_admission'])
        if not receipt_path.exists():raise RuntimeError('ENGINE_ONLY_ADMISSION receipt missing; no practice launch')
        r=json.loads(receipt_path.read_text())
        if r.get('receipt_type')!='ENGINE_ONLY_ADMISSION' or r.get('scope')!='ENGINE_ONLY_CORE_GRAPHICS' or r.get('max_processes')!=1 or r.get('status')!='ENGINE_ONLY_PASS' or r.get('source_freeze_sha256')!=sha(a.freeze) or r.get('engine_sha256')!=lock['engine_sha256'] or r.get('errors') or r.get('resource_hold_remains') or not r.get('source_stable') or r.get('overrun'):raise RuntimeError('Exact engine-only admission not accepted')
    return lock,ready

def practice_provenance_matches(actual,case):
    return actual.get('scope')=='CORE_AC_DC_GRAPHICS_ONLY' and bool(actual.get('engine_only')) and actual.get('case')==case

def stage(a,lock,folder,arguments,deadline,limit,*,intentional=False):
    folder.mkdir();log=folder/'engine.log';marker=folder/'ready.json'
    env=build(os.environ,folder)
    for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP'):Path(env[key]).mkdir()
    api=WindowsEngineJob(a.project,env);controller=EngineJobController(api)
    record={'scope':'ENGINE_ONLY','errors':[],'cleanup':None,'events':[],'intentional_stop':intentional,'max_processes':1}
    spec=EngineSpec(a.godot.resolve(),lock['engine_sha256'],lock['engine_bytes'])
    args=['--path',str(a.project.resolve()),'--log-file',str(log),*arguments]
    if intentional:args.extend(['--',f'--ready={marker}'])
    started=time.monotonic()
    with pin_engine_file(spec.path):
        try:
            controller.start(spec,args);record['pid']=controller.engine.pid
            until=min(deadline-4,time.monotonic()+limit)
            while time.monotonic()<until:
                if api.wait_owned(controller.engine,0):break
                active=api.active_count(controller.job);pids=api.member_pids(controller.job)
                if active!=1 or pids!=[controller.engine.pid]:
                    # Queries are sequential; normal exit can occur between them.
                    if api.wait_owned(controller.engine,0):break
                    raise RuntimeError('One-engine-only job invariant failed')
                if intentional and marker.exists():
                    m=json.loads(marker.read_text())
                    if m.get('pid')!=controller.engine.pid or m.get('scope')!='ENGINE_ONLY_ADMISSION':raise RuntimeError('Wrong own-engine marker')
                    record['marker']=m;break
                time.sleep(.1)
            else:raise RuntimeError('Owned engine stage deadline')
            if intentional and 'marker' not in record:raise RuntimeError('Engine ended before intentional stop marker')
            if not intentional:
                if not api.wait_owned(controller.engine,0) or controller.engine.exit_code!=0:raise RuntimeError('Actual engine did not exit normally')
                record['normal_exit']=controller.engine.exit_code
        except BaseException as error:record['errors'].append(str(error))
        finally:
            try:
                if controller.job in api.jobs:record['cleanup']=controller.stop()
                elif controller.failure_cleanup is not None:record['cleanup']=controller.failure_cleanup
                elif controller.engine is None:record['cleanup']={'stop_verified':True,'no_engine_executed':True,'scope':'no engine or job left open'}
            except BaseException as error:record['errors'].append('Owned cleanup failed: '+str(error))
            finally:
                if api.jobs:
                    record['unverified_final_cleanup']=True
                    for job in list(api.jobs):
                        try:api.terminate_job(job);api.close_job(job)
                        except OSError as error:record['errors'].append(str(error))
                record['events']=api.events
    if not (record.get('cleanup') or {}).get('stop_verified',False):record['errors'].append('Own engine/job cleanup unverified')
    if not log.exists():record['errors'].append('Structured actual engine log missing')
    else:record['errors'].extend(line for line in log.read_text(encoding='utf-8',errors='replace').splitlines() if any(k in line for k in ('ERROR','WARNING','SCRIPT ERROR')) and 'Failed to read the root certificate store.' not in line)
    record['elapsed_seconds']=time.monotonic()-started;return record

def run(a):
    started=time.monotonic();deadline=started+a.budget
    lock,ready=validate(a);frozen=json.loads(a.freeze.read_text())
    if a.evidence.exists():raise RuntimeError('New evidence directory required')
    out=a.evidence.resolve();out.mkdir(parents=True);records=[];errors=[]
    result={'receipt_type':'ENGINE_ONLY_ADMISSION' if a.mode=='admission' else 'CORE_GRAPHICS_PRACTICE','scope':'ENGINE_ONLY_CORE_GRAPHICS','engine_sha256':lock['engine_sha256'],'source_freeze_sha256':sha(a.freeze),'max_processes':1,'external_load':'UNVERIFIED_PRIOR_TEST_ENGINES_AND_OLD_HELPER; no clean-environment claim','not_authorized_for':['native','helper','firmware','compiler','advanced_devices'],'errors':errors,'stages':records,'resource_hold_remains':False}
    (out/'lock.json').write_text(json.dumps(lock,indent=2));(out/'readiness.txt').write_text(ready);(out/'source-before.json').write_text(json.dumps(frozen,indent=2))
    try:
        if a.mode=='admission':
            if deadline-time.monotonic()<12:raise RuntimeError('Insufficient admission lease after hashes')
            for name,args,limit,intent in [('parser',['--headless','--check-only','--script',str(a.project/'tests/campus/performance/practice_profile.gd')],6,False),('report-contract',['--headless','--script','res://tests/campus/performance/test_practice_report.gd'],3,False),('intentional-stop',['--headless','--script','res://tests/campus/performance/engine_only_admission.gd'],5,True)]:
                r=stage(a,lock,out/name,args,deadline,limit,intentional=intent);r['name']=name;records.append(r)
                if name=='report-contract' and not r['errors']:
                    lines=(out/name/'engine.log').read_text(encoding='utf-8',errors='replace').splitlines()
                    payloads=[line.split('=',1)[1] for line in lines if line.startswith('PRACTICE_REPORT_CONTRACT_JSON=')]
                    fixture={'id':'dc-practice','seconds':18,'graphics':{'render_scale':1.0}}
                    if len(payloads)!=1 or not practice_provenance_matches(json.loads(payloads[0]),fixture):r['errors'].append('Actual producer/Python consumer boundary mismatch')
                    else:
                        actual_contract=json.loads(payloads[0])
                        bad_string=json.loads(payloads[0]);bad_string['case']['seconds']='18'
                        missing_case=json.loads(payloads[0]);missing_case.pop('case')
                        wrong_scope=json.loads(payloads[0]);wrong_scope['scope']='wrong'
                        missing_scope=json.loads(payloads[0]);missing_scope.pop('scope')
                        false_engine=json.loads(payloads[0]);false_engine['engine_only']=False
                        if any(practice_provenance_matches(bad,fixture) for bad in (bad_string,missing_case,wrong_scope,missing_scope,false_engine)):r['errors'].append('Actual producer/consumer negative contract regression')
                        else:r['producer_consumer_contract']='ACTUAL_GDSCRIPT_JSON_TO_STRICT_PYTHON_POSITIVE_AND_NEGATIVES_PASS'  
                if r['errors']:raise RuntimeError(str(r['errors']))
        else:
            plan=json.loads(a.plan.read_text())
            for case in plan['practice_cases']:
                if case['id'] not in ('dc-practice','ac-practice'):raise RuntimeError('Only core AC/DC practice cases admitted')
                if deadline-time.monotonic()<44:raise RuntimeError('Insufficient remaining practice budget; no next case')
                validate(a);config=out/(case['id']+'.json');config.write_text(json.dumps(case,indent=2))
                folder=out/case['id'];report=folder/'report.json'
                r=stage(a,lock,folder,['--script','res://tests/campus/performance/practice_profile.gd','--',f'--case={config}',f'--output={report}'],deadline,44);r['name']=case['id'];records.append(r)
                if not report.exists():r['errors'].append('Actual practice report missing')
                else:
                    actual=json.loads(report.read_text());r['errors'].extend(actual.get('failures',[]))
                    if not practice_provenance_matches(actual,case):r['errors'].append('Practice scope/provenance mismatch')
                    if not any(c.get('label')=='sample' and c.get('proof',{}).get('valid') and c.get('timing',{}).get('sample_count',0)>0 for c in actual.get('checkpoints',[])):r['errors'].append('Missing genuine measured practice population')
                if not Path(str(report)+'.png').exists():r['errors'].append('Actual view verification image missing')
                if r['errors']:raise RuntimeError(str(r['errors']))
    except BaseException as error:errors.append(str(error))
    finally:
        after=inventory(a.project);result['source_stable']=after==frozen;result['overrun']=time.monotonic()-started>a.budget;result['elapsed_seconds']=time.monotonic()-started
        result['resource_hold_remains']=any(not (r.get('cleanup') or {}).get('stop_verified',False) or r.get('unverified_final_cleanup') for r in records)
        if not result['source_stable']:errors.append('Source drift during run')
        if result['overrun']:errors.append('Lease overrun')
        result['status']='ENGINE_ONLY_PASS' if a.mode=='admission' and not errors and not result['resource_hold_remains'] else 'PRACTICE_PENDING_VISUAL_REVIEW' if a.mode=='practice' and not errors and not result['resource_hold_remains'] else 'NOT_ACCEPTED'
        (out/'source-after.json').write_text(json.dumps(after,indent=2));(out/'receipt.json').write_text(json.dumps(result,indent=2))
        print(json.dumps({'status':'OWNED CLEANUP UNVERIFIED / HOLD REMAINS' if result['resource_hold_remains'] else 'WINDOW RELEASED','result':result['status'],'elapsed_seconds':result['elapsed_seconds']}),flush=True)
    if errors or result['resource_hold_remains']:raise RuntimeError(str(errors))

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for key in ('project','main','freeze','evidence','plan','godot','lock','readiness'):p.add_argument('--'+key,type=Path,required=True)
    for key in ('mode','lease'):p.add_argument('--'+key,required=True)
    p.add_argument('--budget',type=float,required=True);run(p.parse_args())
