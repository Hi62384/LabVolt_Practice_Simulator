"""Two-process ENet regression of Faculty audio; synthetic speech provider only."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',required=True);p.add_argument('--logs',required=True)
a=p.parse_args()
root=Path(__file__).resolve().parents[3]
logs=Path(a.logs).resolve();logs.mkdir(parents=True,exist_ok=True)
with socket.socket() as reserve:
    reserve.bind(('127.0.0.1',0));port=reserve.getsockname()[1]
processes={};handles={};profiles=[]
try:
    for role in ('host','client'):
        profile=tempfile.TemporaryDirectory(prefix=role+'-',dir=logs);profiles.append(profile)
        env=dict(os.environ,XDG_DATA_HOME=profile.name,APPDATA=profile.name)
        handles[role]=(logs/(role+'.log')).open('w')
        command=[a.godot,'--headless','--path',str(root),'--script','res://tests/campus/academics/test_speech_audio_network.gd','--',role,str(port)]
        processes[role]=subprocess.Popen(command,stdout=handles[role],stderr=subprocess.STDOUT,env=env)
        if role=='host':
            until=time.monotonic()+12
            while time.monotonic()<until:
                output=(logs/'host.log').read_text()
                if 'SPEECH_AUDIO_HOST_READY' in output:break
                if processes[role].poll() is not None or 'SCRIPT ERROR' in output:raise RuntimeError('Host startup failed: '+output[-3000:])
                time.sleep(.03)
            else:raise RuntimeError('Host readiness timeout')
    deadline=time.monotonic()+35
    for role,process in processes.items():process.wait(timeout=max(.1,deadline-time.monotonic()))
    report={'transport':'real ENet localhost, two processes','speech_provider':'synthetic fixture','live_api':False,'cases':[]}
    for role,process in processes.items():
        output=(logs/(role+'.log')).read_text()
        passed=process.returncode==0 and 'SPEECH_AUDIO_'+role.upper()+' PASS' in output and not any(x in output for x in ('SCRIPT ERROR','ERROR:','Assertion failed'))
        report['cases'].append({'role':role,'passed':passed,'exit_code':process.returncode})
        print(('PASS ' if passed else 'FAIL ')+role,flush=True)
        if not passed:print(output[-4000:])
    (logs/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(int(any(not c['passed'] for c in report['cases'])))
finally:
    for process in processes.values():
        if process.poll() is None:process.terminate()
    for process in processes.values():
        try:process.wait(timeout=3)
        except subprocess.TimeoutExpired:process.kill();process.wait()
    for handle in handles.values():handle.close()
    for profile in profiles:profile.cleanup()
