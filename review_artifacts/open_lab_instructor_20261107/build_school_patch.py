from pathlib import Path
import difflib,hashlib
root=Path(__file__).resolve().parents[2]
source=root/'scripts/school_session.gd'
old=source.read_text(encoding='utf-8-sig');new=old
def edit(a,b):
 global new
 if new.count(a)!=1:raise RuntimeError('school anchor '+str(new.count(a))+': '+a[:55])
 new=new.replace(a,b,1)
edit('''\telif op=="guide":
\t\tif not _near(peer,teacher_position):return''','''\telif op=="guide":
\t\tif not preload("res://review_artifacts/open_lab_instructor_20261107/tutorials/formal_guide_policy.gd").allowed(mode,activity):return
\t\tif not _near(peer,teacher_position):return''')
edit('''\telif op=="new":
\t\tif mode=="Class":return''','''\telif op=="practice_lesson":
\t\tif mode not in ["Open Lab","Freeplay","Creative Freeplay"]:return
\t\tif not game.session.roster.has(peer) or str(identities.get(peer,""))=="":return
\t\tvar pose: Variant=game.session.poses.get(peer,{}).get("position")
\t\tif not pose is Vector3 or not _near(peer,teacher_position):return
\t\tif room_bridge.registry==null:return
\t\tvar room_id := str(room_bridge.registry.call("locate",pose))
\t\tif not room_bridge.contains(room_id,pose):return
\t\tvar service=preload("res://review_artifacts/open_lab_instructor_20261107/practice/practice_service.gd")
\t\tvar course := service.course_for_room(room_id)
\t\tif course.is_empty():return
\t\tif mode=="Open Lab" and (activity.is_empty() or str(activity.get("course_id",""))!=course or str(activity.get("room",{}).get("id",""))!=room_id):return
\t\tvar practice: Dictionary=service.issue_for_room(room_id,course_bridge,random.randi())
\t\tif practice.has("error"):_notice(peer,str(practice.error));return
\t\t_give(peer,practice,true,false)
\telif op=="new":
\t\tif mode=="Class":return''')
edit('''func _give(peer: int,assignment: Dictionary,lesson: bool,class_copy: bool) -> int:
''','''func _give(peer: int,assignment: Dictionary,lesson: bool,class_copy: bool) -> int:
\tif str(assignment.get("practice_scope",""))=="ungraded" and (class_copy or not lesson):return 0
''')
edit('''func _lesson_reward(paper: Dictionary) -> void:
\tif mode=="Creative Freeplay":return''','''func _lesson_reward(paper: Dictionary) -> void:
\tif str(paper.get("project",{}).get("practice_scope",""))=="ungraded":return
\tif mode=="Creative Freeplay":return''')
edit('''\treturn not bool(paper.get("lesson",true)) and int(paper.get("class_round",0))!=0''','''\treturn not bool(paper.get("lesson",true)) and int(paper.get("class_round",0))!=0 and str(paper.get("project",{}).get("practice_scope",""))!="ungraded"''')
target=Path(__file__).resolve().parent
(target/'school_session.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),'a/scripts/school_session.gd','b/scripts/school_session.gd')),encoding='utf-8')
(target/'school_session.sha256').write_text(hashlib.sha256(source.read_bytes()).hexdigest()+'\n',encoding='utf-8')
