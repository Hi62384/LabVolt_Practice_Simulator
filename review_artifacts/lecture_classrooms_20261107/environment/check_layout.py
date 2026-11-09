"""Offline seat/desk and floor-clearance admission for M201/M202."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[3]
registry=json.loads((root/'assets/campus/world/room_registry.json').read_text(encoding='utf8'))
rooms={r['id']:r for r in registry['rooms']}
assert registry['course_rooms']['ELM253']['lecture']=='elm253_lecture'
assert registry['course_rooms']['ETY155']['lecture']=='ety155_lecture'
assert registry['course_rooms']['MTH147']['lecture']=='elm253_lecture'
assert registry['course_rooms']['MTH255']['lecture']=='elm253_lecture'
for id in ['elm253_lecture','ety155_lecture']:
    r=rooms[id];cx,cy,cz=r['center'];xmin,ymin,zmin=r['bounds_min'];xmax,ymax,zmax=r['bounds_max']
    for z in [-2.,2.]:
        for x in [-6.,-2.,2.,6.]:
            px,pz=cx+x,cz+z
            assert xmin+.2<px-.85 and px+.85<xmax-.2
            assert zmin+.2<pz-.4 and pz+1<zmax-.2
            assert abs(px-r['door'][0])>2.5
    print(id,r['number'],'8 desks/8 seats; shell',r['size'],'door',r['door'])
# Old leg extends below floor; new skin rests 0.010 m above and keeps worksheet top.
old_bottom=.8-.035-.41-.8/2
new_bottom=.8-.035-.385-.74/2
assert old_bottom<0 and new_bottom>=0
assert abs((.8-.035)+.07/2-.8)<1e-9
source=(root/'scripts/school_world.gd').read_text(encoding='utf8')
assert 'shape.size=Vector3(1.7,.07,.8)' in source
print('old leg bottom',old_bottom,'new leg bottom',new_bottom,'worksheet top 0.8')
print('school_world preimage',hashlib.sha256((root/'scripts/school_world.gd').read_bytes()).hexdigest())
for id in ['elm253_lecture','ety155_lecture']:
    r=rooms[id];cx,cy,cz=r['center'];xmin,_,zmin=r['bounds_min'];xmax,_,zmax=r['bounds_max']
    lectern=(cx+3.65,cz-4.4)
    cabinet=(cx-8.6 if cx<13 else cx+8.6,cz+4.8)
    assert xmin<lectern[0]-.625 and lectern[0]+.625<xmax
    assert zmin<lectern[1]-.325 and lectern[1]+.325<cz-2 # front desk row
    assert abs(lectern[0]-cx)>2.85+.625 # board half-width + lectern
    assert xmin<cabinet[0]-.425 and cabinet[0]+.425<xmax
    assert zmin<cabinet[1]-.28 and cabinet[1]+.28<zmax
    assert abs(cabinet[0]-r['door'][0])>1
print('instructor lectern clears live board and desk rows; rear cabinets remain within shells')
