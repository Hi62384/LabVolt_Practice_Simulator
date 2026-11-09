"""Produce exact-preimage M105 shared patches. No production file is edited."""
from pathlib import Path
import hashlib,difflib,json
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
changes={}
def patch(path,edits):
    src=(ROOT/path).read_text(encoding='utf8')
    dst=src
    for old,new in edits:
        if dst.count(old)!=1:raise ValueError(f'{path}: expected one match, got {dst.count(old)} for {old[:65]!r}')
        dst=dst.replace(old,new,1)
    diff=''.join(difflib.unified_diff(src.splitlines(True),dst.splitlines(True),fromfile='a/'+path,tofile='b/'+path))
    (HERE/(Path(path).name+'.patch')).write_text(diff,encoding='utf8')
    changes[path]={'preimage_sha256':hashlib.sha256(src.encode()).hexdigest(),'patch':Path(path).name+'.patch'}

patch('scripts/campus/facilities/facility_host.gd',[
('const EMOTES :=', 'const WEIGHTS := {"pushup":[0],"pullup":[0],"benchpress":[10,20,40],"squat":[10,20,40],"curl":[5,10,20]}\nconst EMOTES :='),
('if not EXERCISES.has(exercise) or seats.has(station):return fail("Equipment occupied")', 'if not EXERCISES.has(exercise) or seats.has(station):return fail("Equipment occupied")\n\t\tvar weight: Variant=request.get("weight",WEIGHTS[exercise][0])\n\t\tif not weight is int or not weight in WEIGHTS[exercise]:return fail("Unsupported exercise weight")'),
('"phase":0,"reps":0}', '"phase":0,"reps":0,"weight":weight}'),
('"phase":0,"reps":0,"station":station}', '"phase":0,"reps":0,"weight":weight,"station":station}'),
('"phase":next_active.phase,"reps":next_active.reps,"station":current.station}', '"phase":next_active.phase,"reps":next_active.reps,"weight":current.weight,"station":current.station}'),
('next.xp=mini(1000000000,int(p.xp)+reps*5)', 'next.xp=mini(1000000000,int(p.xp)+reps*(5+int(current.get("weight",0))/20))'),
])
patch('scripts/campus/facilities/facility_panel.gd',[
('status.text+="\\n%s • %d reps\\nFollow a steady rhythm; press each half repetition."%[str(a.exercise).capitalize(),a.reps]', 'status.text+="\\n%s • %d kg • %d reps • 1 set\\nFollow a steady rhythm."%[str(a.exercise).capitalize(),int(a.get("weight",0)),a.reps]'),
('elif station_kind in ["pushup","pullup","benchpress","squat","curl"]:button("Start "+station_kind.capitalize(),{"op":"start","station":station_id})', 'elif station_kind in ["pushup","pullup","benchpress","squat","curl"]:\n\t\tvar choices: Array=preload("res://scripts/campus/facilities/facility_host.gd").WEIGHTS[station_kind]\n\t\tfor kg in choices:button("Start %s • %d kg"%[station_kind.capitalize(),kg],{"op":"start","station":station_id,"weight":kg})'),
])
patch('scripts/campus/facilities/facility_room.gd',[
('if kind=="squat":box(at+Vector3(0,1.35,0.2),Vector3(2.5,0.12,0.12),metal,false)', 'if kind=="squat":pass # M105 motion adapter owns the moving bar and plates.'),
('box(at+Vector3(0,1.25,-0.8),Vector3(2.5,0.12,0.12),metal,false)', '# M105 motion adapter owns the moving bar and plates.'),
('for x in [-0.7,0,0.7]:\n\t\t\t\tbox(at+Vector3(x,0.82,-0.5),Vector3(0.5,0.15,0.12),metal,false)', '# M105 motion adapter owns the moving dumbbell.'),
('label(at+Vector3(0,2.9,0),kind.capitalize(),0.004)', '# Compact HUD presents station context; no floating station labels.'),
('label(Vector3(0,3.6,-3.7),"GYM • Rhythm training\\nAlternate Lower / Raise • Finish set to save XP",0.006)', '# Wall sign is provided by the numbered campus signage; no floating directions.'),
])
patch('scripts/campus_integration.gd',[
('var social: Node', 'var gym_motion: Node3D\nvar social: Node'),
('for id in ["gym","tim_hortons","subway"]:facilities.mount_room(id,game.campus)', 'for id in ["gym","tim_hortons","subway"]:facilities.mount_room(id,game.campus)\n\tgym_motion=preload("res://scripts/campus/presentation/decor/m105/gym_equipment_motion.gd").new()\n\tgym_motion.name="GymEquipmentMotion";game.campus.add_child(gym_motion)\n\tfacilities.controller.room_event.connect(gym_motion.on_room_event)\n\tvar gym_decor=preload("res://scripts/campus/presentation/decor/m105/m105_decor.gd").new()\n\tgame.campus.add_child(gym_decor)\n\tgym_decor.mount(game.campus)'),
])
(HERE/'patch_manifest.json').write_text(json.dumps(changes,indent=2)+'\n')
print('Staged',len(changes),'patches')
if __name__=='__main__':pass
