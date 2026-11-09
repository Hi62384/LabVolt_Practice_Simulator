from pathlib import Path
import difflib, hashlib

root=Path(__file__).resolve().parents[2]
out=Path(__file__).resolve().parent
def make(name, edits):
    path=root/name
    before=path.read_text(encoding='utf-8-sig')
    after=before
    for old,new in edits:
        count=after.count(old)
        if count!=1: raise RuntimeError(f'{name}: expected one anchor, found {count}: {old[:65]!r}')
        after=after.replace(old,new,1)
    diff=''.join(difflib.unified_diff(before.splitlines(keepends=True),after.splitlines(keepends=True),fromfile='a/'+name,tofile='b/'+name, n=3))
    (out/(name.replace('/','__')+'.patch')).write_text(diff,encoding='utf-8')
    (out/(name.replace('/','__')+'.preimage.sha256')).write_text(hashlib.sha256(path.read_bytes()).hexdigest()+'\n',encoding='utf-8')
    return len(edits),len(diff)

school=[]
def s(a,b):school.append((a,b))
s('const Attendance = preload("res://scripts/campus/academics/attendance_ledger.gd")','const Attendance = preload("res://scripts/campus/academics/attendance_ledger.gd")\nconst ClassStartClock = preload("res://scripts/campus/academics/class_start/class_start_clock.gd")\nvar class_start = ClassStartClock.new()')
s('func _reset_session() -> void:\n\tsent_identity=false','func _reset_session() -> void:\n\tclass_start.cancel()\n\tsent_identity=false')
s('\tactivity={}\n\tpresentation={}\n\tallocation={}\n\tmode=new_mode','\tclass_start.cancel()\n\tactivity={}\n\tpresentation={}\n\tallocation={}\n\tmode=new_mode')
s('\tif mode=="Class":\n\t\tif class_students.has(token):','\tif mode=="Class":\n\t\tif class_students.has(token):\n\t\t\tif phase in ["travel","lesson"]:class_start.arrive(token,Time.get_ticks_usec())')
s('\t\telif phase in ["travel","lesson"]:\n\t\t\tclass_students[token]={"done":false}','\t\telif phase in ["travel","lesson"]:\n\t\t\tclass_students[token]={"done":false}\n\t\t\tclass_start.arrive(token,Time.get_ticks_usec())')
s('\tif op=="activity":\n\t\tif peer==1:','\tif op=="activity":\n\t\tif peer==1 and can_choose_next_activity():')
s('\tif op=="begin_lesson":\n\t\tif peer==1:begin_lesson()\n\t\treturn','\tif op=="begin_lesson":return')
s('\telif op=="new":\n\t\tif not _near(peer,teacher_position):return','\telif op=="new":\n\t\tif mode=="Class":return\n\t\tif not _near(peer,teacher_position):return')
s('func _record_attendance(peer: int) -> void:','func _record_attendance(peer: int) -> void:') if False else None
s('\tremaining=maxf(0,remaining-maxf(0,delta))\n\tif phase=="assignment":','\tremaining=maxf(0,remaining-maxf(0,delta))\n\tif phase=="assignment":') if False else None
s('\tif game==null or not multiplayer.is_server() or not game.front.in_game:return\n\tadvance(delta)','\tif game==null or not multiplayer.is_server():return\n\tif phase=="travel" and not suspended:\n\t\tvar now_usec := Time.get_ticks_usec()\n\t\tremaining=class_start.remaining(now_usec)\n\t\tif class_start.begin_if_due(now_usec):\n\t\t\tphase="lesson"\n\t\t\tremaining=teaching_seconds\n\t\t\tfor peer in identities:_record_attendance(int(peer))\n\t\t\tbroadcast()\n\t\t\tcheckpoint()\n\tif not game.front.in_game:return\n\tadvance(delta)')
s('func formal_active() -> bool:\n\treturn mode=="Class" and phase in ["travel","lesson","assignment"] and not class_students.is_empty()','func formal_active() -> bool:\n\treturn mode=="Class" and phase in ["travel","lesson","assignment"]\n\nfunc can_choose_next_activity() -> bool:\n\treturn multiplayer.is_server() and ((mode in ["Freeplay","Creative Freeplay"] and phase=="freeplay") or (mode=="Class" and phase=="complete"))')
s('\tif formal_active():return {"ok":false,"error":"Finish the current class before switching activities."}\n\tvar selected :=','\tif game.front.in_game and not can_choose_next_activity():return {"ok":false,"error":"The next activity is available to the host in Freeplay or after class ends."}\n\tvar selected :=')
s('\t_clear_earthing_demo()\n\tpapers.clear()\n\tclass_students.clear()\n\tround_id+=1','\t_clear_earthing_demo()\n\tclass_start.cancel()\n\tpapers.clear()\n\tclass_students.clear()\n\tround_id+=1')
s('\tallocation=Benches.allocate(class_students.keys()) if kind=="lab" else {}\n\tfor peer in identities:_give_slip(int(peer))','\tallocation=Benches.allocate(class_students.keys()) if kind=="lab" else {}\n\tif selected=="Course":\n\t\tclass_start.arm(assessment_id,Time.get_ticks_usec())\n\t\tfor token in class_students:class_start.arrive(str(token),Time.get_ticks_usec())\n\t\tremaining=class_start.remaining(Time.get_ticks_usec())\n\tfor peer in identities:_give_slip(int(peer))')
s('The host begins teaching once students are ready.','Teaching begins automatically two minutes after Class starts.')
s('func begin_lesson() -> bool:\n\tif not multiplayer.is_server() or phase!="travel":return false','func begin_lesson() -> bool:\n\t# Legacy instructor requests cannot start scheduled teaching early.\n\treturn false\n\tif not multiplayer.is_server() or phase!="travel":return false')
s('"deadline":assessment_deadline,"saved_at":_academic_now()}','"deadline":assessment_deadline,"saved_at":_academic_now(),"class_start_remaining":class_start.remaining(Time.get_ticks_usec()) if phase=="travel" else 0.0,"class_start_wall_cap":_academic_now()+class_start.remaining(Time.get_ticks_usec()) if phase=="travel" else 0.0,"class_start_arrivals":class_start.arrivals.duplicate(true)}')
s('\tremaining=maxf(0,float(data.remaining))\n\t# Neither clock rollback','\tremaining=maxf(0,float(data.remaining))\n\tclass_start.cancel()\n\tif phase=="travel":\n\t\tvar saved_wait := float(data.get("class_start_remaining",0.0))\n\t\tvar wall_cap := float(data.get("class_start_wall_cap",0.0))\n\t\tremaining=minf(saved_wait,maxf(0.0,wall_cap-_academic_now()))\n\t\tclass_start.restore(assessment_id,remaining,Time.get_ticks_usec(),data.get("class_start_arrivals",{}))\n\t# Neither clock rollback')
# Refine the generated changes while retaining function-level preimage anchors.
school[5]=(school[5][0],school[5][1].replace('can_choose_next_activity():','can_choose_next_activity() and int(a.get("expected_round",-1))==round_id:'))
school[3]=(school[3][0],school[3][1]+'\n\t\t\tif phase=="lesson":_record_attendance(peer)')
school[4]=(school[4][0],school[4][1]+'\n\t\t\tif phase=="lesson":_record_attendance(peer)')
school.append(('\tif result.get("created",false):_save("user://teacher_attendance.json",attendance_archive)','\tif result.get("created",false):\n\t\tresult.event["late"]=bool(class_start.arrivals.get(token,false))\n\t\tattendance_archive[result.id]=result.event.duplicate(true)\n\t\t_save("user://teacher_attendance.json",attendance_archive)'))
school=[change for change in school if not change[0].startswith('func begin_lesson() -> bool:')]
source_school=(root/'scripts/school_session.gd').read_text(encoding='utf-8-sig')
old_begin=source_school[source_school.index('func begin_lesson() -> bool:'):source_school.index('func teaching_stage() -> Dictionary:')]
school.append((old_begin,'func begin_lesson() -> bool:\n\t# Legacy callers cannot start scheduled teaching early.\n\treturn false\n\n'))
school.append(('\t# Neither clock rollback nor restart may increase the saved time budget.','\tif phase=="lesson":\n\t\tclass_start.restore(assessment_id,0.0,Time.get_ticks_usec(),data.get("class_start_arrivals",{}))\n\t\tclass_start.begin_if_due(Time.get_ticks_usec())\n\t# Neither clock rollback nor restart may increase the saved time budget.'))
school.append(('var round_id := 0','var round_id := 0\nvar activity_epoch := 0'))
school.append(('\tclass_start.cancel()\n\tactivity={}\n\tpresentation={}\n\tallocation={}\n\tmode=new_mode','\tclass_start.cancel()\n\tactivity_epoch+=1\n\tactivity={}\n\tpresentation={}\n\tallocation={}\n\tmode=new_mode')) if False else None
# Append to the existing replacement so the same preimage anchor is consumed once.
school[2]=(school[2][0],school[2][1].replace('\tclass_start.cancel()\n\tactivity={}','\tclass_start.cancel()\n\tactivity_epoch+=1\n\tactivity={}'))
school[5]=(school[5][0],school[5][1].replace('int(a.get("expected_round",-1))==round_id','int(a.get("expected_epoch",-1))==activity_epoch'))
school.append(('\t_clear_earthing_demo()\n\tpapers.clear()\n\tclass_students.clear()\n\tround_id+=1','\t_clear_earthing_demo()\n\tactivity_epoch+=1\n\tpapers.clear()\n\tclass_students.clear()\n\tround_id+=1')) if False else None
school[11]=(school[11][0],school[11][1].replace('\tclass_start.cancel()\n\tpapers.clear()','\tclass_start.cancel()\n\tactivity_epoch+=1\n\tpapers.clear()'))
school.append(('"class_start_arrivals":class_start.arrivals.duplicate(true)}','"class_start_arrivals":class_start.arrivals.duplicate(true),"activity_epoch":activity_epoch}')) if False else None
school.append(('\tphase=str(data.phase);round_id=int(data.round_id);next_id=int(data.next_id);assessment_id=str(data.assessment_id);assessment_deadline=float(data.deadline)','\tphase=str(data.phase);round_id=int(data.round_id);next_id=int(data.next_id);assessment_id=str(data.assessment_id);assessment_deadline=float(data.deadline)\n\tactivity_epoch=maxi(activity_epoch+1,int(data.get("activity_epoch",0))+1)'))
make('scripts/school_session.gd',school)

