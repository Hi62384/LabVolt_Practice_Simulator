extends Node3D

const Pending = preload("res://scripts/campus/academics/pending_assessment.gd")
const AssessmentPlan = preload("res://scripts/campus/academics/ai_assessment_plan.gd")
const Metadata = preload("res://scripts/campus/academics/record_metadata.gd")
const TeachingBoard = preload("res://scripts/campus/academics/teaching_board.gd")
const Practice = preload("res://scripts/campus/academics/open_lab/practice/practice_service.gd")
const LessonBoardState = preload("res://scripts/campus/academics/lesson_board_state.gd")
const LessonPlan = preload("res://scripts/campus/academics/class_lesson_plan.gd")
const Visuals = preload("res://scripts/campus/academics/classroom_visuals.gd")
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
var sent_animation_revisions: Dictionary={}
var classroom_events: Node
var classroom_students: Node3D
var lesson_projector: Node3D
var projector_room: String=""
var lab_practice := preload("res://scripts/campus/academics/classroom_lab_practice.gd").new()

func build(owner: Node) -> void:
	game=owner
	school=game.school
	classroom_students=preload("res://scripts/campus/academics/classroom_students.gd").new()
	add_child(classroom_students)
	classroom_students.configure(game)
	lab_practice.game=game
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
		if room in game.campus.registry.lecture_rooms():
			picker.practice_requested=func(config: Dictionary):_send("practice",room,config)
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
	picker.practice_requested=func(config: Dictionary):_send("practice",room,config)
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
	if op=="hand":
		_toggle_hand(peer,room,str(config.get("class_id","")))
		return
	var error := "Approach the desk in the lecture room."
	if _inside(peer,room) and signs.has(room) and _position(peer).distance_to(signs[room].desk)<=3.6:
		if op=="start":
			if peer!=1:error="Only the host can start a class."
			elif student_has_class(peer) or classes.values().any(func(activity):return activity.get("host",0)==peer):
				error="Finish your current class before starting another."
			elif not game.host_openai.ready_for_class():error=game.host_openai.class_connection_status()
			else:
				error=_start(room,config)
				if error.is_empty():
					classes[room]["ai_teaching"]=true
					classes[room].host=peer
		elif op=="practice":error=_issue_practice(peer,room,config)
		elif op=="sign":error=_sign(peer,room)
		else:return
	if peer==multiplayer.get_unique_id():action_result(op,error)
	else:action_result.rpc_id(peer,op,error)
	if error.is_empty():_publish()

@rpc("authority","call_remote","reliable")
func action_result(op: String,error: String) -> void:
	if op in ["start","practice"] and is_instance_valid(picker):
		if error.is_empty():close_picker()
		else:picker.classroom_error(error)
	elif not error.is_empty():game.ui.log_message(error)
	elif op=="sign":game.ui.log_message("Attendance signed. Be in the room when the assessment starts.")

