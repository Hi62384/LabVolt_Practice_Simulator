extends Node3D

const Pending = preload("res://scripts/campus/academics/pending_assessment.gd")
const AssessmentPlan = preload("res://scripts/campus/academics/ai_assessment_plan.gd")
const Metadata = preload("res://scripts/campus/academics/record_metadata.gd")
const TeachingBoard = preload("res://scripts/campus/academics/teaching_board.gd")
const LessonBoardState = preload("res://scripts/campus/academics/lesson_board_state.gd")
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const ArrivalSeconds := 120.0
const LessonSeconds := 420.0
const AssignmentSeconds := 1800.0
## Classroom activities include host-measured physical lab rounds.
const CLASSROOM_EVENTS_ENABLED := true

var game: Node
var school: Node
var classes := {}
var public_classes := {}
var signs := {}
var picker: Control
var overlay: CanvasLayer
var announcements: VBoxContainer
var cards := {}
var check_clock := 0.0
var publish_clock := 0.0
var received_at := 0
var classroom_events: Node

func build(owner: Node) -> void:
	game=owner
	school=game.school
	overlay=CanvasLayer.new()
	overlay.layer=12
	add_child(overlay)
	announcements=VBoxContainer.new()
	announcements.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.add_child(announcements)
	announcements.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	announcements.offset_left=22
	announcements.offset_right=294
	announcements.offset_top=80
	announcements.add_theme_constant_override("separation",8)
	for room in game.campus.registry.lecture_rooms() + ["ac_lab","dc_lab"]:_build_sign(room)
	game.session.leaving.connect(_session_leaving)
	game.session.restarted.connect(_reset)
	game.session.roster_changed.connect(_check_students)
	if CLASSROOM_EVENTS_ENABLED:
		classroom_events=preload("res://scripts/campus/academics/classroom_events/controller.gd").new()
		classroom_events.name="ClassroomEvents";add_child(classroom_events);classroom_events.configure(game);classroom_events.enabled=true

func interact(target: Node) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","") not in ["lecture_desk","lecture_attendance"]:return false
	var room := str(target.get_meta("room",""))
	if target.get_meta("role")=="lecture_attendance":
		_send("sign",room,{})
	elif public_classes.has(room):
		var info: Dictionary=public_classes[room]
		game.ui.log_message("Class in %s · %s" % [info.number,str(info.phase).capitalize()])
	elif room in ["ac_lab","dc_lab"] and school.mode in ["Freeplay","Creative Freeplay","Open Lab"]:
		game.paper_ui.teacher()
	else:
		if is_instance_valid(picker):return true
		picker=preload("res://scripts/campus/ui/host_game_page.gd").new()
		picker.classroom=str(game.campus.registry.get_room(room).number)
		picker.class_requested=func(config: Dictionary):_send("start",room,config)
		overlay.add_child(picker)
		picker.build(game)
		picker.closed.connect(close_picker)
		game.release_mouse()
	return true

func open_lab_picker(room: String) -> void:
	if room not in ["ac_lab","dc_lab"] or is_instance_valid(picker):return
	if public_classes.has(room):
		game.ui.log_message("A class is already in progress in this laboratory.")
		return
	picker=preload("res://scripts/campus/ui/host_game_page.gd").new()
	picker.classroom=str(game.campus.registry.get_room(room).number)
	picker.required_kind="lab"
	picker.required_room=room
	picker.class_requested=func(config: Dictionary):_send("start",room,config)
	overlay.add_child(picker)
	picker.build(game)
	picker.closed.connect(close_picker)
	game.release_mouse()

func close_picker() -> bool:
	if not is_instance_valid(picker):return false
	picker.hide()
	picker.queue_free()
	picker=null
	game.capture()
	return true

func _send(op: String,room: String,config: Dictionary) -> void:
	if multiplayer.is_server():_apply(multiplayer.get_unique_id(),op,room,config)
	else:command.rpc_id(1,op,room,config)

@rpc("any_peer","call_remote","reliable")
func command(op: String,room: String,config: Dictionary) -> void:
	if multiplayer.is_server():_apply(multiplayer.get_remote_sender_id(),op,room,config)

