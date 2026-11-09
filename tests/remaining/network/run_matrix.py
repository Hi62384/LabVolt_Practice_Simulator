"""Leased2/8process ENet acceptance. One orchestrator, immutable source checks,
hard wall deadline, isolated saves/logs. Never kills a process it did not spawn.
"""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time

def inventory(project):
    return {p.relative_to(project).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(project.rglob('*')) if p.is_file()
        and not any(x in p.parts for x in ['.godot','__pycache__','.git'])}

def run(args):
    project=args.project.resolve();evidence=args.evidence.resolve()
    if evidence.exists():raise RuntimeError('Use a new evidence directory; never overwrite prior runs')
    evidence.mkdir(parents=True)
    baseline=inventory(project)
    if baseline!=json.loads(args.freeze.read_text()):raise RuntimeError('Source differs from frozen candidate; no child launched')
    (evidence/'source-before.json').write_text(json.dumps(baseline,indent=2))
    deadline=time.monotonic()+args.budget
    cases=[]
    for total,port in [(2,26002),(8,26008)]:
        # Reserve complete case + cleanup. Abort rather than starting past lease.
        if deadline-time.monotonic()<27:raise RuntimeError('Insufficient remaining lease; no next case')
        if inventory(project)!=baseline:raise RuntimeError('Source drift; no next case')
        folder=evidence/f'case-{total}';folder.mkdir()
        processes=[];handles=[];commands=[]
        started=time.monotonic();case_deadline=min(deadline-2,started+25)
        try:
            for slot in range(total):
                role='host' if slot==0 else 'client'
                output=folder/f'{role}-{slot}.json'
                log=folder/f'{role}-{slot}-console.log'
                env=os.environ.copy();env['APPDATA']=str(folder/f'userdata-{slot}')
                Path(env['APPDATA']).mkdir()
                command=[str(args.godot.resolve()),'--headless','--path',str(project),
                    '--log-file',str(folder/f'{role}-{slot}-engine.log'),
                    '--script','res://tests/remaining/network/peer.gd','--',
                    f'--role={role}',f'--slot={slot}',f'--total={total}',f'--port={port}',f'--output={output}']
                handle=log.open('w',encoding='utf-8');handles.append(handle)
                flags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name=='nt' else 0
                process=subprocess.Popen(command,env=env,cwd=project,stdout=handle,stderr=subprocess.STDOUT,creationflags=flags)
                processes.append(process);commands.append({'pid':process.pid,'command':command})
                if slot==0:
                    ready=Path(str(output)+'.ready')
                    while not ready.exists() and process.poll() is None and time.monotonic()<case_deadline:
                        time.sleep(.025)
                    if not ready.exists():raise RuntimeError('Host not ready')
            while any(p.poll() is None for p in processes) and time.monotonic()<case_deadline:
                time.sleep(.025)
            if any(p.poll() is None for p in processes):raise RuntimeError('Owned case deadline expired')
        finally:
            for p in processes:
                if p.poll() is None:
                    if os.name=='nt':
                        # Exact still-live child PID; /T includes only its descendant tree.
                        subprocess.run([str(Path(os.environ['SystemRoot'])/'System32/taskkill.exe'),'/PID',str(p.pid),'/T','/F'],capture_output=True,timeout=3)
                    else:p.kill()
                    p.wait(timeout=3)
            for handle in handles:handle.close()
            (folder/'launches.json').write_text(json.dumps({'commands':commands,'exit_codes':[p.returncode for p in processes],'elapsed_seconds':time.monotonic()-started},indent=2))
        errors=[];results=[]
        for slot in range(total):
            role='host' if slot==0 else 'client'
            path=folder/f'{role}-{slot}.json'
            if not path.exists():errors.append('Missing result '+str(slot));continue
            result=json.loads(path.read_text());results.append(result)
            errors.extend(result['failures'])
            text=(folder/f'{role}-{slot}-console.log').read_text(encoding='utf-8',errors='replace')
            errors.extend(line for line in text.splitlines() if ('ERROR' in line or 'WARNING' in line or 'FAIL' in line) and 'Failed to read the root certificate store.' not in line)
        if any(p.returncode for p in processes):errors.append('Nonzero exit')
        host=results[0] if results else {}
        measured={r['phase']:r for r in host.get('phases',[]) if 'queued_payload_bytes' in r}
        if set(measured)!={'separated','all-object-control'}:errors.append('Missing measured comparison phase')
        else:
            if not measured['separated'].get('workload_sha256') or measured['separated']['workload_sha256']!=measured['all-object-control'].get('workload_sha256'):errors.append('Comparison workloads differ')
            if measured['separated']['queued_payload_bytes']>=measured['all-object-control']['queued_payload_bytes']:errors.append('Separation did not reduce actual queued bytes')
        capture=folder/'host-0.json.workload.bin'
        capture_manifest=folder/'host-0.json.workload.json'
        if not capture.exists() or not capture_manifest.exists():errors.append('Missing authoritative replay capture')
        else:
            replay=json.loads(capture_manifest.read_text())
            if replay.get('frame_count')!=13 or len(replay.get('history',[]))!=13:errors.append('Replay must contain13 actual snapshots')
            if hashlib.sha256(capture.read_bytes()).hexdigest()!=replay.get('workload_sha256'):errors.append('Replay capture hash mismatch')
            if any(m.get('workload_sha256')!=replay.get('workload_sha256') for m in measured.values()):errors.append('Measured workload differs from capture')
        case={'players':total,'errors':errors,'metrics':measured,'elapsed_seconds':time.monotonic()-started}
        cases.append(case)
        (evidence/'matrix.json').write_text(json.dumps({'cases':cases,'source_stable':inventory(project)==baseline},indent=2))
        if errors:raise RuntimeError('Case failed; do not continue to next case')
    after=inventory(project)
    (evidence/'source-after.json').write_text(json.dumps(after,indent=2))
    if after!=baseline:raise RuntimeError('Source changed during measured window')
    print(json.dumps({'status':'WINDOW RELEASED','cases':cases,'source_stable':True}))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--godot',type=Path,required=True)
    parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parents[3])
    parser.add_argument('--evidence',type=Path,required=True)
    parser.add_argument('--freeze',type=Path,required=True)
    parser.add_argument('--budget',type=float,default=60)
    args=parser.parse_args()
    try:
        run(args)
    finally:
        # Preserve end hashes even when a case fails and the next is skipped.
        if args.evidence.exists():
            (args.evidence/'source-after.json').write_text(json.dumps(inventory(args.project.resolve()),indent=2))
        print('WINDOW RELEASED: orchestrator exited; owned children cleaned up',flush=True)
