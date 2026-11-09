from pathlib import Path
import hashlib,json,re,subprocess,sys,difflib
root=Path(__file__).resolve().parents[3]
here=Path(__file__).resolve().parent
guard=root/'review_artifacts/physical_instruments_20261106/ac_baseline_guard.py'
result=subprocess.run([sys.executable,str(guard)],capture_output=True,text=True)
guard_ok=result.returncode==0
lab=root/'scripts/dc_lab.gd'; text=lab.read_text(encoding='utf-8')
old='\t\tinstrument_fixtures[index].observe(state,delta,fixture_relevant)'
assert old in text
new='\t\t# Read opening transforms every presentation pass; rebuild cable geometry when anchors move.\n\t\tvar physical_ports: Dictionary=instrument_fixtures[index].port_positions()\n\t\tfor id in physical_ports:\n\t\t\tif ports[index].get(id)!=physical_ports[id]:drawn_revisions[index]=-1;external_signature=""\n\t\t\tports[index][id]=physical_ports[id]\n'+old
patch={'file':'scripts/dc_lab.gd','observed_sha256':hashlib.sha256(lab.read_bytes()).hexdigest(),'old':old,'new':new,'policy':'Main integrator only. Require exact old snippet once; re-review if changed. No production patch applied.'}
(here/'moving_endpoints.patch.json').write_text(json.dumps(patch,indent=2)+'\n')
checks=[]
for name in ['control_adapter.gd','device_binding.gd','socket_registry.gd','electrical_fixture.gd','physical_binding.gd','cable_binding.gd','assembled_fixture.gd']:
 source=(here/name).read_text(encoding='utf-8')
 for resource in re.findall(r'preload\("res://([^"]+)"\)',source):assert (root/resource).is_file(),resource
 assert 'const Skin ' not in source
 checks.append({'file':name,'sha256':hashlib.sha256((here/name).read_bytes()).hexdigest()})
adapter=(here/'control_adapter.gd').read_text()
for key in ['voltage','limit','enabled','frequency','amplitude','offset','phase','duty','resistance','timebase','scale','trigger','coupling','attenuation']:assert '"'+key+'"' in adapter
assert 'lab.request(station,action)' in (here/'device_binding.gd').read_text()
assert 'global_transform' in (here/'socket_registry.gd').read_text()
data=json.loads((here.parent/'physical_models/ports.json').read_text(encoding='utf-8'))
station=(root/'scripts/dc_station.gd').read_text(encoding='utf-8-sig')
ports=set(re.findall(r'"([^"\n]+)"',station.split('const PORTS = ',1)[1].split('\n',1)[0]))
assert {p['id'] for p in data['ports']}=={p for p in ports if not p.startswith('X')}
assert len(data['ports'])==34
expected={'psu':{'CH1+','CH1-','CH2+','CH2-','CH3+','CH3-'},'meter':{'VΩ','COM','A'},'generator':{'GEN','REF'},'scope':{'S1','S2','GND'}}
for device,ids in expected.items():assert {p['id'] for p in data['ports'] if p['device']==device}==ids
assert all(p['normal']==[0,0,1] and p['xyz'][2]==p['face_z'] for p in data['ports'])
assembled=text.replace(old,new)
mount_old='\tvar fixture := preload("res://scripts/instruments/physical/bench_instruments.gd").new()\n\torigin.add_child(fixture)\n\tfixture.build(self,index)\n\tinstrument_fixtures.append(fixture)'
mount_new='\tvar physical := preload("res://review_artifacts/m103_dc_rebuild_20261107/physical_models/fixture.gd").new()\n\torigin.add_child(physical)\n\tphysical.build(index)\n\tvar fixture := preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/physical_binding.gd").new()\n\torigin.add_child(fixture)\n\tfixture.bind(self,index,physical)\n\tinstrument_fixtures.append(fixture)'
assert mount_old in assembled;assembled=assembled.replace(mount_old,mount_new)
local='preload("res://scripts/cable_mesh.gd").build(a,b,Color("dc9d5b"),game.cable_obstacles)'
external='preload("res://scripts/cable_mesh.gd").build(a,b,Color("dba45b"),game.cable_obstacles)'
assert local in assembled and external in assembled
assembled=assembled.replace(local,'preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/cable_binding.gd").from_ports(self,index,str(wire[0]),a,index,str(wire[1]),b,Color("dc9d5b"),game.cable_obstacles)')
assembled=assembled.replace(external,'preload("res://review_artifacts/m103_dc_rebuild_20261107/bindings/cable_binding.gd").from_ports(self,int(link.a.station),str(link.a.port),a,int(link.b.station),str(link.b.port),b,Color("dba45b"),game.cable_obstacles)')
if (here/'dc_lab.preimage').exists():assert (here/'dc_lab.preimage').read_bytes()==lab.read_bytes(),'Pinned production source changed; main must reconcile.'
else:(here/'dc_lab.preimage').write_bytes(lab.read_bytes())
(here/'dc_lab.assembled.gd').write_text(assembled,encoding='utf-8')
(here/'dc_lab.patch').write_text(''.join(difflib.unified_diff(text.splitlines(True),assembled.splitlines(True),fromfile='a/scripts/dc_lab.gd',tofile='b/scripts/dc_lab.gd')),encoding='utf-8')
(here/'integration_manifest.json').write_text(json.dumps({'source':'scripts/dc_lab.gd','preimage_sha256':hashlib.sha256(lab.read_bytes()).hexdigest(),'new_sha256':hashlib.sha256((here/'dc_lab.assembled.gd').read_bytes()).hexdigest(),'policy':'Apply this combined patch ONLY; supersedes model dc_lab_mount.patch and moving_endpoints.patch.json.'},indent=2)+'\n')
def functions(source):
 matches=list(re.finditer(r'^func (\w+)\(',source,re.M))
 return {m[1]:source[m.start():matches[i+1].start() if i+1<len(matches) else len(source)] for i,m in enumerate(matches)}
before_functions=functions(text);after_functions=functions(assembled)
for name in before_functions:
 if name not in ['build_bench','_process','draw_external_links']:assert before_functions[name]==after_functions[name],name
assert 'physical.bind' not in assembled and 'fixture.bind(self,index,physical)' in assembled
model_validator=subprocess.run([sys.executable,str(here.parent/'physical_models/validate.py')],capture_output=True,text=True)
assert model_validator.returncode==0,model_validator.stdout+model_validator.stderr
report={'ac_guard':result.stdout.strip(),'files':checks,'fixed_ports':34,'device_parent_sets':'pass','runtime':'NOT RUN; guarded fixtures only','physical_contract':(here.parent/'CONTRACT.md').exists()}
(here/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
if not guard_ok:raise SystemExit('AC guard FAILED: '+result.stdout+result.stderr)