func _apply(peer: int,op: String,room: String,config: Dictionary) -> void:
	if room not in game.campus.registry.lecture_rooms() + ["ac_lab","dc_lab"] or not game.session.roster.has(peer) or var_to_bytes(config).size()>1024:return
	var error := "Approach the desk in the lecture room."
	if _inside(peer,room) and signs.has(room) and _position(peer).distance_to(signs[room].desk)<=3.6:
		if op=="start":
			if peer!=1:error="Only the host can start a class."
			elif not game.host_openai.verified_for_class():error=game.host_openai.class_connection_status()
			else:
				error=_start(room,config)
				if error.is_empty():classes[room]["ai_teaching"]=true
		elif op=="sign":error=_sign(peer,room)
		else:return
	if peer==multiplayer.get_unique_id():action_result(op,error)
	else:action_result.rpc_id(peer,op,error)
	if error.is_empty():_publish()

@rpc("authority","call_remote","reliable")
func action_result(op: String,error: String) -> void:
	if op=="start" and is_instance_valid(picker):
		if error.is_empty():close_picker()
		else:picker.classroom_error(error)
	elif not error.is_empty():game.ui.log_message(error)
	elif op=="sign":game.ui.log_message("Attendance signed. Be in the room when the assessment starts.")

func _start(room: String,config: Dictionary) -> String:
	if classes.has(room):return "This lecture room already has a class."
	if school.formal_active() and school.activity.get("room",{}).get("id","")==room:return "This lecture room is in use."
	var course := str(config.get("course_id",""))
	var week := int(config.get("week",0))
	var level := int(config.get("difficulty",-1))
	var kind := "lab" if room in ["ac_lab","dc_lab"] else "lecture"
	if course not in school.course_ids() or config.get("kind")!=kind or level not in range(5):return "Choose an appropriate course week and difficulty."
	if kind=="lab" and str(game.campus.registry.course_room(course,"lab").get("id",""))!=room:return "That course is not taught in this laboratory."
	var extra_id := str(config.get("gradebook_assessment_id",""))
	var extra := {}
	if not extra_id.is_empty():
		for option in school.official_extra_assessments(course):
			if option.id==extra_id and option.kind==kind:
				extra=option
				week=int(option.content_week)
				break
		if extra.is_empty():return "That assessment is unavailable."
	var weeks: Array=school.course_bridge.weeks(course,kind)
	if week<1 or week>weeks.size():return "That course week is unavailable."
	var room_info: Dictionary=game.campus.registry.activity_room(course,kind,room if kind=="lecture" else "")
	if room_info.is_empty():return "The selected room is unavailable."
	var lesson: Dictionary=school.course_bridge.generate(course,week,kind,level,school.random.randi())
	if lesson.is_empty() or lesson.has("error"):return "Could not prepare the class."
	if kind=="lab" and not lesson.get("practical",{}).is_empty():
		if lesson.practical.get("blocked",false):return str(lesson.practical.get("reason","Required practical equipment is unavailable."))
		var capability: Dictionary=school.equipment_adapter.call("supports",lesson)
		if not capability.get("ok",false):return str(capability.get("error","Practical grading is unavailable."))
	var teacher: String=game.faculty.current.get(room,"") if kind=="lab" else ""
	if teacher.is_empty() or course not in preload("res://scripts/campus/academics/faculty_roster.gd").entry(teacher).get("courses",[]):teacher=game.faculty.pick_lecture(course)
	if teacher.is_empty():return "No eligible teacher is available right now."
	if course not in preload("res://scripts/campus/academics/faculty_roster.gd").entry(teacher).courses:return "The current lab instructor does not teach that course."
	var teaching: Dictionary=school.course_bridge.lesson_for_assignment(lesson,LessonSeconds)
	classes[room]={"id":Crypto.new().generate_random_bytes(16).hex_encode(),"room":room_info,"course":course,"kind":kind,"teacher":teacher,"week":week,"difficulty":level,"extra":extra,"title":str(extra.get("title",lesson.get("title",course))),"phase":"arrival","deadline":_now()+ArrivalSeconds,"teaching":teaching,"students":{}}
	return ""