func _issue_practice(peer: int,room: String,config: Dictionary) -> String:
	var lab := room in ["ac_lab","dc_lab"]
	if (not lab and room not in game.campus.registry.lecture_rooms()) or classes.has(room) or (school.formal_active() and school.activity.get("room",{}).get("id","")==room):
		return "Practice sheets are available from the class desk between classes."
	var course:=str(config.get("course_id",""))
	if course not in school.course_ids() or not config.get("week") is int or not config.get("difficulty") is int or str(school.identities.get(peer,"")).is_empty():
		return "Choose a course and week."
	if lab and Practice.course_for_room(room)!=course:return "Choose the course assigned to this lab."
	var seed_value: int=school.random.randi()
	var project:=Practice.issue_for_course(course,school.course_bridge,seed_value,config.week,config.difficulty) if lab else Practice.issue_for_lecture(course,config.week,config.difficulty,school.course_bridge,seed_value)
	if project.has("error"):return str(project.error)
	var id: int=school._give(peer,project,true,false)
	if id==0:return "Free a sheet slot before requesting another worksheet."
	if not school.papers[id].held:
		var layout: Dictionary=game.campus.registry.activity_room(course,"lab" if lab else "lecture",room)
		if not layout.get("desks",[]).is_empty():school.papers[id].position=layout.desks[0]
	school.broadcast()
	return ""

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
	const Faculty=preload("res://scripts/campus/academics/faculty_roster.gd")
	var teacher:=str(config.get("teacher_override",""))
	if not teacher.is_empty() and not Faculty.has(teacher):return "Choose an existing teacher."
	if teacher.is_empty():
		teacher=game.faculty.current.get(room,"") if kind=="lab" else ""
		if course not in Faculty.entry(teacher).get("courses",[]):teacher=game.faculty.pick_lecture(course)
		if teacher.is_empty():return "No eligible teacher is available right now."
	var class_id:=Crypto.new().generate_random_bytes(16).hex_encode()
	const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
	var teaching:=LessonPlan.build(school.course_bridge.lesson_for_assignment(lesson,LessonSeconds),
		Dialogue.personalities().get(teacher,{}),class_id.hash())
	classes[room]={"id":class_id,"room":room_info,"course":course,"kind":kind,"teacher":teacher,"week":week,"difficulty":level,"extra":extra,"title":str(extra.get("title",lesson.get("title",course))),"phase":"arrival","deadline":_now()+ArrivalSeconds,"teaching":teaching,"students":{}}
	if room=="ac_lab":
		classes[room].lab_practice={"plan":lesson.get("physical_ac_plan",{}),"leads":lesson.get("physical_wire_steps",[])}
	elif course=="ETY155":
		classes[room].lab_practice={"resistance":lesson.get("scenario",{}).get("nominal_resistance",1000.)}
	elif course=="DGS266" and kind=="lab":
		classes[room].lab_practice={"digital":lesson.get("lab_validation","")}
	var present: Array[Vector3]=[]
	for peer in game.session.roster:
		if _inside(int(peer),room):present.append(_position(int(peer)))
	classroom_students.start(classes[room],room_info,present,_now())
	if not classes[room].classmates.is_empty():classes[room].classmate_assessment=lesson
	return ""

func student_has_class(peer: int, except_room := "") -> bool:
	var identity:=str(school.identities.get(peer,""))
	if identity.is_empty():return false
	if school.formal_active() and school.class_students.has(identity) and not school.class_students[identity].get("done",false):return true
	for room: String in classes:
		if room==except_room:continue
		var enrolled: Dictionary=classes[room].students.get(identity,{})
		if not enrolled.is_empty() and not enrolled.get("done",false):return true
	return false

func _sign(peer: int,room: String) -> String:
	var activity: Dictionary=classes.get(room,{})
	var phase := str(activity.get("phase",""))
	if phase not in ["arrival","lesson"] or (phase=="lesson" and _now()>=float(activity.deadline)):return "Attendance is closed."
	var identity := str(school.identities.get(peer,""))
	if identity.is_empty():return "Your student profile is still loading."
	if activity.students.has(identity):return "You already signed attendance."
	if student_has_class(peer,room):return "You are already attending another class."
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
		lab_practice.yield_bench(bench,"ac" if activity.course=="ELM253" else "dc")
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
	if multiplayer.is_server() and (not classes.is_empty() or not lab_practice.work.is_empty()):
		# Assessment generation starts when the lesson deadline is reached.
		# Extending this deadline while ai_waiting was true prevented the
		# generator from ever being called and softlocked every AI-taught class.
		check_clock+=delta
		publish_clock+=delta
		if check_clock>=.2:
			for room in classes:
				classroom_students.step(classes[room],_now(),check_clock,room)
				_hand_turn(room,classes[room],_now())
				Visuals.advance(classes[room],_now(),game.faculty.lesson_question_active(room))
			var ac: Dictionary=classes.get("ac_lab",{})
			var dc: Dictionary=classes.get("dc_lab",{})
			if lab_practice.work.get("domain","ac")=="ac":lab_practice.step(ac,_now())
			if lab_practice.work.get("domain","dc")=="dc":lab_practice.step(dc,_now())
			check_clock=0.0
			_check_students()
			_advance()
		if publish_clock>=1.0:
			publish_clock=0.0
			for activity in classes.values():
				if Visuals.uses_bench(activity):
					var reading:=lab_practice.live_readings(str(activity.id),Visuals.uses_scope_trace(activity)) if activity.phase=="lesson" else {}
					Visuals.update_bench(activity,reading)
			_publish()
	if is_instance_valid(classroom_events):classroom_events.step(_now())
	if game.front.in_game:
		classroom_students.render(game.campus.registry.locate(game.player.global_position),public_classes,delta)
	_update_views()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not is_instance_valid(game):return
	if not game.front.in_game or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or event.physical_keycode!=game.player.keys.raise_hand:return
	var room: String=game.campus.registry.locate(game.player.global_position)
	var info: Dictionary=public_classes.get(room,{})
	if info.get("phase")!="lesson" or not info.get("signed",false):return
	_send("hand",room,{"class_id":info.id})
	get_viewport().set_input_as_handled()

