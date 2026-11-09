"""Create a preimage-bound M103 mounting patch; never writes production source."""
from pathlib import Path
import difflib, hashlib, json

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
target=ROOT/'scripts/dc_lab.gd'
before_bytes=target.read_bytes()
before=before_bytes.decode('utf-8-sig')
old='''\tvar fixture := preload("res://scripts/instruments/physical/bench_instruments.gd").new()
\torigin.add_child(fixture)
\tfixture.build(self,index)
\tinstrument_fixtures.append(fixture)
\tvar display := Label3D.new()
\torigin.add_child(display)
\tdisplay.visible=false
\tdisplays.append(display)
\tports.append(fixture.port_positions())'''
new='''\tvar physical := preload("res://review_artifacts/m103_dc_rebuild_20261107/physical_models/fixture.gd").new()
\torigin.add_child(physical)
\tphysical.build(index)
\tvar binding := preload("res://scripts/ui/instrument_panels/physical_binding.gd").new()
\torigin.add_child(binding)
\tbinding.bind(self,index,physical)
\tinstrument_fixtures.append(binding)
\tvar display := Label3D.new()
\torigin.add_child(display)
\tdisplay.visible=false
\tdisplays.append(display)
\tports.append(physical.port_positions())'''
assert before.count(old)==1,'Current DC mounting preimage changed; review manually'
after=before.replace(old,new,1)
(OUT/'dc_lab_mount.preimage').write_bytes(before_bytes)
(OUT/'dc_lab_mount.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/scripts/dc_lab.gd',tofile='b/scripts/dc_lab.gd')),encoding='utf-8')
(OUT/'MOUNT_MANIFEST.json').write_text(json.dumps({'target':'scripts/dc_lab.gd','preimage_sha256':hashlib.sha256(before_bytes).hexdigest(),
 'proposed_sha256':hashlib.sha256(after.encode('utf-8')).hexdigest(),
 'dependency':'res://scripts/ui/instrument_panels/physical_binding.gd from binding owner',
 'status':'staged only; main integrates after binding script and asset import checks'},indent=2)+'\n',encoding='utf-8')