func _sign(peer: int,room: String) -> String:
	var activity: Dictionary=classes.get(room,{})
	var phase := str(activity.get("phase",""))
	if phase not in ["arrival","lesson"] or (phase=="lesson" and _now()>=float(activity.deadline)):return "Attendance is closed."
	var identity := str(school.identities.get(peer,""))
	if identity.is_empty():return "Your student profile is still loading."
	if activity.students.has(identity):return "You already signed attendance."
	for other in classes.values():
		var enrolled: Dictionary=other.students.get(identity,{})
		if not enrolled.is_empty() and not enrolled.get("done",false):return "You are already attending another class."
	var assignment: Dictionary=school.course_bridge.generate(activity.course,activity.week,str(activity.get("kind","lecture")),activity.difficulty,school.random.randi())
	if assignment.is_empty() or assignment.has("error"):return "Could not prepare your assessment."
	if str(activity.get("kind","lecture"))=="lab" and not assignment.get("practical",{}).is_empty():
		if assignment.practical.get("blocked",false):return str(assignment.practical.get("reason","Required practical equipment is unavailable."))
		var capability: Dictionary=school.equipment_adapter.call("supports",assignment)
		if not capability.get("ok",false):return str(capability.get("error","Practical grading is unavailable."))
	var extra: Dictionary=activity.extra
	assignment.official_curriculum_id=str(extra.get("id","%s:%d" % [str(activity.get("kind","lecture")),int(activity.week)]))
	if not extra.is_empty():
		assignment.title=extra.title
		assignment.official_assessment_title=extra.title
	var bench := -1
	if activity.get("kind","")=="lab" and activity.course in ["ETY155","ELM253","DGS266"]:
		var count: int=game.session.labs.size() if activity.course=="ELM253" else game.dc_lab.benches.size()
		if count<1:return "No laboratory bench is available."
		var counts := []
		counts.resize(count)
		counts.fill(0)
		for participant in activity.students.values():
			var used := int(participant.get("bench",-1))
			if used>=0 and used<counts.size():counts[used]+=1
		bench=counts.find(counts.min())
	activity.students[identity]={"peer":peer,"project":assignment,"replay":school._is_replay(identity,assignment),"done":false,"paper":0,"failure":"","bench":bench}
	school.record_room_attendance(peer,activity.id,assignment,phase=="lesson")
	game.faculty.acknowledge_attendance(room,str(activity.teacher),peer)
	return ""

func _now() -> float:return Time.get_ticks_msec()/1000.0

func _position(peer: int) -> Vector3:
	return game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)

func _inside(peer: int,room: String) -> bool:
	if not game.session.roster.has(peer):return false
	var point := _position(peer)
	return point.is_finite() and game.campus.registry.room_contains(room,point)

func _check_students() -> void:
	if not multiplayer.is_server():return
	for room in classes:
		var activity: Dictionary=classes[room]
		if activity.phase!="assignment" or _now()>=float(activity.deadline):continue
		for identity in activity.students:
			var student: Dictionary=activity.students[identity]
			if student.done:continue
			var connected_peer: Variant=school.identities.find_key(identity)
			var peer := int(connected_peer) if connected_peer!=null else 0
			student.peer=peer
			if peer==1 and int(student.paper)>0 and not _inside(peer,room) and student.failure.is_empty():
				student.failure="Left the classroom before completing the assessment."
			if not student.failure.is_empty():
				_settle(activity,identity,false,student.failure)
				continue
			var paper: Dictionary=school.papers.get(student.paper,{})
			if peer>0 and not paper.is_empty() and paper.owner!=peer:
				paper.owner=peer
				paper.revision+=1
				school.broadcast()
			elif int(student.paper)==0 and _inside(peer,room) and _now()>=float(student.get("retry_at",0.0)):
				if _issue_assessment(room,activity,student):school.broadcast()

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	if multiplayer.is_server() and not classes.is_empty():
		for activity in classes.values():
			if activity.phase=="lesson" and activity.get("ai_waiting",false):activity.deadline+=delta
		check_clock+=delta
		publish_clock+=delta
		if check_clock>=.2:
			check_clock=0.0
			_check_students()
			_advance()
		if publish_clock>=1.0:
			publish_clock=0.0
			_publish()
	if is_instance_valid(classroom_events):classroom_events.step(_now())
	_update_views()

