"""Owned job controller; actual Windows backend requires a NEW granted admission.
Mock tests are not kernel containment proof. No implicit/fallback backend.
"""
import time

class EngineJobController:
    def __init__(self,api=None):
        if api is None:raise RuntimeError('ENGINE ONLY backend required; no process launched')
        self.api=api;self.job=None;self.engine=None;self.thread=None;self.resumed=False;self.failure_cleanup=None
    def start(self,engine_spec,arguments):
        self.job=self.api.create_job(kill_on_close=True,inheritable=False,breakaway=False,max_processes=1)
        try:
            self.engine,self.thread=self.api.create_suspended(engine_spec,arguments,inherit_job_handle=False)
            if not self.api.assign(self.job,self.engine):raise RuntimeError('Job assignment failed; never resume')
            self.api.verify_owned_image(self.engine,engine_spec)
            if self.api.active_count(self.job)!=1 or set(self.api.member_pids(self.job))!={self.engine.pid}:raise RuntimeError('Exactly one owned engine must be established before resume')
            self.api.resume(self.thread);self.resumed=True
        except BaseException:
            engine_exit=False;job_empty=False;handles_closed=True;errors=[]
            exit_code=None
            if self.engine is not None:
                if not self.resumed:
                    try:self.api.terminate_owned(self.engine)
                    except BaseException as error:errors.append('Owned startup terminate: '+str(error))
                try:
                    engine_exit=bool(self.api.wait_owned(self.engine,2))
                    exit_code=self.engine.exit_code
                    if not engine_exit:errors.append('Owned startup engine wait unverified')
                except BaseException as error:errors.append('Owned startup engine wait: '+str(error))
            else:
                # Creation did not return a process handle; Job0 is still required.
                engine_exit=True
            if self.job is not None:
                try:self.api.terminate_job(self.job)
                except BaseException as error:errors.append('Owned startup Job terminate: '+str(error))
                try:
                    job_empty=bool(self.api.wait_job_empty(self.job,2))
                    if not job_empty:errors.append('Owned startup Job empty unverified')
                except BaseException as error:errors.append('Owned startup Job wait: '+str(error))
            try:self.api.close_owned_handles(self.engine,self.thread)
            except BaseException as error:handles_closed=False;errors.append('Owned startup handle close: '+str(error))
            if self.job is not None:
                try:self.api.close_job(self.job)
                except BaseException as error:handles_closed=False;errors.append('Owned startup Job close: '+str(error))
            verified=bool(engine_exit and job_empty and handles_closed and not errors)
            self.failure_cleanup={'engine_created':self.engine is not None,'engine_exit_verified':engine_exit,'engine_exit_code':exit_code,'owned_job_empty_verified':job_empty,'handle_close_calls_completed':handles_closed,'stop_verified':verified,'errors':errors,'resource_hold_remains':not verified}
            raise
    def stop(self):
        errors=[]
        try:self.api.terminate_job(self.job)
        except OSError as error:errors.append('Owned job stop denied: '+str(error))
        try:engine_exit=self.api.wait_owned(self.engine,2)
        except OSError as error:engine_exit=False;errors.append('Owned engine exit verification denied: '+str(error))
        try:active=self.api.wait_job_empty(self.job,2) # only this unnamed owned job, no global/PID inventory
        except OSError as error:active=False;errors.append('Owned job empty verification denied: '+str(error))
        verified=bool(engine_exit and active)
        self.api.close_owned_handles(self.engine,self.thread)
        self.api.close_job(self.job) # kill-on-close remains the final owned-tree backstop
        return {'engine_exit_verified':bool(engine_exit),'owned_job_empty_verified':bool(active),'stop_verified':verified,'resource_hold_remains':not verified,'errors':errors}
