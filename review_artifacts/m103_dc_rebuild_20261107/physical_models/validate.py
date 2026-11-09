"""Offline geometry/port/contract checks. No engine or live scene use."""
from pathlib import Path
import json, math, re

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
data=json.loads((HERE/'ports.json').read_text(encoding='utf-8'))
devices=data['devices']; ports=data['ports']
station=(ROOT/'scripts/dc_station.gd').read_text(encoding='utf-8-sig')
source_ports=set(re.findall(r'"([^"\n]+)"',station.split('const PORTS = ',1)[1].split('\n',1)[0]))
fixed={p for p in source_ports if not p.startswith('X')}
actual={p['id'] for p in ports}
assert actual==fixed,(sorted(fixed-actual),sorted(actual-fixed))
assert len(actual)==len(ports)==34
assert set(devices)=={'psu','meter','generator','scope','deck'}
assert devices['psu']['origin'][0]<devices['meter']['origin'][0]<devices['scope']['origin'][0]

for name,spec in devices.items():
    x,y,z=spec['origin'];w,h,d=spec['size']
    assert x-w/2>=-2.4 and x+w/2<=2.4
    assert abs(y-h/2-.028-.88)<.002 if name!='generator' else abs(y-h/2-.028-(devices['meter']['origin'][1]+devices['meter']['size'][1]/2))<.002
    assert -.8<=z-d and z<=.8
for i,a in enumerate(ports):
    dev=devices[a['device']];w,h,d=dev['size'];px,py,pz=a['xyz']
    assert pz==dev['front_z']==a['face_z'] and a['normal']==[0,0,1]
    assert -w/2+.035<=px<=w/2-.035 and -h/2+.035<=py<=h/2-.035
    assert a['color'] in {'red','black','yellow','cyan'}
    for b in ports[i+1:]:
        if b['device']==a['device']:
            assert math.dist(a['xyz'],b['xyz'])>=.075,(a['id'],b['id'])

mesh_data=json.loads((HERE/'meshes/mesh_manifest.json').read_text(encoding='utf-8'))['meshes']
for name,meta in mesh_data.items():
    path=HERE/'meshes'/f'{name}.obj'
    assert path.exists() and meta['triangles']<=1500 and meta['surfaces']<=8
    rows=path.read_text(encoding='utf-8').splitlines()
    vertices=[tuple(map(float,row.split()[1:])) for row in rows if row.startswith('v ')]
    normals=[tuple(map(float,row.split()[1:])) for row in rows if row.startswith('vn ')]
    faces=[row.split()[1:] for row in rows if row.startswith('f ')]
    assert len(vertices)==len(normals)==meta['vertices'] and len(faces)==meta['triangles']
    for face in faces:
        a,b,c=[vertices[int(x.split('/')[0])-1] for x in face]
        u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
        cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        normal=normals[int(face[0].split('/')[2])-1]
        assert sum(cross[j]*normal[j] for j in range(3))>0
assert sum(v['triangles'] for v in mesh_data.values())<7500
assert 'port_positions()' in (HERE/'fixture.gd').read_text(encoding='utf-8')
print('M103 physical contract passed: %d fixed ports, %d reusable triangles.'%(len(ports),sum(v['triangles'] for v in mesh_data.values())))