func _advance() -> void:
	var changed := false
	var assessment_intros: Array[String]=[]
	for room in classes.keys():
		var activity: Dictionary=classes[room]
		if activity.phase=="assignment" and activity.students.values().all(func(student):return student.done):
			classes.erase(room)
			changed=true
			continue
		if _now()<float(activity.deadline):continue
		match activity.phase:
			"arrival":
				activity.phase="lesson"
				activity.deadline=_now()+LessonSeconds
				activity.ai_waiting=activity.get("ai_teaching",false)
				changed=true
			"lesson":
				if _now()<float(activity.get("enrollment_retry_at",0.0)):continue
				if _begin_assignment(room,activity):
					changed=true
					assessment_intros.append(room)
			"assignment":
				for identity in activity.students:
					var student: Dictionary=activity.students[identity]
					if student.done:continue
					if int(student.paper)==0:_withdraw_unissued(activity,identity)
					else:_settle(activity,identity,true,str(student.failure))
	if changed:_publish()
	if is_instance_valid(classroom_events) and classroom_events.enabled and is_instance_valid(game.faculty):
		for room in assessment_intros:
			if classes.has(room):game.faculty.present_assessment_intro(room,str(classes[room].teacher),str(classes[room].course))

func _begin_assignment(room: String, activity: Dictionary) -> bool:
	if activity.get("ai_teaching",false) and not activity.students.is_empty() and not _prepare_ai_assessments(room,activity):
		return false
	var records: Array[Dictionary]=[]
	for identity in activity.students:
		var student: Dictionary=activity.students[identity]
		var connected_peer: Variant=school.identities.find_key(identity)
		var peer := int(connected_peer) if connected_peer!=null else 0
		student.peer=peer
		if not student.get("replay",false):
			var record: Dictionary=school._enrollment_record(identity,activity.id,student.project,peer==1)
			record.room_class=true
			records.append(record)
	var enrollment_error: Error=Pending.enroll(school.archive,records,school._persist_archive) if not records.is_empty() else OK
	if enrollment_error!=OK:
		if not activity.has("enrollment_retry_at"):
			for student in activity.students.values():
				if int(student.peer)>0:school._notice(int(student.peer),"Assessment enrollment could not be saved (%s). Retrying without starting the assignment timer."%error_string(enrollment_error))
		activity.enrollment_retry_at=_now()+2.0
		return false
	if is_instance_valid(classroom_events) and classroom_events.enabled:classroom_events.begin_assessment(room,str(activity.id),_now())
	activity.phase="assignment"
	activity.deadline=_now()+AssignmentSeconds
	for identity in activity.students:
		var student: Dictionary=activity.students[identity]
		if not student.get("replay",false):
			var record: Dictionary=records.filter(func(candidate: Dictionary):return candidate.profile==identity)[0]
			student.project.merge(Metadata.from_project(record),true)
		if _inside(int(student.peer),room):_issue_assessment(room,activity,student)
	school.broadcast()
	return true

func _prepare_ai_assessments(room: String, activity: Dictionary) -> bool:
	var state: Dictionary=activity.get_or_add("assessment_plan_state",{})
	var reference: Dictionary=activity.students.values()[0].project
	var plan:=AssessmentPlan.plan(game.host_openai,state,reference,_stage(activity),
		func():return is_same(classes.get(room),activity) and activity.phase=="lesson")
	activity.ai_status=state.get("status","")
	if plan.is_empty():return false
	var prepared := {}
	for identity in activity.students:
		if activity.students[identity].project.has("assessment_focus"):continue
		var generated: Dictionary=school.compile_ai_assessment(activity.students[identity].project,plan,identity)
		if generated.is_empty():
			AssessmentPlan.retry(state)
			activity.ai_status=state.status
			return false
		prepared[identity]=generated
	for identity in prepared:activity.students[identity].project=prepared[identity]
	return true

