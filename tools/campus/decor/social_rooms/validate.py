"""Full XZ footprint and source resource admission; no engine or game access."""
import json, math, pathlib
root=pathlib.Path(__file__).resolve().parents[4]
data=json.loads((root/'assets/campus/decor/social_rooms/profiles.json').read_text())
rooms={r['id']:r for r in json.loads((root/'assets/campus/world/room_registry.json').read_text())['rooms']}
errors=[];stats={}
def overlap(a,b):return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]
for rid,p in data['rooms'].items():
 room=rooms[rid];center=p['center'];lo,hi=room['bounds_min'],room['bounds_max'];door=room['door'];count=0;tris=0
 doorlane=(door[0]-(2.4 if rid in ('cafeteria','tim_hortons','subway','library') else .2)-center[0],-1.25,door[0]+.2-center[0] if rid!='study' else 2.4,1.25)
 # Local west/east entry threshold and 2.4 m longitudinal door opening.
 lane=(-10,-1.2,-7.8,1.2) if rid!='study' else (7.8,-1.2,10,1.2)
 # Restaurant service aisle spans door to functional ordering anchor.
 queue=(-8,-.45,-2.9,.45)
 for g in p['groups']:
  meta=data['meshes'][g['mesh']];path=root/'assets/campus/decor/social_rooms/meshes'/f"{g['mesh']}.obj"
  if not path.exists():errors.append(f'{rid}: absent {g["mesh"]}')
  for t in g['items']:
   count+=1;tris+=meta['triangles'];x,y,z,angle,sx,sy,sz=t;a=math.radians(angle)
   corners=[(x+u*sx*math.cos(a)+w*sz*math.sin(a),y+v*sy,z-u*sx*math.sin(a)+w*sz*math.cos(a)) for u in (meta['bounds_min'][0],meta['bounds_max'][0]) for v in (meta['bounds_min'][1],meta['bounds_max'][1]) for w in (meta['bounds_min'][2],meta['bounds_max'][2])]
   if any(not all(lo[i]-.001<=q[i]+center[i]<=hi[i]+.001 for i in range(3)) for q in corners):errors.append(f'{rid}: shell {g["mesh"]} {t}')
   box=(min(q[0] for q in corners),min(q[2] for q in corners),max(q[0] for q in corners),max(q[2] for q in corners))
   low=min(q[1] for q in corners);high=max(q[1] for q in corners)
   if low<2.1 and high>.2 and overlap(box,lane):errors.append(f'{rid}: door {g["mesh"]} {t}')
   if rid in ('tim_hortons','subway') and low<2.1 and high>.2 and overlap(box,queue) and not g['mesh'].startswith('counter'):
    errors.append(f'{rid}: ordering aisle {g["mesh"]} {t}')
 stats[rid]={'instances':count,'batches':len(p['groups']),'expanded_triangles':tris}
print(json.dumps({'errors':errors,'rooms':stats},indent=2))
raise SystemExit(bool(errors))