func _toggle_hand(peer: int,room: String,class_id: String) -> void:
	var activity: Dictionary=classes.get(room,{})
	var identity:=str(school.identities.get(peer,""))
	if activity.get("phase")!="lesson" or activity.get("id")!=class_id or not _inside(peer,room) or not activity.students.has(identity):return
	var hands: Array=activity.get_or_add("hands",[])
	if identity in hands:hands.erase(identity)
	elif hands.size()<24 and activity.get("hand_identity","")!=identity:hands.append(identity)
	_publish()

func _hand_turn(room: String,activity: Dictionary,now: float) -> void:
	if activity.phase!="lesson" or activity.get("npc_voice_question",false):return
	var hands: Array=activity.get("hands",[])
	if now<float(activity.get("next_hand",0.)):return
	activity.erase("hand_identity")
	if game.faculty.lesson_question_active(room) or classroom_events.service.rooms.has(room):return
	while not hands.is_empty():
		var identity: String=hands.pop_front()
		var peer:=int(activity.students.get(identity,{}).get("peer",0))
		if not _inside(peer,room) or str(school.identities.get(peer,""))!=identity:continue
		activity.hand_identity=identity
		activity.next_hand=now+20.
		game.faculty.invite_question(room,str(activity.teacher),peer,str(activity.id))
		return
	if activity.kind!="lecture" or lesson_duration(activity)-maxf(0.,float(activity.deadline)-now)<40.:return
	var stage:=_stage(activity)
	var topic:=str(stage.get("title",""))
	if topic.is_empty() or activity.get("npc_question_topic","")==topic:return
	for member in activity.get("classmates",{}).values():
		if not member.seated or member.action not in ["raising hand","asking for help"]:continue
		var question: String="Could you walk us through the first step?" if member.profile.confidence<.6 else "Which part of this should we check first?"
		member.action="asking a question"
		member.line=question
		member.next=now+8.
		activity.npc_question_topic=topic
		activity.next_hand=now+45.
		var phase_id:=str(activity.id)
		activity.npc_voice_question=true
		if game.faculty.has_method("pause_voice_target"):
			game.faculty.pause_voice_target({"id":str(activity.teacher),"room":room,"class_id":phase_id})
		if game.faculty.has_method("present_student_speech"):
			game.faculty.present_student_speech(room,phase_id,str(member.profile.id),question,str(member.get("mood","steady")),{},1)
		var answer: String=await game.faculty.classroom_character_exchange(activity,member,stage,question)
		while is_inside_tree() and str(classes.get(room,{}).get("id",""))==phase_id and classes.get(room,{}).get("phase","")=="lesson" and game.faculty.has_method("student_speech_pending") and game.faculty.student_speech_pending(str(member.profile.id)):
			await get_tree().create_timer(.1).timeout
		activity.npc_voice_question=false
		var current: bool=str(classes.get(room,{}).get("id",""))==phase_id and classes.get(room,{}).get("phase","")=="lesson"
		if current and not answer.is_empty():game.faculty.present_class_reaction(room,activity.teacher,"%s, %s"%[str(member.profile.name).get_slice(" ",0),answer],2)
		if game.faculty.has_method("resume_voice_channel"):game.faculty.resume_voice_channel(room,room)
		if not current or answer.is_empty():return
		break