func _issue_assessment(room: String,activity: Dictionary,student: Dictionary) -> bool:
	if int(student.paper)>0:return false
	var peer := int(student.peer)
	var id: int=school._give(peer,student.project,false,false,true)
	if id<=0:
		if not student.has("retry_at"):school._notice(peer,"Your assessment paper could not be created. Stay in the classroom while the host retries.")
		student.retry_at=_now()+2.0
		return false
	var paper: Dictionary=school.papers[id]
	paper.class_round=-1
	paper.assessment_id=activity.id
	paper.replay=bool(student.get("replay",false))
	paper.room_class=room
	paper.room_bench=int(student.get("bench",-1))
	var desk: int=activity.students.values().find(student)
	var desk_count: int=activity.room.desks.size()
	paper.position=activity.room.desks[desk%desk_count]+Vector3(.29*floori(float(desk)/desk_count),.045,0)
	paper.held=paper.held and game.dc_lab.held_board(peer)<0
	if str(paper.course_id).begins_with("MTH"):paper.math_policy=school.course_bridge.paper_policy(student.project,false)
	student.paper=id
	school._notice(peer,"Your assessment is ready in room "+str(activity.room.number)+".")
	return true

func _withdraw_unissued(activity: Dictionary,identity: String,notify := true) -> void:
	var student: Dictionary=activity.students[identity]
	var attempt_id := str(school._enrollment_record(identity,activity.id,student.project,false).id)
	if Pending.withdraw(school.archive,identity,attempt_id,school._persist_archive)!=OK:return
	student.done=true
	if notify and int(student.peer)>0:school._notice(int(student.peer),"The assessment ended before your paper was issued. No mark was recorded.")

func _settle(activity: Dictionary,identity: String,expired: bool,reason: String) -> void:
	var student: Dictionary=activity.students[identity]
	var paper: Dictionary=school.papers.get(student.paper,{})
	if paper.is_empty():
		paper={"identity":identity,"owner":student.peer,"project":student.project,"answers":{},"mark":{},"revision":0,"class_round":-1,"assessment_id":activity.id,"lesson":false,"replay":bool(student.get("replay",false))}
	school._mark(paper,expired,reason)
	if not paper.mark.is_empty():
		student.done=true
		if school.papers.has(student.paper):
			paper.held=false
			paper.stowed=true
		school.broadcast()

func assigned_lab(peer: int) -> Dictionary:
	for room in ["dc_lab","ac_lab"]:
		var activity: Dictionary=classes.get(room,{})
		if activity.get("phase","")!="assignment":continue
		var student: Dictionary=activity.get("students",{}).get(str(school.identities.get(peer,"")),{})
		if not student.is_empty() and not student.get("done",true) and int(student.get("bench",-1))>=0:
			return {"bench":int(student.bench),"course":str(activity.course),"paper":int(student.get("paper",0))}
	return {}

func has_active_lab_assessment(peer: int,bench: int) -> bool:
	var assignment := assigned_lab(peer)
	return assignment.get("course","")=="ETY155" and int(assignment.get("bench",-1))==bench

func paper_action_allowed(peer: int,paper: Dictionary,op: String) -> bool:
	if not paper.mark.is_empty():return true
	var room := str(paper.room_class)
	var activity: Dictionary=classes.get(room,{})
	if activity.get("id","")!=paper.assessment_id or activity.get("phase","")!="assignment":return false
	if not _inside(peer,room) or _now()>=float(activity.deadline):return false
	var student: Dictionary=activity.students.get(paper.identity,{})
	if student.get("done",true) or not student.get("failure","").is_empty():return false
	if op=="trash":
		school._notice(peer,"Submit the assessment or wait for it to be collected.")
		return false
	return true

func paper_submitted(paper: Dictionary) -> void:
	var activity: Dictionary=classes.get(paper.room_class,{})
	var student: Dictionary=activity.get("students",{}).get(paper.identity,{})
	if not student.is_empty() and activity.id==paper.assessment_id:student.done=true

