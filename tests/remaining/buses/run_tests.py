"""Light native bus regressions. No game export, UI automation or production save access."""
import argparse,pathlib,subprocess,os,sys,json,hashlib
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--node',required=True);p.add_argument('--avr-bin',required=True);p.add_argument('--arduino-hex',required=True);p.add_argument('--logs',required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[3];logs=pathlib.Path(a.logs).resolve();logs.mkdir(parents=True,exist_ok=True);fixtures=logs/'firmware'
builds=[['python',str(root/'tests/remaining/buses/build_fixtures.py'),a.avr_bin,str(fixtures)],[a.node,str(root/'tests/remaining/buses/build_pico_fixtures.cjs'),str(fixtures)]]
for i,cmd in enumerate(builds):
 r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf-8',errors='replace',timeout=30)
 (logs/('build-'+str(i)+'.log')).write_text(r.stdout,encoding='utf-8')
 if r.returncode:print(r.stdout);sys.exit(r.returncode)
cases=[]
for name,script,extra in [('machine','tests/workers/firmware/test_machine.cjs',[]),('prior-timing','tests/campus/native/test_timing.cjs',[]),('compiled-arduino','tests/workers/firmware/test_compiled_arduino.cjs',[a.arduino_hex]),('reply-sequence','tests/remaining/buses/test_reply_sequence.cjs',[]),('bus-engine','tests/remaining/buses/test_bus_engine.cjs',[]),('group-engine','tests/remaining/buses/test_group.cjs',[str(fixtures)])]:cases.append((name,[a.node,str(root/script),*extra]))
for name,script in [('reply-validation','tests/remaining/buses/test_reply_validation.gd'),('contracts','tests/remaining/buses/test_contracts.gd'),('shared-solver','tests/remaining/buses/test_shared_solver.gd'),('group-scheduler','tests/remaining/buses/test_group_scheduler.gd'),('old-worker','tests/workers/firmware/test_worker.gd'),('legacy-firmware','tests/electronics/test_firmware.gd'),('legacy-nested','tests/electronics/test_nested_firmware.gd')]:cases.append((name,[a.godot,'--headless','--path',str(root),'--script','res://'+script]))
def source_hashes():
 result={}
 for folder in ['scripts/firmware_backends','scripts/electronics_buses','tests/remaining/buses']:
  for file in (root/folder).rglob('*'):
   if file.is_file():result[file.relative_to(root).as_posix()]=hashlib.sha256(file.read_bytes()).hexdigest()
 return result
before=source_hashes();(logs/'source-start.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
failed=0
for name,cmd in cases:
 env=dict(os.environ,APPDATA=str(logs/(name+'-appdata')),LABVOLT_BUS_FIXTURES=str(fixtures),LABVOLT_TEST_NODE=a.node);pathlib.Path(env['APPDATA']).mkdir(exist_ok=True)
 try:
  r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=env,encoding='utf-8',errors='replace',timeout=60)
  text=r.stdout;errors=[line for line in text.splitlines() if line.startswith('ERROR:') and line!='ERROR: Failed to read the root certificate store.']
  bad=bool(r.returncode or errors or any(x in text for x in ['SCRIPT ERROR','Parse Error','FAIL ']))
 except subprocess.TimeoutExpired as e:text=str(e);bad=True
 (logs/(name+'.log')).write_text(text,encoding='utf-8');(logs/(name+'-command.txt')).write_text(subprocess.list2cmdline(cmd),encoding='utf-8');failed+=bad;print(('FAIL ' if bad else 'PASS ')+name,flush=True)
after=source_hashes();(logs/'source-end.json').write_text(json.dumps(after,indent=2),encoding='utf-8');stable=before==after;failed+=not stable;print(('PASS ' if stable else 'FAIL ')+'source-stable',flush=True)
print('FAILED SUITES: '+str(failed),flush=True);sys.exit(bool(failed))
