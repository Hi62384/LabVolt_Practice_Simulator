"""Bounded source/OBJ checks only. Does not invoke Godot or inspect the live game."""
from pathlib import Path
import json, math, hashlib, re

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'assets/instruments/physical'
manifest=json.loads((OUT/'mesh_manifest.json').read_text())
total=0
for name,meta in manifest['meshes'].items():
    vertices=[]; normals=[]; uv=[]; faces=[]; materials=set()
    current=''
    for line in (OUT/(name+'.obj')).read_text(encoding='utf-8').splitlines():
        p=line.split()
        if not p:continue
        if p[0]=='v':vertices.append(tuple(map(float,p[1:])))
        elif p[0]=='vt':uv.append(tuple(map(float,p[1:])))
        elif p[0]=='vn':normals.append(tuple(map(float,p[1:])))
        elif p[0]=='usemtl':current=p[1];materials.add(current)
        elif p[0]=='f':faces.append((current,[[int(x) for x in part.split('/')] for part in p[1:]]))
    assert len(vertices)==meta['vertices'] and len(faces)==meta['triangles']
    assert len(vertices)==len(uv)==len(normals) and len(materials)==meta['surfaces']
    assert len(materials)<=8 and len(faces)<=1500
    for v in vertices+normals+uv:assert all(math.isfinite(x) for x in v)
    for material,face in faces:
        assert len(face)==3 and material
        assert all(1<=i<=len(vertices) for part in face for i in part)
        a,b,c=(vertices[part[0]-1] for part in face)
        u=[b[i]-a[i] for i in range(3)];v=[c[i]-a[i] for i in range(3)]
        cross=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
        assert sum(x*x for x in cross)>1e-15
        n=normals[face[0][2]-1]
        assert sum(cross[i]*n[i] for i in range(3))>0
    assert all(abs(min(p[i] for p in vertices)-meta['bounds_min'][i])<1e-6 for i in range(3))
    assert all(abs(max(p[i] for p in vertices)-meta['bounds_max'][i])<1e-6 for i in range(3))
    total+=len(faces)
assert total<6500,total

source=(ROOT/'scripts/instruments/physical/bench_instruments.gd').read_text(encoding='utf-8')
station=(ROOT/'scripts/dc_station.gd').read_text(encoding='utf-8')
ports_line=station.split('const PORTS = ',1)[1].split('\n',1)[0]
for value in ['CH%d+'%i for i in (1,2,3)]+['CH%d-'%i for i in (1,2,3)]+['GEN','REF','VΩ','COM','A','S1','S2','GND','R1a','R1b','R2a','R2b','Ca','Cb','Da','Db','B1','B2','B3','B4']:
    assert '"'+value+'"' in ports_line,value
for suffix in ['', '2','3','4']:assert '"IS'+suffix+'+"' in ports_line and '"IS'+suffix+'-"' in ports_line
assert 'lab=owner' in source and 'station=index' in source
assert 'dc_instrument_control' in source and 'dc_port' in source and 'dc_panel' in source
assert 'state.get("meter"' in source and 'result.get("drop"' in source and 'result.get("i"' in source
patches=json.loads((ROOT/'review_artifacts/physical_instruments_20261106/shared_patch_manifest.json').read_text(encoding='utf-8'))
for row in patches:
    saved=(ROOT/'review_artifacts/physical_instruments_20261106'/Path(row['file']).name).with_suffix('.gd.preimage')
    assert saved.exists() and hashlib.sha256(saved.read_bytes()).hexdigest()==row['preimage_sha256']
print('Offline mesh/source contracts passed; %d OBJ triangles across reusable assets.'%total)
