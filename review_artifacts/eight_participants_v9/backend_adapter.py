"""Caller adapter for unchanged admitted core-engine modules. Import performs no Win32 calls.
Every newly created engine is alone in its own atomic JobList Job. A two-peer lease must
explicitly authorize total_engine_jobs=2; old aggregate max1 admission is insufficient.
"""
from pathlib import Path
import contextlib
import hashlib
import json
import os
import sys
import time
import types


def load_backend(binding):
    modules={}
    for row in binding['files']:
        path=Path(row['copied_path']);data=path.read_bytes();name=path.stem
        if hashlib.sha256(data).hexdigest()!=row['sha256']:raise RuntimeError('Admitted backend source drift: '+name)
        module=types.ModuleType(name);module.__file__=str(path);sys.modules[name]=module
        exec(compile(data,str(path),'exec'),module.__dict__);modules[name]=module
    return modules


def cleanup_proven(record):
    value=record.get('cleanup') or {}
    return (value.get('stop_verified') is True and value.get('engine_exit_verified') is True
            and value.get('owned_job_empty_verified') is True and value.get('resource_hold_remains') is False
            and not value.get('errors') and not record.get('unverified_final_cleanup'))


def launch_proven(record):
    events=record.get('events',[]);names=[event.get('event') for event in events]
    required=['job_created','engine_created_suspended','atomic_job_assignment_verified_before_resume','actual_engine_image_verified','resumed']
    try:positions=[names.index(name) for name in required]
    except ValueError:return False
    job=events[positions[0]]
    return (positions==sorted(positions) and job.get('max_processes')==1
            and job.get('kill_on_close') is True and job.get('breakaway') is False
            and job.get('inheritable') is False and 'owned_job_empty_verified' in names)


class CoreEngineSet:
    def __init__(self,plan,binding):
        self.plan=plan;self.modules=load_backend(binding);self.entries=[];self.processes=[]
        self.pins=contextlib.ExitStack();self.closed=False
    def start(self,argv,cwd,unused_environment,log):
        self.plan['_lease_check']()
        if self.closed or len(self.entries)>=self.plan['total_engine_jobs']:raise RuntimeError('Exact engine Job envelope exceeded')
        if Path(argv[0]).resolve()!=Path(self.plan['engine']).resolve():raise RuntimeError('Wrong actual engine path')
        folder=Path(log).parent
        environment=self.modules['engine_environment'].build(os.environ,folder)
        for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP'):
            if Path(environment[key]).resolve().parent!=folder.resolve():raise RuntimeError('Profile/temp environment escaped role folder')
            Path(environment[key]).mkdir(exist_ok=True)
        api=self.modules['windows_engine_job'].WindowsEngineJob(cwd,environment)
        controller=self.modules['engine_job_controller'].EngineJobController(api)
        entry={'api':api,'controller':controller,'environment':environment,'folder':folder,'normal_exit':None,'cleanup':None,'errors':[]}
        self.entries.append(entry)
        spec=self.modules['engine_process'].EngineSpec(Path(self.plan['engine']).resolve(),self.plan['engine_sha256'],self.plan['engine_bytes'])
        self.pins.enter_context(self.modules['engine_process'].pin_engine_file(spec.path))
        controller.start(spec,['--log-file',str(log),*argv[1:]])
        self.processes.append(controller.engine)
        return len(self.processes)-1
    def exit_code(self,index):
        self.plan['_lease_check']()
        entry=self.entries[index];controller=entry['controller'];api=entry['api']
        if api.wait_owned(controller.engine,0):
            entry['normal_exit']=controller.engine.exit_code;return controller.engine.exit_code
        active=api.active_count(controller.job);members=api.member_pids(controller.job)
        if active!=1 or members!=[controller.engine.pid]:
            if api.wait_owned(controller.engine,0):
                entry['normal_exit']=controller.engine.exit_code;return controller.engine.exit_code
            raise RuntimeError('A newly owned Job does not contain exactly its one engine')
        return None
    def wait_normal_all(self,deadline):
        while True:
            exits=[self.exit_code(i) for i in range(len(self.processes))]
            if all(code is not None for code in exits):
                if any(code!=0 for code in exits):raise RuntimeError('Every actual engine must exit normally with code zero')
                return
            if time.monotonic()>=deadline:raise RuntimeError('Normal engine exit deadline; owned controller cleanup follows')
            time.sleep(.05)
    def close(self):
        if self.closed:raise RuntimeError('Engine set already closed')
        self.closed=True;records=[]
        try:
            for entry in reversed(self.entries):
                api=entry['api'];controller=entry['controller']
                record={'normal_exit':entry['normal_exit'],'errors':entry['errors'],'cleanup':None,'events':[]}
                try:
                    if controller.job in api.jobs:record['cleanup']=controller.stop()
                    elif controller.failure_cleanup is not None:record['cleanup']=controller.failure_cleanup
                    else:record['errors'].append('No controller cleanup proof available')
                except BaseException as error:record['errors'].append('Owned controller stop failed: '+str(error))
                record['events']=api.events
                record['launch_verified']=launch_proven(record)
                if not record['launch_verified']:record['errors'].append('Atomic own max1 Job/image proof events incomplete')
                record['resource_hold_remains']=bool(api.jobs) or not cleanup_proven(record)
                (entry['folder']/'core-engine-backend.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
                records.append(record)
        finally:self.pins.close()
        hold=any(record['resource_hold_remains'] for record in records)
        return {'records':records,'per_job_process_limit':1,'owned_engine_jobs':len(self.entries),
                'owned_job_zero_verified':not hold,'resource_hold_remains':hold,
                'normal_zero_all':len(records)==self.plan['total_engine_jobs'] and all(record['normal_exit']==0 and record['launch_verified'] and not record['errors'] for record in records)}
