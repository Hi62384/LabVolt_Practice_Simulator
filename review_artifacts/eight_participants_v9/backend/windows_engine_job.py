"""Actual Win32 backend for NEW owned ENGINE-ONLY benchmark jobs.
Import and construction call no Win32 API. A separate granted admission is
required before calling create_job/start. This is not a compiler sandbox.
"""
from pathlib import Path
from dataclasses import dataclass
import ctypes as C,os,subprocess,time
from engine_process import verify_engine

DWORD=C.c_uint32;BOOL=C.c_int32;HANDLE=C.c_void_p;SIZE_T=C.c_size_t;U64=C.c_uint64
class BasicLimit(C.Structure):
    _fields_=[('process_time',C.c_int64),('job_time',C.c_int64),('flags',DWORD),('min_working',SIZE_T),('max_working',SIZE_T),('active_limit',DWORD),('affinity',SIZE_T),('priority',DWORD),('scheduling',DWORD)]
class IOCounters(C.Structure):_fields_=[('values',U64*6)]
class ExtendedLimit(C.Structure):
    _fields_=[('basic',BasicLimit),('io',IOCounters),('process_memory',SIZE_T),('job_memory',SIZE_T),('peak_process',SIZE_T),('peak_job',SIZE_T)]
class Accounting(C.Structure):
    _fields_=[('user',C.c_int64),('kernel',C.c_int64),('period_user',C.c_int64),('period_kernel',C.c_int64),('page_faults',DWORD),('total_processes',DWORD),('active_processes',DWORD),('terminated_processes',DWORD)]
class ProcessIds(C.Structure):_fields_=[('assigned',DWORD),('count',DWORD),('pids',SIZE_T*16)]
class StartupInfo(C.Structure):
    _fields_=[('cb',DWORD),('reserved',C.c_wchar_p),('desktop',C.c_wchar_p),('title',C.c_wchar_p),('x',DWORD),('y',DWORD),('width',DWORD),('height',DWORD),('xchars',DWORD),('ychars',DWORD),('fill',DWORD),('flags',DWORD),('show',C.c_uint16),('reserved_size',C.c_uint16),('reserved_ptr',C.c_void_p),('stdin',HANDLE),('stdout',HANDLE),('stderr',HANDLE)]
class ProcessInfo(C.Structure):_fields_=[('process',HANDLE),('thread',HANDLE),('pid',DWORD),('tid',DWORD)]
class StartupInfoEx(C.Structure):_fields_=[('startup',StartupInfo),('attributes',C.c_void_p)]
@dataclass
class OwnedProcess:
    handle: int
    thread: int
    pid: int
    job: int=0
    exit_code: int|None=None

def environment_block(environment):
    values=[]
    for key,value in sorted(environment.items(),key=lambda pair:pair[0].casefold()):
        if not key or '=' in key or '\0' in key or '\0' in str(value):raise ValueError('Invalid explicit child environment')
        values.append(str(key)+'='+str(value))
    return C.create_unicode_buffer('\0'.join(values)+'\0')

