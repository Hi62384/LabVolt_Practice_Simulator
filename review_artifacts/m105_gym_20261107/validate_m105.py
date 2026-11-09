"""Offline geometry, interaction and assembly contract; never starts the engine."""
from pathlib import Path
import hashlib,json,math
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
p=HERE/'generated/profiles.json'
d=json.loads(p.read_text())
g=d['profiles']['gym']
room=next(r for r in json.loads((ROOT/'assets/campus/world/room_registry.json').read_text())['rooms'] if r['id']=='gym')
assert g['origin']==room['center']
assert len(g['groups'])<=12
assert g['triangles']<=16000
roles={o['role'] for o in g['objects']}
assert {'surface','wall','ceiling','furniture'}<=roles
for o in g['objects']:
    lo,hi=o['min'],o['max']
    assert all(-10.001<=lo[0]<=hi[0]<=10.001 for _ in [0]),o['name']
    assert -.01<=lo[1]<=hi[1]<=4.05,o['name']
    assert -6.001<=lo[2]<=hi[2]<=6.001,o['name']
    if o['role'] not in ['surface','wall','ceiling']:
        assert not (lo[0]<9.5 and hi[0]>8.7 and lo[2]<1.3 and hi[2]>-1.3),o['name']
for group in g['groups']:
    mesh=HERE/'generated/meshes'/Path(group['mesh']).name
    assert mesh.is_file()
    verts=[];normals=[];uv=[];faces=[]
    for line in mesh.read_text().splitlines():
        s=line.split()
        if not s:continue
        if s[0]=='v':verts.append(tuple(map(float,s[1:])))
        if s[0]=='vn':normals.append(tuple(map(float,s[1:])))
        if s[0]=='vt':uv.append(tuple(map(float,s[1:])))
        if s[0]=='f':faces.append([int(q.split('/')[0])-1 for q in s[1:]])
    assert len(faces)==group['triangles'] and len(verts)==len(normals)==len(uv)==3*len(faces)
    for i,(a,b,c) in enumerate(faces):
        p,q,r=[verts[j] for j in [a,b,c]]
        x=[q[k]-p[k] for k in range(3)];y=[r[k]-p[k] for k in range(3)]
        n=(x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0])
        assert sum(v*v for v in n)>1e-12,(mesh.name,i)
        assert sum(n[k]*normals[a][k] for k in range(3))>0,(mesh.name,i)
        assert abs(math.sqrt(sum(v*v for v in normals[a]))-1)<1e-5
        assert all(math.isfinite(v) for v in (*uv[a],*p))
host=(ROOT/'scripts/campus/facilities/facility_host.gd').read_text()
assert all(x in host for x in ['seats.has(station)','seats.erase(a.station)','multiplayer'] if x!='multiplayer')
assert 'host.clear_activity(peer)' in (ROOT/'scripts/campus/facilities/facility_controller.gd').read_text()
print('M105 source contract PASS:',len(g['objects']),'authored objects,',g['triangles'],'triangles,',len(g['groups']),'material batches')