func _advance() -> void:
	var changed := false
	var assessment_intros: Array[String]=[]
	var now:=_now()
	for room in classes.keys():
		var activity: Dictionary=classes[room]
		if activity.phase=="lesson":
			var previous:=float(activity.get("lesson_tick",now))
			var elapsed:=maxf(0.,now-previous)
			activity.lesson_tick=now
			var paused: bool=game.faculty.lesson_question_active(room) or bool(activity.get("npc_voice_question",false))
			if paused:
				if not activity.has("voice_pause_remaining"):
					activity.voice_pause_remaining=maxf(0.,float(activity.deadline)-previous)
				activity.deadline=now+float(activity.voice_pause_remaining)
				activity.lesson_pause=float(activity.get("lesson_pause",0.))+elapsed
				continue
			if activity.has("voice_pause_remaining"):
				activity.deadline=now+float(activity.voice_pause_remaining)
				activity.erase("voice_pause_remaining")
			# A final explanation queued or restored at the old deadline must
			# actually finish before the assessment transition clears narration.
			var speech: Node=game.faculty.get("speech_player") as Node
			if now>=float(activity.deadline) and is_instance_valid(speech) and (speech.presentations.has(room) or speech.queued.has(room) or speech.has_suspended(room)):
				continue
		if activity.phase=="assignment" and activity.students.values().all(func(student):return student.done):
			classes.erase(room)
			changed=true
			continue
		if _now()<float(activity.deadline):continue
		match activity.phase:
			"arrival":
				activity.phase="lesson"
				activity.deadline=now+lesson_duration(activity)
				activity.lesson_tick=now
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
	activity.ai_waiting=false
	activity.phase="assignment"
	activity.deadline=_now()+AssignmentSeconds
	classroom_students.begin_assessment(activity,_now())
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
		prepared[identity]=generated if not generated.is_empty() else activity.students[identity].project
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
	lab_practice.finish()
	for activity in classes.values():
		if activity.phase!="assignment":continue
		for identity in activity.students:
			var student: Dictionary=activity.students[identity]
			if student.done:continue
			if int(student.peer)==1 and int(student.paper)>0:_settle(activity,identity,false,"Session ended before the assessment was completed.")
			else:_withdraw_unissued(activity,identity,false)

func _reset() -> void:
	if multiplayer.is_server():lab_practice.finish()
	if is_instance_valid(classroom_events):
		classroom_events.disable()
		classroom_events.enabled=CLASSROOM_EVENTS_ENABLED
	classes.clear()
	public_classes.clear()
	sent_animation_revisions.clear()
	if is_instance_valid(picker):
		picker.queue_free()
		picker=null

func _stage(activity: Dictionary) -> Dictionary:
	var duration:=lesson_duration(activity)
	var elapsed := maxf(0.,duration-maxf(0.0,float(activity.deadline)-_now()))
	var board := LessonBoardState.at(activity.teaching,str(activity.title),elapsed,duration)
	if activity.get("ai_teaching",false):
		board["teaching_step"]=LessonPlan.step(board,elapsed,duration)
	return board

static func lesson_duration(activity: Dictionary) -> float:
	return float(activity.get("teaching",{}).get("duration_seconds",LessonSeconds))