func _session_leaving() -> void:
	if is_instance_valid(classroom_events):classroom_events.disable()
	if not multiplayer.is_server():return
	for activity in classes.values():
		if activity.phase!="assignment":continue
		for identity in activity.students:
			var student: Dictionary=activity.students[identity]
			if student.done:continue
			if int(student.peer)==1 and int(student.paper)>0:_settle(activity,identity,false,"Session ended before the assessment was completed.")
			else:_withdraw_unissued(activity,identity,false)

func _reset() -> void:
	if is_instance_valid(classroom_events):
		classroom_events.disable()
		classroom_events.enabled=CLASSROOM_EVENTS_ENABLED
	classes.clear()
	public_classes.clear()
	if is_instance_valid(picker):
		picker.queue_free()
		picker=null

func _stage(activity: Dictionary) -> Dictionary:
	var elapsed := LessonSeconds-maxf(0.0,float(activity.deadline)-_now())
	var board := LessonBoardState.at(activity.teaching,str(activity.title),elapsed,LessonSeconds)
	if activity.get("ai_teaching",false):
		board["teaching_step"]=preload("res://scripts/campus/academics/adaptive_lesson.gd").window(elapsed,LessonSeconds)
	return board

func _publish() -> void:
	for peer in game.session.roster:
		var public := {}
		var identity := str(school.identities.get(peer,""))
		for room in classes:
			var activity: Dictionary=classes[room]
			var student: Dictionary=activity.students.get(identity,{})
			var stage := _stage(activity) if activity.phase=="lesson" and _inside(int(peer),room) else {}
			public[room]={"id":activity.id,"number":activity.room.number,"course":activity.course,"teacher":activity.get("teacher",""),"week":activity.week,"title":activity.title,"phase":activity.phase,"seconds":maxf(0.0,float(activity.deadline)-_now()),"signed":not student.is_empty(),"done":student.get("done",false),"stage":stage,"ai_status":activity.get("ai_status",""),"ai_teaching":activity.get("ai_teaching",false)}
		if int(peer)==multiplayer.get_unique_id():receive(public)
		elif game.session.online and game.session.peer_connected_now(int(peer)):receive.rpc_id(int(peer),public)

@rpc("authority","call_remote","reliable")
func receive(public: Dictionary) -> void:
	public_classes=public
	received_at=Time.get_ticks_msec()

func _build_sign(room: String) -> void:
	var info: Dictionary=game.campus.registry.get_room(room)
	if info.is_empty():return
	var center: Vector3=game.campus.registry.vector(info.center)
	var floor_y: float=game.campus.registry.vector(info.get("bounds_min",[center.x,0.0,center.z])).y
	var room_size: Vector3 = game.campus.registry.vector(info.size)
	var desk := Vector3(center.x+(-4.45 if float(info.door[0])>center.x else 4.45),floor_y,center.z - room_size.z * .5 + 2.15)
	# Lab class tables sit near the entry aisle so they are visible and reachable
	# without colliding with the instructor, lab benches, or equipment.
	if room in ["ac_lab", "dc_lab"]:
		# M101 racks line the south wall. M103 benches occupy the north end.
		var wall_side := 1.0 if room == "ac_lab" else -1.0
		desk = Vector3(center.x, floor_y, center.z + wall_side * (room_size.z * .5 - .64))
	if room in ["ac_lab", "dc_lab"]:
		var class_table:=StaticBody3D.new()
		class_table.position=desk
		class_table.collision_layer=5;class_table.collision_mask=0
		class_table.set_meta("role","lecture_desk");class_table.set_meta("room",room)
		class_table.set_meta("label","Lab Guide")
		add_child(class_table)
		var table_hit:=CollisionShape3D.new();var table_shape:=BoxShape3D.new();table_shape.size=Vector3(1.5,.12,.85);table_hit.shape=table_shape;table_hit.position.y=.78;class_table.add_child(table_hit)
		game._box(class_table,Vector3(0,.78,0),Vector3(1.5,.12,.85),Color("a98265"))
		for x in [-.65,.65]:
			for z in [-.32,.32]:
				var leg_position := Vector3(x,.38,z)
				var leg_size := Vector3(.07,.76,.07)
				game._box(class_table,leg_position,leg_size,Color("53666e"))
				var leg := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = leg_size
				leg.shape = shape
				leg.position = leg_position
				class_table.add_child(leg)
		for x in [-.61,.61]:game._box(class_table,Vector3(x,.70,0),Vector3(.055,.08,.60),Color("53666e"))
	var body := StaticBody3D.new()
	body.position=desk+Vector3(.48,.87,.05)
	body.collision_layer=4
	body.collision_mask=0
	body.set_meta("role","lecture_attendance")
	body.set_meta("room",room)
	body.set_meta("label","Sign attendance")
	add_child(body)
	game._box(body,Vector3.ZERO,Vector3(.30,.055,.22),Color("e5d9b6"))
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.45,.20,.35)
	hit.shape=shape
	body.add_child(hit)
	var marker := Label3D.new()
	marker.position.y=.12
	marker.text="!"
	marker.font_size=42
	marker.pixel_size=.0025
	marker.modulate=Color("ffdb6e")
	marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	body.add_child(marker)
	var board := TeachingBoard.new()
	board.position=center+Vector3(0,2.18,-5.72)
	add_child(board)
	board.set_room_active(false)
	signs[room]={"body":body,"marker":marker,"board":board,"desk":desk,"lesson_key":""}

