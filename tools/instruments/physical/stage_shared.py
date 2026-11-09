"""Prepare reviewable, preimage-bound shared hooks; never edits shared files."""
from pathlib import Path
import difflib, hashlib, json

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'review_artifacts/physical_instruments_20261106'
OUT.mkdir(parents=True,exist_ok=True)

def stage(name, edits):
    path=ROOT/name
    original=path.read_bytes()
    before=original.decode('utf-8-sig')
    after=before
    for old,new in edits:
        assert after.count(old)==1,(name,old[:90],after.count(old))
        after=after.replace(old,new,1)
    assert after!=before
    patch=''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/'+name,tofile='b/'+name))
    (OUT/(Path(name).name+'.patch')).write_text(patch,encoding='utf-8')
    (OUT/(Path(name).name+'.preimage')).write_bytes(original)
    return {'file':name,'preimage_sha256':hashlib.sha256(original).hexdigest(),'proposed_sha256':hashlib.sha256(after.encode('utf-8')).hexdigest(),'patch':Path(name).name+'.patch'}

lab='scripts/dc_lab.gd'
source=(ROOT/lab).read_text(encoding='utf-8-sig')
begin=source.index('\tgame._box(origin,Vector3(0,1.3,-.45)')
end=source.index('\tports.append(locations)',begin)+len('\tports.append(locations)')
old=source[begin:end]
new='''\tvar fixture := preload("res://scripts/instruments/physical/bench_instruments.gd").new()
\torigin.add_child(fixture)
\tfixture.build(self,index)
\tvar display := Label3D.new()
\torigin.add_child(display)
\tdisplay.visible=false
\tdisplays.append(display)
\tports.append(fixture.port_positions())'''
records=[stage(lab,[(old,new),
('var displays: Array=[]','var displays: Array=[]\nvar instrument_fixtures: Array=[]'),
('\tfixture.build(self,index)','\tfixture.build(self,index)\n\tinstrument_fixtures.append(fixture)'),
('\tif target.get_meta("role")=="dc_panel":ui.open(index);return true',
 '''\tif target.get_meta("role")=="dc_instrument_control":
\t\tvar physical_action: Dictionary=instrument_fixtures[index].action_for(target,right,states[index])
\t\tif not physical_action.is_empty():request(index,physical_action)
\t\treturn true
\tif target.get_meta("role")=="dc_panel":ui.open(index);return true'''),
('\t\tcampus_readouts.observe(str(index),state,displays[index],display_relevant)',
'\t\tvar fixture_relevant: bool=instrument_fixtures[index].global_position.distance_squared_to(game.camera.global_position)<=144.0\n\t\tinstrument_fixtures[index].observe(state,delta,fixture_relevant)')])]
game='scripts/game.gd'
records.append(stage(game,[( '''\t\telif role=="dc_port":''', '''\t\telif role=="dc_instrument_control":
\t\t\thint="Click: "+str(current_target.get_meta("label","Instrument control"))
\t\telif role=="dc_port":''')]))
(OUT/'shared_patch_manifest.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