paper=[]
def p(a,b):paper.append((a,b))
p('\t_label(column,"Practice assignments and lessons never change official course marks.")\n\tvar row :=','\tif school.mode=="Class":\n\t\t_label(column,"%s · Week %d · %s"%[str(school.activity.get("course_id","")),int(school.activity.get("week",0)),str(school.activity.get("kind","")).capitalize()])\n\t\t_label(column,"%s · %02d:%02d"%[school.phase.capitalize(),int(school.remaining)/60,int(school.remaining)%60])\n\t\tif school.phase=="travel":_label(column,"Find your assigned room. Teaching begins automatically when the countdown ends.")\n\t\telif school.phase=="lesson":_label(column,str(school.teaching_stage().get("title","Teaching in progress")))\n\t\telif school.phase=="assignment":_label(column,"Your assigned work is ready. Complete it before the deadline.")\n\t\tif school.phase=="assignment" and school.held(multiplayer.get_unique_id())==0:_button(column,"Replace missing Class sheet",func():school.request({"op":"replacement"});close())\n\telse:\n\t\t_label(column,"Practice assignments and lessons never change official course marks.")\n\tvar row :=')
# Keep legacy practice widgets in a dedicated branch by indenting the contiguous block.
start='\tvar row := HBoxContainer.new()\n'
end='\tif school.mode=="Class":\n\t\t_label(column,"CLASS • %s • %02d:%02d remaining"%[school.phase.capitalize(),int(school.remaining)/60,int(school.remaining)%60])'
source=(root/'scripts/paper_ui.gd').read_text(encoding='utf-8-sig')
block=source[source.index(start,source.index('func teacher()')):source.index(end,source.index('func teacher()'))]
p(block,'\n'.join('\t'+line for line in block.rstrip('\n').split('\n'))+'\n')
p('\tif school.mode=="Class":\n\t\t_label(column,"CLASS • %s • %02d:%02d remaining"%[school.phase.capitalize(),int(school.remaining)/60,int(school.remaining)%60])\n\t\t_label(column,"Join during the lesson to take part. Join during a lab for ungraded practice, then start the next round. Rejoining restores your current work and original deadline. At the deadline, completed answers are marked and unanswered parts receive no credit.")\n\t\t_button(column,"Replace missing Class sheet",func():school.request({"op":"replacement"});close())\n','')
p('\t\tif school.phase=="travel":_button(column,"Begin teaching when everyone is ready",func():school.request({"op":"begin_lesson"});close())\n\t\t_button(column,"Choose next campus activity",activity_menu)\n','')
p('\tif multiplayer.is_server() and school.phase=="complete" and completed_popup_round!=school.round_id and game.front.in_game:\n\t\tcompleted_popup_round=school.round_id\n\t\tactivity_menu.call_deferred()\n','')
p('func activity_menu() -> void:\n\tif not multiplayer.is_server():return','func activity_menu(expected_round: int) -> void:\n\tif not multiplayer.is_server() or not school.can_choose_next_activity() or school.round_id!=expected_round:return')
p('\t\tvar result: Dictionary=school.start_activity({"mode":mode_select.get_item_text(mode_select.selected)','\t\tif not school.can_choose_next_activity() or school.round_id!=expected_round:\n\t\t\tresult_label.text="This activity menu has expired."\n\t\t\treturn\n\t\tvar result: Dictionary=school.start_activity({"mode":mode_select.get_item_text(mode_select.selected)')
paper[0]=(paper[0][0],paper[0][1].replace('\telse:\n\t\t_label(column,"Practice assignments','\t\t_button(column,"Equipment guide",func():school.request({"op":"guide"});close())\n\telse:\n\t\t_label(column,"Practice assignments'))
paper=[(a,b.replace('expected_round: int','expected_epoch: int').replace('school.round_id!=expected_round','school.activity_epoch!=expected_epoch')) for a,b in paper]
make('scripts/paper_ui.gd',paper)

front=[]
def f(a,b):front.append((a,b))
f('\tsettings_host.show()\n\tbutton("Back",pause_menu if in_game else home)','\tsettings_host.show()\n\tif in_game and multiplayer.is_server() and game.school.can_choose_next_activity():\n\t\tvar expected_round: int=game.school.round_id\n\t\tbutton("Choose next campus activity",func():\n\t\t\tif not multiplayer.is_server() or not game.school.can_choose_next_activity() or game.school.round_id!=expected_round:return\n\t\t\tscreen.hide()\n\t\t\tgame.paper_ui.activity_menu(expected_round))\n\tbutton("Back",pause_menu if in_game else home)')
front=[(a,b.replace('expected_round: int=game.school.round_id','expected_epoch: int=game.school.activity_epoch').replace('game.school.round_id!=expected_round','game.school.activity_epoch!=expected_epoch').replace('activity_menu(expected_round)','activity_menu(expected_epoch)')) for a,b in front]
make('scripts/front_menu.gd',front)
make('scripts/school_world.gd', [
    ('Find your assigned room, then sit for a lecture. The host starts teaching when participants are ready.',
     'Find your assigned room. Teaching begins automatically when the two-minute countdown ends; arrivals afterward are late.')
])
