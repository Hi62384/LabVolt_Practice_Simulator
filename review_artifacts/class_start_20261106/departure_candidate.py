from pathlib import Path
import difflib,hashlib
root=Path(__file__).resolve().parents[2]
out=Path(__file__).resolve().parent
def build(name,edits):
 p=root/name;old=p.read_text(encoding='utf-8-sig');new=old
 for a,b in edits:
  if new.count(a)!=1:raise RuntimeError(name+': anchor count '+str(new.count(a))+' '+a[:60])
  new=new.replace(a,b,1)
 (out/(name.replace('/','__')+'.departure.patch')).write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),'a/'+name,'b/'+name)),encoding='utf-8')
 (out/(name.replace('/','__')+'.departure.sha256')).write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'\n',encoding='utf-8')

school=[]
school.append(('''\t\t\tfor id in papers.keys():
\t\t\t\tif papers[id].owner==peer:
\t\t\t\t\tif papers[id].class_round==round_id and class_students.has(token):
\t\t\t\t\t\tclass_students[token].saved=papers[id].duplicate(true)
\t\t\t\t\tpapers.erase(id)''','''\t\t\t_fail_departing(token,peer)
\t\t\tfor id in papers.keys():
\t\t\t\tif papers[id].owner==peer:papers.erase(id)'''))
start=old=None
text=(root/'scripts/school_session.gd').read_text(encoding='utf-8-sig')
a=text[text.index('\tif mode=="Class":',text.index('func _identify(')):text.index('\tbroadcast()',text.index('func _identify('))]
b='''\tif mode=="Class":
\t\tif class_students.has(token):
\t\t\tif phase in ["travel","lesson"]:class_start.arrive(token,Time.get_ticks_usec())
\t\t\tif phase=="lesson":_record_attendance(peer)
\t\t\tif bool(class_students[token].get("done",false)):
\t\t\t\t_notice(peer,"Your previous class assignment is closed.")
\t\t\telif phase=="assignment":
\t\t\t\t# Rejoining a departed class never restores or reissues its assessment.
\t\t\t\t_fail_departing(token,peer)
\t\telif phase in ["travel","lesson"]:
\t\t\tclass_students[token]={"done":false}
\t\t\tclass_start.arrive(token,Time.get_ticks_usec())
\t\t\tif phase=="lesson":_record_attendance(peer)
\t\t\t_individual_project(token)
\t\t\tif activity.get("kind","")=="lab" and not allocation.has(token):
\t\t\t\tvar counts := [0,0,0]
\t\t\t\tfor slot in allocation.values():counts[int(slot.bench)]+=1
\t\t\t\tvar bench: int=counts.find(counts.min())
\t\t\t\tallocation[token]={"bench":bench,"group":bench,"individual":true}
\t\t\tif not activity.is_empty():_give_slip(peer)
\t\telif phase=="assignment":
\t\t\t_give(peer,project,false,false)
\t\t\t_notice(peer,"You joined during the lab. This copy is ungraded practice; your first graded round starts after the break.")
'''
school.append((a,b))
school.append(('''func checkpoint() -> void:
\tif not multiplayer.is_server() or activity.is_empty() or mode!="Class":return''','''func checkpoint() -> void:
\t# Class sessions are not resumable. Official marks are stored separately.
\treturn
\tif not multiplayer.is_server() or activity.is_empty() or mode!="Class":return'''))
school.append(('''func recover_activity() -> Dictionary:
\tif not multiplayer.is_server() or formal_active():return {"ok":false,"error":"Recovery requires an idle trusted host."}''','''func recover_activity() -> Dictionary:
\treturn {"ok":false,"error":"Saved class sessions cannot be resumed."}
\tif not multiplayer.is_server() or formal_active():return {"ok":false,"error":"Recovery requires an idle trusted host."}'''))
school.append(('''func prepare_host_exit(intentional: bool) -> void:
\tif multiplayer.is_server():
\t\tif intentional:abandon(1)
\t\tcheckpoint()
\telse:suspend_for_host_loss()''','''func prepare_host_exit(intentional: bool) -> void:
\tif multiplayer.is_server():
\t\tif intentional:_fail_departing(str(identities.get(1,local_identity)),1)
\telse:suspend_for_host_loss()'''))
school.append(('''func _session_leaving() -> void:
\tif not game.front.in_game:return
\tif game.session.get_meta("lost_authority",false):suspend_for_host_loss()
\telse:prepare_host_exit(multiplayer.is_server())''','''func _session_leaving() -> void:
\tif not game.front.in_game:return
\tif game.session.get_meta("lost_authority",false):suspend_for_host_loss()
\telse:prepare_host_exit(multiplayer.is_server())''')) if False else None
school.append(('''func checkpoint() -> void:''','''func _fail_departing(token: String, peer: int) -> void:
\tif not multiplayer.is_server() or mode!="Class" or phase not in ["travel","lesson","assignment"]:return
\tif token.is_empty() or not class_students.has(token) or bool(class_students[token].get("done",false)):return
\tvar id := GradePolicy.attempt_id(assessment_id,token)
\tif archive.get(token,{}).has(id):
\t\tclass_students[token].done=true
\t\treturn
\tvar assigned: Dictionary=_individual_project(token)
\tif assigned.is_empty():assigned=project
\tif assigned.is_empty():return
\tvar record := {"id":id,"profile":token,"title":str(assigned.get("title","Class assignment")),"score":0.0,"difficulty":assigned.get("difficulty",difficulty),"lesson":false,"course_id":assigned.get("course_id",activity.get("course_id","ELM253")),"kind":assigned.get("kind",activity.get("kind","lecture")),"week":assigned.get("week",activity.get("week",1)),"assessment_id":assessment_id,"time":Time.get_datetime_string_from_system(),"reason":"Left class before completing the assigned assessment."}
\trecord.merge(CourseProgression.record_fields(assigned),true)
\tif not archive.has(token):archive[token]={}
\tarchive[token][id]=record
\t_save("user://teacher_records.json",archive)
\tclass_students[token].done=true
\tclass_students[token].erase("saved")
\tif peer==1:_receive_grade(record)
\telif game.session.online and game.session.roster.has(peer):_receive_grade.rpc_id(peer,record)

func checkpoint() -> void:'''))
school=[x for x in school if not x[0].startswith('func checkpoint() -> void:\n') and not x[0].startswith('func recover_activity() -> Dictionary:')]
source=(root/'scripts/school_session.gd').read_text(encoding='utf-8-sig')
school.append((source[source.index('func checkpoint() -> void:'):source.index('func suspend_for_host_loss() -> void:')],'''func checkpoint() -> void:
\t# Class sessions are not resumable. Official marks are stored separately.
\treturn

func recover_activity() -> Dictionary:
\treturn {"ok":false,"error":"Saved class sessions cannot be resumed."}

'''))
school.append(('const GradePolicy = preload("res://scripts/campus/academics/grade_policy.gd")','const GradePolicy = preload("res://scripts/campus/academics/grade_policy.gd")\nconst PendingAssessment = preload("res://review_artifacts/class_start_20261106/pending_assessment_candidate.gd")'))
school.append(('\tif archive.get(token,{}).has(grade_id):','\tif archive.get(token,{}).has(grade_id) and not archive[token][grade_id].has("pending_assessment_version"):'))
school.append(('\tarchive[token][grade_id]=record\n\t_save("user://teacher_records.json",archive)','\tif PendingAssessment.settle(archive,record,_persist_archive)!=OK:\n\t\tpaper.mark={}\n\t\treturn'))
school.append(('\tif archive.get(token,{}).has(id):','\tif archive.get(token,{}).has(id) and not archive[token][id].has("pending_assessment_version"):'))
school.append(('\tarchive[token][id]=record\n\t_save("user://teacher_records.json",archive)','\tif PendingAssessment.settle(archive,record,_persist_archive)!=OK:return'))
school.append(('\tfor id in records:_receive_grade(records[id])','\tfor id in records:\n\t\tif not records[id].has("pending_assessment_version"):_receive_grade(records[id])'))
school.append(('\tvar count := 0\n\tfor paper in papers.values():','\tif class_copy:\n\t\tvar token := str(identities.get(peer,""))\n\t\tvar obligation := {"id":GradePolicy.attempt_id(assessment_id,token),"assessment_id":assessment_id,"profile":token,"title":str(assignment.get("title","Class assignment")),"course_id":assignment.get("course_id","ELM253"),"kind":assignment.get("kind","lecture"),"week":assignment.get("week",1),"difficulty":difficulty,"lesson":false,"time":Time.get_datetime_string_from_system()}\n\t\tobligation.merge(CourseProgression.record_fields(assignment),true)\n\t\tif PendingAssessment.prepare(archive,obligation,_persist_archive)!=OK:return 0\n\tvar count := 0\n\tfor paper in papers.values():'))
school.append(('func _notice(peer: int,message: String) -> void:','func _persist_archive(value: Dictionary) -> Error:\n\tvar path := "user://teacher_records.json"\n\tvar file := FileAccess.open(path+".tmp",FileAccess.WRITE)\n\tif file==null:return FileAccess.get_open_error()\n\tfile.store_string(JSON.stringify(value))\n\tfile.flush()\n\tvar error := file.get_error()\n\tfile.close()\n\tif error!=OK:return error\n\treturn DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))\n\nfunc _notice(peer: int,message: String) -> void:'))
school.append(('\t_identity_changed()\nfunc _reset_session()','\t_identity_changed()\n\tfor result in PendingAssessment.abandoned(archive,local_identity):\n\t\tif PendingAssessment.settle(archive,result,_persist_archive)==OK:_receive_grade(result)\nfunc _reset_session()'))
school.append(('\t_clear_earthing_demo()\n\tclass_start.cancel()','''\tvar next_assessment_id := Crypto.new().generate_random_bytes(16).hex_encode()
\tif selected=="Course":
\t\tvar enrollment: Array[Dictionary]=[]
\t\tvar profiles: Array=identities.values().duplicate()
\t\tif local_identity not in profiles:profiles.append(local_identity)
\t\tfor profile in profiles:
\t\t\tif str(profile).is_empty():return {"ok":false,"error":"A validated student identity is required."}
\t\t\tenrollment.append(_enrollment_record(str(profile),next_assessment_id,assignment))
\t\tif PendingAssessment.enroll(archive,enrollment,_persist_archive)!=OK:return {"ok":false,"error":"Class enrollment could not be saved. Class has not started."}
\t_clear_earthing_demo()
\tclass_start.cancel()'''))
school.append(('\tround_id+=1\n\tassessment_id=Crypto.new().generate_random_bytes(16).hex_encode()\n\tassessment_deadline=0','\tround_id+=1\n\tassessment_id=next_assessment_id\n\tassessment_deadline=0'))
school.append(('\tidentities[peer]=token\n\tif peer==1:', '''\tif mode=="Class" and phase in ["travel","lesson"] and not class_students.has(token):
\t\tvar enrollment: Array[Dictionary]=[_enrollment_record(token,assessment_id,project)]
\t\tif PendingAssessment.enroll(archive,enrollment,_persist_archive)!=OK:
\t\t\t_notice(peer,"Class enrollment could not be saved. Ask the host to retry admission.")
\t\t\treturn
\tidentities[peer]=token
\tif peer==1:'''))
school.append(('func _persist_archive(value: Dictionary) -> Error:', '''func _enrollment_record(token: String, session_id: String, assignment: Dictionary) -> Dictionary:
\tvar record := {"id":GradePolicy.attempt_id(session_id,token),"assessment_id":session_id,"profile":token,"title":str(assignment.get("title","Class assignment")),"course_id":assignment.get("course_id","ELM253"),"kind":assignment.get("kind","lecture"),"week":assignment.get("week",1),"difficulty":assignment.get("difficulty",difficulty),"lesson":false,"time":Time.get_datetime_string_from_system()}
\trecord.merge(CourseProgression.record_fields(assignment),true)
\treturn record

func _persist_archive(value: Dictionary) -> Error:'''))
school.append(('var suspended := false','var suspended := false\nvar host_departure_in_progress := false'))
school.append(('func _reset_session() -> void:\n\tclass_start.cancel()','func _reset_session() -> void:\n\thost_departure_in_progress=false\n\tclass_start.cancel()'))
school[0]=(school[0][0],school[0][1].replace('\t\t\t_fail_departing(token,peer)','\t\t\tif not host_departure_in_progress:_fail_departing(token,peer)'))
school=[(a,b.replace('if intentional:_fail_departing(str(identities.get(1,local_identity)),1)','if intentional:\n\t\t\thost_departure_in_progress=true\n\t\t\t_fail_departing(str(identities.get(1,local_identity)),1)')) if a.startswith('func prepare_host_exit(') else (a,b) for a,b in school]
build('scripts/school_session.gd',school)
front=[]
start=text=None
text=(root/'scripts/front_menu.gd').read_text(encoding='utf-8-sig')
a=text[text.index('func resume_class_page() -> void:'):text.index('func network_page(',text.index('func resume_class_page() -> void:'))]
front.append((a,''))
build('scripts/front_menu.gd',front)