func _publish() -> void:
	var next_sent: Dictionary={}
	var stages: Dictionary={}
	for room in classes:
		var activity: Dictionary=classes[room]
		if activity.phase!="lesson" or not activity.has("visual_slides"):continue
		var stage:=_stage(activity)
		stages[room]=stage
		Visuals.select_slide(activity,int(stage.get("index",0)),_now())
	for peer in game.session.roster:
		if int(peer)!=multiplayer.get_unique_id() and (not game.session.online or not game.session.peer_connected_now(int(peer))):continue
		var public := {}
		var identity := str(school.identities.get(peer,""))
		for room in classes:
			var activity: Dictionary=classes[room]
			var student: Dictionary=activity.students.get(identity,{})
			var in_room:=_inside(int(peer),room)
			var stage: Dictionary={}
			if in_room and activity.phase=="lesson":
				if not stages.has(room):stages[room]=_stage(activity)
				stage=stages[room]
			public[room]={"id":activity.id,"number":activity.room.number,"course":activity.course,"teacher":activity.get("teacher",""),"week":activity.week,"title":activity.title,"phase":activity.phase,"seconds":maxf(0.0,float(activity.deadline)-_now()),"signed":not student.is_empty(),"done":student.get("done",false),"stage":stage,"ai_status":activity.get("ai_status",""),"ai_teaching":activity.get("ai_teaching",false)}
			if in_room:public[room].classmates=classroom_students.snapshot(activity,_now())
			if in_room and activity.phase=="lesson":
				if activity.has("visual_playback"):
					var revision: int=activity.visual_playback.revision
					var visual_key: String="%s:%d"%[activity.id,revision]
					var show_full: bool=sent_animation_revisions.get(peer,{}).get(room,"")!=visual_key
					var animation:=Visuals.view(activity,game.faculty.lesson_question_active(room),show_full)
					if not animation.is_empty():
						public[room].animation=animation
						next_sent.get_or_add(peer,{})[room]=visual_key
				var raised: Array[int]=[]
				for raised_identity in activity.get("hands",[]):
					var raised_peer:=int(activity.students.get(raised_identity,{}).get("peer",0))
					if raised_peer>0 and _inside(raised_peer,room):raised.append(raised_peer)
				public[room].raised_peers=raised
		if int(peer)==multiplayer.get_unique_id():receive(public)
		elif game.session.online and game.session.peer_connected_now(int(peer)):receive.rpc_id(int(peer),public)
	sent_animation_revisions=next_sent

@rpc("authority","call_remote","reliable")
func receive(public: Dictionary) -> void:
	for room in public:
		var next: Dictionary=public[room].get("animation",{})
		if next.is_empty() or next.has("scene"):continue
		var previous: Dictionary=public_classes.get(room,{})
		var animation: Dictionary=previous.get("animation",{})
		if previous.get("id","")==public[room].id and animation.get("revision",-1)==next.revision and animation.has("scene"):
			next.scene=animation.scene
		else:public[room].erase("animation")
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
	var showing_projector:=false
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
		var animation: Dictionary=info.get("animation",{})
		var use_projector: bool=teaching and animation.get("surface","board")=="projector"
		var board: Node3D=sign.board
		if use_projector:
			board=_lesson_projection(room,sign.board)
			showing_projector=true
		var use_board:=teaching and not use_projector
		if sign.board.active!=use_board:sign.board.set_room_active(use_board)
		if teaching and not board.active:board.set_room_active(true)
		var lesson_key := "%s:%d:%s" % [info.id,int(info.stage.get("index",0)),str(use_projector)] if teaching else ""
		if sign.lesson_key!=lesson_key:
			sign.lesson_key=lesson_key
			if teaching:
				var location: String="Projector · Room " if use_projector else "Room "
				board.show_content(info.course,"lesson",info.title,info.stage,location+str(info.number))
			sign.erase("visual_received")
		if teaching:
			var key:="%s:%d:%s"%[info.id,int(animation.get("revision",0)),str(animation.get("playing",false))]
			var visual_stamp:=[received_at,key]
			if sign.get("visual_received",[])!=visual_stamp:
				sign.visual_received=visual_stamp
				board.show_animation(key,animation)
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
		if teaching and info.signed:text+="\n[%s] %s"%[OS.get_keycode_string(game.player.keys.raise_hand),"Lower hand" if multiplayer.get_unique_id() in info.get("raised_peers",[]) else "Raise hand"]
		var label: Label=cards[room].get_child(0)
		if label.text!=text:label.text=text
	if not showing_projector and is_instance_valid(lesson_projector) and lesson_projector.active:
		lesson_projector.set_room_active(false)
		projector_room=""
	for room in cards.keys():
		if room not in visible_cards:
			cards[room].queue_free()
			cards.erase(room)

func _lesson_projection(room: String,board: Node3D) -> Node3D:
	if not is_instance_valid(lesson_projector):
		lesson_projector=TeachingBoard.new()
		add_child(lesson_projector)
		game._box(lesson_projector,Vector3(0,1.27,0),Vector3(5.7,.11,.13),Color("455462"))
		game._box(lesson_projector,Vector3(0,-1.24,0),Vector3(5.6,.05,.07),Color("394855"))
	if projector_room!=room:
		projector_room=room
		lesson_projector.global_transform=board.global_transform
		lesson_projector.position.z+=.1
		lesson_projector.position.y+=.06
	return lesson_projector