func _update_views() -> void:
	var elapsed := (Time.get_ticks_msec()-received_at)/1000.0
	var visible_cards := []
	var local_room: String = game.campus.registry.locate(game.player.global_position)
	var show_local_only := public_classes.has(local_room)
	for room in signs:
		var info: Dictionary=public_classes.get(room,{})
		var sign: Dictionary=signs[room]
		var phase := str(info.get("phase",""))
		var remaining := float(info.get("seconds",0))-elapsed
		var signing := phase=="arrival" or (phase=="lesson" and remaining>0)
		sign.body.visible=signing
		sign.body.collision_layer=4 if signing else 0
		sign.marker.text="✓" if info.get("signed",false) else "!"
		var physical_board_event: bool=is_instance_valid(classroom_events) and classroom_events.enabled and is_instance_valid(classroom_events.service) and classroom_events.service.rooms.has(room) and classroom_events.service.rooms[room].round.mode=="board"
		var projected_event: bool=is_instance_valid(classroom_events) and is_instance_valid(classroom_events.projector) and classroom_events.projector.active_room==room and classroom_events.projector.board.visible
		var event_board_active: bool=physical_board_event or projected_event
		var teaching: bool=info.get("phase","")=="lesson" and not event_board_active and not info.get("stage",{}).is_empty() and game.front.in_game and game.campus.registry.room_contains(room,game.player.global_position)
		if sign.board.active!=teaching:sign.board.set_room_active(teaching)
		var lesson_key := "%s:%d" % [info.id,int(info.stage.get("index",0))] if teaching else ""
		if sign.lesson_key!=lesson_key:
			sign.lesson_key=lesson_key
			if teaching:sign.board.show_content(info.course,"lesson",info.title,info.stage,"Room "+str(info.number))
		if not game.front.in_game or info.is_empty() or (phase!="arrival" and not teaching and (not info.signed or info.done)):continue
		if show_local_only and room != local_room: continue
		visible_cards.append(room)
		if not cards.has(room):
			var panel := PanelContainer.new()
			panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
			panel.add_theme_stylebox_override("panel",Tokens.surface(Tokens.SURFACE,Tokens.BORDER,8))
			var label := UI.text("")
			panel.add_child(label)
			announcements.add_child(panel)
			cards[room]=panel
		var seconds := maxi(0,ceili(float(info.seconds)-elapsed))
		var title := "Class starting" if info.phase=="arrival" else "Assessment" if info.phase=="assignment" else "Lesson"
		if info.phase=="lesson":title=str(info.get("stage",{}).get("teaching_step",{}).get("title",title))
		var text := "%s · %s\n%s · Week %d   %d:%02d" % [title,info.number,info.course,info.week,seconds/60,seconds%60]
		if not str(info.get("ai_status","")).is_empty():text+="\n"+str(info.ai_status)
		var label: Label=cards[room].get_child(0)
		if label.text!=text:label.text=text
	for room in cards.keys():
		if room not in visible_cards:
			cards[room].queue_free()
			cards.erase(room)
