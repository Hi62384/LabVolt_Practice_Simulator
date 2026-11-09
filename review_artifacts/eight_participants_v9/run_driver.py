"""Actual-Main staged runner. DO NOT invoke execution without root's exact resource lease.
Only this source's deterministic evidence unit tests are initially authorized.
"""
import argparse
import json
import os
import shutil
from pathlib import Path
import time
from evidence import registered, stable_paper, privacy, exactly_once, randomized, late_join, practice_excluded, need, fingerprint, saved_assessment
from backend_adapter import CoreEngineSet

class Run:
    def __init__(self, plan):
        self.plan=plan;self.root=Path(plan['output']);self.project=Path(plan['project'])
        self.roles=['host']+[f'client{i}' for i in range(1,plan['participants'])]
        self.sequence={r:0 for r in self.roles};self.latest={};self.end=time.monotonic()+plan['wall_seconds']-12
        self.job=None
    def guard(self):
        self.plan['_lease_check']()
        need(time.monotonic()<self.end,'global stage watchdog')
        for i in range(len(self.job.processes)):
            need(self.job.exit_code(i) is None,'owned peer exited prematurely')
    @staticmethod
    def command_limit(command):
        return {'travel':30.,'prepare_room':30.,'reload_solo_saved':15.,'activity':10.}.get(command['op'],5.)
    def last_progress(self,role,sequence):
        files=sorted((self.root/role).glob(f'progress-{sequence:04d}-*.json'))
        if not files:return {'available':False}
        try:
            value=json.loads(files[-1].read_text(encoding='utf-8'))
            keys=('sequence','op','label','detail','elapsed_ms','player_local','player_global','accepted_position','target','velocity','on_floor','seated','local_pose_epoch','accepted_pose_epoch','accepted_room','room_id','travel','waypoint')
            return {key:value.get(key) for key in keys}
        except (OSError,ValueError):return {'available':False,'reason':'Unreadable immutable progress packet'}
    def wait_file(self,path,deadline=None,label='startup ready'):
        until=min(self.end,time.monotonic()+15 if deadline is None else deadline)
        while not path.exists():
            self.guard()
            need(time.monotonic()<until,'explicit command/startup timeout: '+label)
            time.sleep(.05)
        return json.loads(path.read_text(encoding='utf-8-sig'))
    def commands(self,commands):
        paths={}
        for role,command in commands.items():
            seq=self.sequence[role];directory=self.root/role;limit=self.command_limit(command)
            path=directory/f'command-{seq:04d}.json';tmp=path.with_suffix('.tmp')
            payload=dict(command,timeout_seconds=limit)
            tmp.write_text(json.dumps(payload),encoding='utf-8');tmp.replace(path)
            paths[role]=(directory/f'result-{seq:04d}.json',min(self.end,time.monotonic()+limit),seq,command['op']);self.sequence[role]+=1
        for role,(path,deadline,seq,op) in paths.items():
            try:self.latest[role]=self.wait_file(path,deadline,f'{role} sequence={seq} op={op}')
            except BaseException:
                progress=self.last_progress(role,seq)
                (self.root/(role+'-last-command-progress.json')).write_text(json.dumps(progress,indent=2),encoding='utf-8')
                raise
        return {r:self.latest[r] for r in commands}
    def all(self,command,roles=None):
        return self.commands({r:command for r in (roles or self.roles)})
    def poll(self,roles,predicate):
        while True:
            self.all({'op':'observe'},roles)
            if predicate():return
            self.guard();time.sleep(.1)
    def shutdown_transports(self):
        frozen={role:self.latest[role] for role in self.roles}
        (self.root/'pre-shutdown-lifecycle-evidence.json').write_text(json.dumps(frozen,indent=2),encoding='utf-8')
        if len(self.roles)>1:
            need(all(frozen[role]['phase']=='complete' for role in self.roles),'Network grading must complete before final disconnect')
            departing={role:int(frozen[role]['peer']) for role in self.roles[1:]}
            profiles={role:frozen[role]['local_identity_sha256'] for role in self.roles}
            self.all({'op':'leave'},self.roles[1:])
            for role in self.roles[1:]:
                state=self.latest[role]['transport']
                need(state['online'] is False and state['offline_peer'] is True,'Client actual offline acknowledgement required')
                need(state['last_connected_peer_id']==departing[role] and state['role']==role,'Preserved departing identity/role required')
                need(self.latest[role]['local_identity_sha256']==profiles[role],'Disconnect changed profile')
            self.poll(['host'],lambda:all(str(peer) not in self.latest['host']['roster'] and peer not in self.latest['host']['transport']['connected_peers'] for peer in departing.values()))
            self.commands({'host':{'op':'leave'}})
        self.all({'op':'verify_offline'})
        for role in self.roles:
            after=self.latest[role]
            for field in ('gradebook','reward_ids','dollars'):
                need(frozen[role][field]==after[field],'Final transport closure changed '+field+' for '+role)
        (self.root/'post-shutdown-offline-evidence.json').write_text(json.dumps(self.latest,indent=2),encoding='utf-8')
    def start(self):
        need(self.plan['root_lease_id'],'root lease identifier required')
        owned_project=Path('C:\\Users\\User1\\Documents\\Codex\\2026-11-05\\task-6\\eight_participants_v7\\project')
        need(self.project.resolve()==owned_project,'only the assigned private project may be used')
        runs=Path(__file__).resolve().parent/'run-data'
        need(self.root.resolve().is_relative_to(runs.resolve()),'output must stay in isolated run-data')
        need(self.plan['participants'] == 8 and self.plan['total_engine_jobs'] == 8,'exactly host plus seven engines required')
        need(self.plan['wall_seconds'] == 300,'exact proposed 300-second window required')
        need(self.plan['port'] in (27096,27097,27098,27099),'proposed case-specific port required')
        engine=Path(self.plan['engine'])
        need(fingerprint(engine)==self.plan['engine_sha256'],'engine identity changed')
        for relative,expected in self.plan['source_sha256'].items():
            need(fingerprint(self.project/relative)==expected,'source drift: '+relative)
        for relative,expected in self.plan['cache_sha256'].items():
            need(fingerprint(self.project/'.godot'/relative)==expected,'cache drift: '+relative)
        need(not self.root.exists(),'fresh output/APPDATA directory required')
        self.root.mkdir(parents=True)
        self.job=CoreEngineSet(self.plan,json.loads(Path(self.plan['backend_binding']).read_text(encoding='utf-8')))
        try:
            for ordinal,role in enumerate(self.roles):
                directory=self.root/role;directory.mkdir()
                for name in ('APPDATA','LOCALAPPDATA','TEMP'):(directory/name).mkdir()
                env=os.environ.copy()
                for name in ('APPDATA','LOCALAPPDATA','TEMP'):env[name]=str(directory/name)
                env['TMP']=env['TEMP']
                runtime_project=directory/'project'
                shutil.copytree(self.project,runtime_project)
                for relative,expected in self.plan['source_sha256'].items():
                    need(fingerprint(runtime_project/relative)==expected,'copied source drift: '+relative)
                for relative,expected in self.plan['cache_sha256'].items():
                    need(fingerprint(runtime_project/'.godot'/relative)==expected,'copied cache drift: '+relative)
                config=dict(role=role,ordinal=ordinal,participants=self.plan['participants'],course=self.plan['course'],port=self.plan['port'],
                            control=str(directory),watchdog_seconds=self.plan['wall_seconds']-15)
                config_path=directory/'peer.json';config_path.write_text(json.dumps(config),encoding='utf-8')
                argv=[str(engine),'--headless','--path',str(runtime_project),'--script',
                      'res://tests/acceptance/classroom_network/peer.gd','--',str(config_path)]
                owned_index=self.job.start(argv,runtime_project,env,directory/'engine.log')
                provenance=dict(owned_pid=self.job.processes[owned_index].pid,argv=[str(engine),'--log-file',str(directory/'engine.log'),*argv[1:]],
                                engine_sha256=self.plan['engine_sha256'],config_sha256=fingerprint(config_path),
                                APPDATA=self.job.entries[owned_index]['environment']['APPDATA'],LOCALAPPDATA=self.job.entries[owned_index]['environment']['LOCALAPPDATA'],runtime_project=str(runtime_project))
                (directory/'owned-launch.json').write_text(json.dumps(provenance,indent=2),encoding='utf-8')
                self.latest[role]=self.wait_file(directory/'ready.json')
            self.lifecycle()
            self.shutdown_transports()
            for role in self.roles:
                seq=self.sequence[role];path=self.root/role/f'command-{seq:04}.json'
                temp=path.with_suffix('.tmp');temp.write_text(json.dumps({'op':'quit'}),encoding='utf-8');temp.replace(path)
            self.job.wait_normal_all(min(self.end,time.monotonic()+6))
        finally:
            # Only the exact unnamed Job and handles created above are touched.
            cleanup=self.job.close()
            (self.root/'owned-job-cleanup.json').write_text(json.dumps(cleanup),encoding='utf-8')
            need(not cleanup['resource_hold_remains'] and cleanup['owned_job_zero_verified'],'Exact core-backend owned Job0 cleanup is unproven')
        for role in self.roles:
            log=(self.root/role/'engine.log').read_text(encoding='utf-8',errors='replace')
            bad=[line for line in log.splitlines() if any(marker in line for marker in ('ERROR','WARNING','Assertion failed','CLASSROOM_ACCEPTANCE')) and 'Failed to read the root certificate store.' not in line]
            need(not bad,role+' strict engine diagnostics failed; inspect raw log')
            for relative,digest in self.plan['source_sha256'].items():
                need(fingerprint(self.root/role/'project'/relative)==digest,'Runtime source changed: '+relative)
            for relative,digest in self.plan['cache_sha256'].items():
                need(fingerprint(self.root/role/'project'/'.godot'/relative)==digest,'Runtime cache changed: '+relative)
    def lifecycle(self):
        solo=self.plan['scenario']=='solo_save'
        early=self.roles if self.plan['scenario'] in ('lifecycle','solo_save') else self.roles[:-1]
        self.commands({'host':{'op':'solo' if solo else 'host'}})
        if len(early)>1:self.all({'op':'join'},early[1:])
        self.poll(early,lambda:len(self.latest['host']['identities'])==len(early))
        if len(early)==len(self.roles) and not solo:
            self.poll(self.roles,lambda:all(len(self.latest[r]['roster'])==len(self.roles) for r in self.roles))
            registered(self.latest['host'],[self.latest[r] for r in self.roles[1:]],len(self.roles))
        activity=dict(mode='Course',course_id=self.plan['course'],kind=self.plan['kind'],week=self.plan['week'],difficulty=self.plan['difficulty'],
                      teaching_seconds=300,assessment_seconds=180)
        self.commands({'host':{'op':'activity','config':activity}})
        self.poll(early,lambda:all(self.latest[r]['phase']=='travel' for r in early))
        if int(self.latest['host']['activity']['room'].get('floor',0))==1:
            actual_peers={role:int(self.latest[role]['peer']) for role in early}
            self.commands({'host':{'op':'approach_setup'}})
            placements={row['peer']:row for row in self.latest['host']['approach_evidence']['placements']}
            self.commands({role:dict(op='verify_approach',source_peer=actual_peers[role],epoch=placements[actual_peers[role]]['epoch_after'],destination=placements[actual_peers[role]]['destination']) for role in early})
            self.all({'op':'observe'},early)
        self.all({'op':'prepare_room'},early)
        if self.plan['kind']=='lecture':
            self.poll(['host'],lambda:len(self.latest['host']['occupied_chairs'])==len(early))
        self.commands({'host':{'op':'begin'}})
        self.commands({'host':{'op':'advance_teaching'}})
        self.poll(early,lambda:all(self.latest[r]['phase']=='assignment' for r in early))
        # The room slip occupies the hand; stow it through the ordinary paper action.
        self.all({'op':'request','selector':'any','action':{'op':'stow'}},early)
        if self.plan['kind']=='lab':self.all({'op':'travel','target':'paper'},early)
        self.all({'op':'request','selector':'official','action':{'op':'pickup'}},early)
        from course_fixture_contract import load_fixture,answer_commands
        fixture=load_fixture(self.plan)
        self.all({'op':'observe'},early)
        for batch in answer_commands(fixture,self.latest):self.commands(batch)
        self.all({'op':'request','selector':'official','action':{'op':'stroke','page':1,'points':[[.2,.3],[.4,.5]]}},early)
        self.all({'op':'request','selector':'official','action':{'op':'page','page':1}},early)
        self.all({'op':'observe'},early)
        self.commands({'host':{'op':'checkpoint'}})
        from guards import projection_group,journal_binding,practice_link,duplicate_processed
        projection_group(self.latest['host'],[self.latest[r] for r in self.roles[1:]],self.plan['course'],self.latest['host']['assessment_id'],pre_submit=True)
        (self.root/'guard-pre-submit-coverage.json').write_text(json.dumps(self.latest,indent=2),encoding='utf-8')
        saved_assessment(self.latest['host'])
        journal_binding(self.latest['host'])
        if self.plan['course']=='MTH147':
            seeded=self.latest['host']['mth147_seeded']
            need(len(seeded)==8 and all(row['seed_matches_identity_attempt'] for row in seeded),'eight issued math seeds must bind original attempt and identity')
        if solo:
            before=self.latest['host']
            (self.root/'before-solo-reload.json').write_text(json.dumps(before),encoding='utf-8')
            self.commands({'host':{'op':'reload_solo_saved'}})
            self.all({'op':'observe'})
            stable_paper(before,self.latest['host'],require_new_peer=False)
            need(before['gradebook']==self.latest['host']['gradebook'],'scene reload created an official grade')
            need(before['reward_ids']==self.latest['host']['reward_ids'],'scene reload duplicated a reward')
            (self.root/'after-solo-reload.json').write_text(json.dumps(self.latest['host']),encoding='utf-8')
            return
        if self.plan['scenario']=='late':
            late=self.roles[-1];self.commands({late:{'op':'join'}})
            self.poll(self.roles,lambda:len(self.latest['host']['identities'])==len(self.roles) and self.latest[late]['phase']=='assignment')
            registered(self.latest['host'],[self.latest[r] for r in self.roles[1:]],len(self.roles))
            late_join(self.latest[late]);privacy(self.latest[late])
            if self.plan['kind']=='lab':self.commands({late:{'op':'travel','target':'teacher'}})
            before_practice=self.latest[late]
            self.commands({late:{'op':'request','selector':'practice','action':{'op':'answer','key':'0','value':{}}}})
            self.commands({late:{'op':'request','selector':'practice','action':{'op':'submit'}}})
            self.poll([late],lambda:any(p['owner']==self.latest[late]['peer'] and p['marked'] and not p['official'] for p in self.latest[late]['papers']))
            practice_excluded(before_practice,self.latest[late])
            need(before_practice['reward_ids']==self.latest[late]['reward_ids'],'late practice unexpectedly awarded an official reward')
            (self.root/'late-observation.json').write_text(json.dumps(self.latest[late]),encoding='utf-8')
            return
        client='client1';before=self.latest[client]
        (self.root/'before-rejoin.json').write_text(json.dumps(before),encoding='utf-8')
        self.commands({client:{'op':'leave'}})
        self.poll(['host'],lambda:len(self.latest['host']['identities'])==len(self.roles)-1)
        self.commands({client:{'op':'join'}})
        self.poll([client,'host'],lambda:len(self.latest['host']['identities'])==len(self.roles) and self.latest[client]['phase']=='assignment')
        stable_paper(before,self.latest[client]);privacy(self.latest[client])
        (self.root/'after-rejoin.json').write_text(json.dumps(self.latest[client]),encoding='utf-8')
        rejoined=int(self.latest[client]['peer']); departed=int(before['peer'])
        need(rejoined != departed, 'Reconnect must produce a distinct actual peer ID')
        self.commands({'host':dict(op='reconcile_rejoin',source_peer=rejoined,previous_peer=departed,profile_sha256=before['local_identity_sha256'])})
        placement=self.latest['host']['approach_evidence']['placements'][0]
        need(placement['peer']==rejoined and placement['previous_peer']==departed, 'Reconnect placement ID mismatch')
        self.commands({client:dict(op='verify_approach',source_peer=rejoined,epoch=placement['epoch_after'],destination=placement['destination'])})
        stable_paper(before,self.latest[client]);privacy(self.latest[client])
        (self.root/'after-rejoin-pose-fixture.json').write_text(json.dumps(self.latest[client]),encoding='utf-8')
        self.poll(self.roles,lambda:all(set(map(int,self.latest[r]['roster']))==set(map(int,self.latest['host']['identities'])) for r in self.roles))
        projection_group(self.latest['host'],[self.latest[r] for r in self.roles[1:]],self.plan['course'],self.latest['host']['assessment_id'],pre_submit=True)
        (self.root/'guard-rejoin-all-client-coverage.json').write_text(json.dumps(self.latest,indent=2),encoding='utf-8')

        self.commands({client:{'op':'travel','target':'paper'}})
        self.commands({client:{'op':'request','selector':'official','action':{'op':'pickup'}}})
        if self.plan['kind']=='lecture':self.commands({client:{'op':'prepare_room'}})
        else:self.all({'op':'travel','target':'teacher'})
        self.all({'op':'request','selector':'official','action':{'op':'submit'}})
        self.poll(self.roles,lambda:all(any(p['official'] and p['owner']==self.latest[r]['peer'] and p['marked'] for p in self.latest[r]['papers']) for r in self.roles))
        # Allow normal host-authority reward synchronization, never client-supplied rewards.
        self.poll(self.roles,lambda:all(any(k.startswith('assessment:') for k in self.latest[r]['reward_ids']) for r in self.roles))
        from copy import deepcopy
        remote='client7'
        self.all({'op':'observe'})
        before_duplicate=deepcopy(self.latest[remote])
        paper=[p for p in before_duplicate['papers'] if p['official'] and p['owner']==before_duplicate['peer']]
        need(len(paper)==1 and paper[0]['marked'],'one exact marked remote paper required')
        action={'op':'submit','id':paper[0]['id']}
        command_sequence=self.sequence[remote]+1
        request_id=f"{self.plan['course']}:{before_duplicate['assessment_id']}:{before_duplicate['peer']}:{command_sequence}"
        self.commands({remote:{'op':'guard_duplicate_quiet_start'}})
        quiet_started=time.monotonic()
        while (time.monotonic()-quiet_started)*1000<=1050:
            self.guard();time.sleep(.05)
        quiet_ms=int((time.monotonic()-quiet_started)*1000)
        context=dict(peer=before_duplicate['peer'],paper_id=paper[0]['id'],assessment_id=before_duplicate['assessment_id'],profile_sha256=before_duplicate['local_identity_sha256'],course=self.plan['course'],op='submit',request_id=request_id,sequence=command_sequence)
        self.commands({'host':{'op':'guard_duplicate_arm','peer':before_duplicate['peer'],'action':action,'context':context,'quiet_ms':quiet_ms}})
        self.commands({remote:{'op':'guard_duplicate_dispatch','action':action,'command_sequence':command_sequence}})
        self.commands({'host':{'op':'guard_duplicate_record_dispatch','action':action}})
        self.commands({'host':{'op':'guard_duplicate_collect'}})
        self.all({'op':'observe'},[remote,'host'])
        callback=self.latest['host']['duplicate_observation']
        need(callback.get('source')=='test-instrumented-host' and callback.get('dispatches')==1,'passive host callback provenance/dispatch count')
        dispatch=self.latest[remote]['duplicate_dispatch']
        need(dispatch.get('dispatches')==1 and dispatch.get('quiet_ms',0)>1000 and dispatch.get('command_sequence')==command_sequence,'single remote dispatch and measured sender quiet interval')
        need(dispatch.get('action_sha256')==callback['receipt'].get('request_sha256'),'remote action and host callback digest mismatch')
        duplicate_processed(before_duplicate,self.latest[remote],self.plan['course'],callback['receipt'],callback['request_context'])
        privacy(self.latest[remote])
        (self.root/'test-instrumented-host-duplicate.json').write_text(json.dumps({'before':before_duplicate,'after':self.latest[remote],'callback':callback,'dispatch':dispatch},indent=2),encoding='utf-8')
        self.all({'op':'observe'},['host'])
        for paper in self.latest['host']['papers']:
            if not paper['official']:continue
            expected=paper['host_written_oracle']
            if paper['written_score'] is not None:
                need(paper['written_score']==expected,'host written grade disagrees with provider')
                expected=.5*expected+.5*paper['practical'].get('score',0)
            need(paper['score']==expected,'host grade disagrees with actual provider/equipment capture')
        if self.plan['course'] in ('MTH147','MTH255'):
            randomized(self.latest['host'])
        # ELM253/ETY155 requirement and legitimate shared practical plans are audited by the variants owner.
        # Never infer missing calculation randomization solely from shared class-project fingerprints.
        from eight_evidence import complete_eight
        complete_eight(self.latest,self.plan['course'])
        projection_group(self.latest['host'],[self.latest[r] for r in self.roles[1:]],self.plan['course'],self.latest['host']['assessment_id'],pre_submit=False)
        from course_fixture_contract import expected_marks
        expected_marks(fixture,self.latest)
        (self.root/'course-fixture-expectations.json').write_text(json.dumps(fixture,indent=2),encoding='utf-8')
        (self.root/'lifecycle-observations.json').write_text(json.dumps(self.latest),encoding='utf-8')
        # Actual normal new request, singleton owned delta, then exact-ID actions.
        self.commands({remote:{'op':'request','selector':'official','action':{'op':'stow'}}})
        self.commands({remote:{'op':'travel','target':'teacher'}})
        before_practice=deepcopy(self.latest[remote])
        self.commands({remote:{'op':'guard_new_practice','week':self.plan['week'],'difficulty':self.plan['difficulty']}})
        issued=deepcopy(self.latest[remote]);new_id=issued['practice_request_link']['paper_id']
        value={} if self.plan['course'].startswith('MTH') else 'not-a-number'
        self.commands({remote:{'op':'guard_practice_action','action':{'op':'answer','key':'0','value':value}}})
        self.commands({remote:{'op':'guard_practice_action','action':{'op':'submit'}}})
        self.poll([remote],lambda:any(p['id']==new_id and p['owner']==self.latest[remote]['peer'] and p['marked'] for p in self.latest[remote]['papers']))
        practice_link(before_practice,issued,self.latest[remote],self.plan['course'])
        (self.root/'guard-new-practice-link.json').write_text(json.dumps({'before':before_practice,'issued':issued,'after':self.latest[remote]},indent=2),encoding='utf-8')