class WindowsEngineJob:
    def __init__(self,cwd,environment,*,kernel=None,clock=time.monotonic,sleep=time.sleep):
        self.cwd=Path(cwd).resolve();self.environment=dict(environment);self.kernel=kernel;self.simulated=kernel is not None
        self.clock=clock;self.sleep=sleep;self.jobs=set();self.processes=[];self.events=[]
    def _bind(self):
        if self.kernel is not None:return
        if os.name!='nt' or C.sizeof(C.c_void_p)!=8:raise RuntimeError('Windows x64 job backend unavailable; no process executed')
        k=C.WinDLL('kernel32',use_last_error=True)
        signatures={
            'CreateJobObjectW':([C.c_void_p,C.c_wchar_p],HANDLE),
            'SetInformationJobObject':([HANDLE,C.c_int,C.c_void_p,DWORD],BOOL),
            'InitializeProcThreadAttributeList':([C.c_void_p,DWORD,DWORD,C.POINTER(SIZE_T)],BOOL),
            'UpdateProcThreadAttribute':([C.c_void_p,DWORD,SIZE_T,C.c_void_p,SIZE_T,C.c_void_p,C.c_void_p],BOOL),
            'DeleteProcThreadAttributeList':([C.c_void_p],None),
            'CreateProcessW':([C.c_wchar_p,C.c_wchar_p,C.c_void_p,C.c_void_p,BOOL,DWORD,C.c_void_p,C.c_wchar_p,C.POINTER(StartupInfoEx),C.POINTER(ProcessInfo)],BOOL),
            'ResumeThread':([HANDLE],DWORD),'TerminateProcess':([HANDLE,DWORD],BOOL),
            'TerminateJobObject':([HANDLE,DWORD],BOOL),'WaitForSingleObject':([HANDLE,DWORD],DWORD),
            'GetExitCodeProcess':([HANDLE,C.POINTER(DWORD)],BOOL),
            'IsProcessInJob':([HANDLE,HANDLE,C.POINTER(BOOL)],BOOL),
            'QueryFullProcessImageNameW':([HANDLE,DWORD,C.c_wchar_p,C.POINTER(DWORD)],BOOL),
            'QueryInformationJobObject':([HANDLE,C.c_int,C.c_void_p,DWORD,C.c_void_p],BOOL),
            'CloseHandle':([HANDLE],BOOL)}
        for name,(args,result) in signatures.items():function=getattr(k,name);function.argtypes=args;function.restype=result
        self.kernel=k
    def _error(self,label):
        code=int(self.kernel.last_error) if self.simulated else C.get_last_error()
        return OSError(code,label)
    def _check(self,okay,label):
        if not okay:raise self._error(label)
    def _job(self,job):
        if job not in self.jobs:raise RuntimeError('Not a newly-owned job handle')
    def _process(self,process):
        if not any(process is p for p in self.processes) or not process.handle:raise RuntimeError('Not an open newly-created owned engine handle')
    def create_job(self,*,kill_on_close,inheritable,breakaway,max_processes):
        if not kill_on_close or inheritable or breakaway or max_processes!=1:raise RuntimeError('ENGINE ONLY requires max_processes=1')
        self._bind();job=self.kernel.CreateJobObjectW(None,None);self._check(job,'Create unnamed owned job')
        self.jobs.add(job)
        limits=ExtendedLimit();limits.basic.flags=0x2000|0x8;limits.basic.active_limit=1
        try:self._check(self.kernel.SetInformationJobObject(job,9,C.byref(limits),C.sizeof(limits)),'Set kill-on-close/no-breakaway owned limits')
        except BaseException:self.close_job(job);raise
        self.events.append({'event':'job_created','handle':int(job),'kill_on_close':True,'inheritable':False,'breakaway':False,'max_processes':1});return job
    def create_suspended(self,spec,arguments,*,inherit_job_handle):
        if inherit_job_handle:raise RuntimeError('Job handle inheritance forbidden')
        verify_engine(spec);self._bind()
        if len(self.jobs)!=1:raise RuntimeError('Exactly one newly-owned job required before creation')
        job=next(iter(self.jobs))
        start=StartupInfoEx();start.startup.cb=C.sizeof(start)
        if '--headless' in arguments:start.startup.flags=1;start.startup.show=0
        info=ProcessInfo();command=C.create_unicode_buffer(subprocess.list2cmdline([str(spec.path.resolve()),*arguments]))
        env=environment_block(self.environment)
        # Assignment is atomic with creation, closing the create/assign crash gap.
        # Unsupported/nested-job denial fails before execution; no legacy fallback.
        size=SIZE_T();self.kernel.InitializeProcThreadAttributeList(None,1,0,C.byref(size))
        if size.value==0:raise self._error('Size atomic job-list attributes')
        attributes=C.create_string_buffer(size.value);start.attributes=C.cast(attributes,C.c_void_p)
        self._check(self.kernel.InitializeProcThreadAttributeList(start.attributes,1,0,C.byref(size)),'Initialize atomic job-list attributes')
        jobs=(HANDLE*1)(job)
        flags=0x80000|0x4|0x400 # EXTENDED_STARTUPINFO_PRESENT | SUSPENDED | UNICODE
        try:
            self._check(self.kernel.UpdateProcThreadAttribute(start.attributes,0,0x2000d,C.byref(jobs),C.sizeof(jobs),None,None),'Bind owned job at process creation')
            self._check(self.kernel.CreateProcessW(str(spec.path.resolve()),command,None,None,False,flags,C.cast(env,C.c_void_p),str(self.cwd),C.byref(start),C.byref(info)),'Create owned actual engine suspended inside job')
        finally:self.kernel.DeleteProcThreadAttributeList(start.attributes)
        process=OwnedProcess(int(info.process),int(info.thread),int(info.pid));self.processes.append(process)
        self.events.append({'event':'engine_created_suspended','pid':process.pid,'command':command.value,'flags':flags,'inherited_handles':False})
        return process,process.thread
    def assign(self,job,process):
        self._job(job);self._process(process)
        inside=BOOL();self._check(self.kernel.IsProcessInJob(process.handle,job,C.byref(inside)),'Verify suspended own-job association')
        if not inside.value:raise RuntimeError('Engine not confirmed in owned job; do not resume')
        process.job=job;self.events.append({'event':'atomic_job_assignment_verified_before_resume','pid':process.pid});return True
    def _image(self,handle):
        text=C.create_unicode_buffer(32768);size=DWORD(len(text))
        self._check(self.kernel.QueryFullProcessImageNameW(handle,0,text,C.byref(size)),'Query newly-owned image handle')
        return Path(text.value).resolve()
    def verify_owned_image(self,process,spec):
        self._process(process)
        if not process.job:raise RuntimeError('Image check requires established job ownership')
        actual=self._image(process.handle)
        if actual!=spec.path.resolve():raise RuntimeError('Actual owned engine image differs from pinned executable')
        self.events.append({'event':'actual_engine_image_verified','pid':process.pid,'image':str(actual)})
    def resume(self,thread):
        process=next((p for p in self.processes if p.thread==thread and p.handle),None)
        if process is None or not process.job:raise RuntimeError('Resume requires own assigned suspended engine')
        previous=self.kernel.ResumeThread(thread)
        if previous==0xffffffff:raise self._error('Resume owned engine')
        if previous!=1:raise RuntimeError('Unexpected suspend count; no repeated resume or fallback')
        self.events.append({'event':'resumed','pid':process.pid})
    def terminate_owned(self,process):
        self._process(process);self._check(self.kernel.TerminateProcess(process.handle,125),'Terminate own still-suspended engine')
    def wait_owned(self,process,seconds):
        self._process(process);status=self.kernel.WaitForSingleObject(process.handle,max(0,int(seconds*1000)))
        if status==0x102:return False
        if status!=0:raise self._error('Wait newly-owned engine')
        code=DWORD();self._check(self.kernel.GetExitCodeProcess(process.handle,C.byref(code)),'Read actual owned engine exit')
        process.exit_code=int(code.value);self.events.append({'event':'engine_exit_verified','pid':process.pid,'exit':process.exit_code});return True
    def active_count(self,job):
        self._job(job);info=Accounting();returned=DWORD()
        self._check(self.kernel.QueryInformationJobObject(job,1,C.byref(info),C.sizeof(info),C.byref(returned)),'Query only newly-owned engine job accounting')
        self.events.append({'event':'engine_job_accounting','active':int(info.active_processes),'total':int(info.total_processes),'returned_bytes':int(returned.value),'raw':bytes(info).hex()})
        if returned.value!=C.sizeof(info):raise RuntimeError('Unexpected engine-job accounting size')
        return int(info.active_processes)
    def member_pids(self,job):
        self._job(job);info=ProcessIds();returned=DWORD()
        self._check(self.kernel.QueryInformationJobObject(job,3,C.byref(info),C.sizeof(info),C.byref(returned)),'Query only newly-owned engine job members')
        self.events.append({'event':'engine_job_members','assigned':int(info.assigned),'count':int(info.count),'returned_bytes':int(returned.value),'raw':bytes(info)[:min(returned.value,C.sizeof(info))].hex()})
        if info.assigned>16 or info.count>16 or info.count>info.assigned:raise RuntimeError('Unexpected owned-job member count')
        if returned.value<8+int(info.count)*C.sizeof(SIZE_T) or returned.value>C.sizeof(info):raise RuntimeError('Unexpected engine-job member buffer size')
        return [int(info.pids[i]) for i in range(info.count)]
    def terminate_job(self,job):
        self._job(job);self._check(self.kernel.TerminateJobObject(job,125),'Terminate only newly-owned single engine job')
        self.events.append({'event':'owned_job_terminated'})
    def wait_job_empty(self,job,seconds):
        deadline=self.clock()+seconds
        while True:
            count=self.active_count(job)
            if count==0:
                self.events.append({'event':'owned_job_empty_verified','active':0});return True
            if self.clock()>=deadline:return False
            self.sleep(min(.025,max(0,deadline-self.clock())))
    def close_owned_handles(self,process,thread):
        if process is not None:
            self._process(process)
            if thread and thread==process.thread:self.kernel.CloseHandle(thread);process.thread=0
            self.kernel.CloseHandle(process.handle);process.handle=0
    def close_job(self,job):
        self._job(job);self._check(self.kernel.CloseHandle(job),'Close final noninherited owned job handle');self.jobs.remove(job)
