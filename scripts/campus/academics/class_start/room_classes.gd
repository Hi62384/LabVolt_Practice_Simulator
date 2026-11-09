extends Node3D

const Rooms = preload("res://scripts/campus/world/room_registry.gd")
const Pending = preload("res://scripts/campus/academics/pending_assessment.gd")
const Metadata = preload("res://scripts/campus/academics/record_metadata.gd")
const TeachingBoard = preload("res://scripts/campus/academics/teaching_board.gd")
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const ArrivalSeconds := 120.0
const LessonSeconds := 420.0
const AssignmentSeconds := 1800.0

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

func build(owner: Node) -> void:
	game=owner
	school=game.school
	overlay=CanvasLayer.new()
	overlay.layer=12
	add_child(overlay)
	announcements=VBoxContainer.new()
	announcements.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.add_child(announcements)
	announcements.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	announcements.offset_left=-370
	announcements.offset_right=-22
	announcements.offset_top=80
	announcements.add_theme_constant_override("separation",8)
	for room in Rooms.LECTURE_ROOMS:_build_sign(room)
	game.session.leaving.connect(_session_leaving)
	game.session.restarted.connect(_reset)
	game.session.roster_changed.connect(_check_students)

func interact(target: Node) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","") not in ["lecture_desk","lecture_attendance"]:return false
	var room := str(target.get_meta("room",""))
	if target.get_meta("role")=="lecture_attendance":
		_send("sign",room,{})
	elif public_classes.has(room):
		var info: Dictionary=public_classes[room]
		game.ui.log_message("Class in %s · %s" % [info.number,str(info.phase).capitalize()])
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
	if room not in Rooms.LECTURE_ROOMS or not game.session.roster.has(peer) or var_to_bytes(config).size()>1024:return
	var error := "Approach the desk in the lecture room."
	if _inside(peer,room) and signs.has(room) and _position(peer).distance_to(signs[room].desk)<=3.6:
		if op=="start":error=_start(room,config)
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
	if course not in school.course_ids() or config.get("kind")!="lecture" or level not in range(5):return "Choose a lecture and difficulty."
	var extra_id := str(config.get("gradebook_assessment_id",""))
	var extra := {}
	if not extra_id.is_empty():
		for option in school.official_extra_assessments(course):
			if option.id==extra_id and option.kind=="lecture":
				extra=option
				week=int(option.content_week)
				break
		if extra.is_empty():return "That assessment is unavailable."
	var weeks: Array=school.course_bridge.weeks(course,"lecture")
	if week<1 or week>weeks.size():return "That lecture week is unavailable."
	var room_info: Dictionary=game.campus.registry.activity_room(course,"lecture",room)
	if room_info.is_empty():return "Lecture room unavailable."
	var lesson: Dictionary=school.course_bridge.generate(course,week,"lecture",level,school.random.randi())
	if lesson.is_empty() or lesson.has("error"):return "Could not prepare the lecture."
	var teaching: Dictionary=school.course_bridge.lesson_for_assignment(lesson,LessonSeconds)
	classes[room]={"id":Crypto.new().generate_random_bytes(16).hex_encode(),"room":room_info,"course":course,"week":week,"difficulty":level,"extra":extra,"title":str(extra.get("title",lesson.get("title",course))),"phase":"arrival","deadline":_now()+ArrivalSeconds,"teaching":teaching,"students":{}}
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
	var assignment: Dictionary=school.course_bridge.generate(activity.course,activity.week,"lecture",activity.difficulty,school.random.randi())
	if assignment.is_empty() or assignment.has("error"):return "Could not prepare your assessment."
	var extra: Dictionary=activity.extra
	assignment.official_curriculum_id=str(extra.get("id","lecture:%d" % int(activity.week)))
	if not extra.is_empty():
		assignment.title=extra.title
		assignment.official_assessment_title=extra.title
	activity.students[identity]={"peer":peer,"project":assignment,"done":false,"paper":0,"failure":""}
	school.record_room_attendance(peer,activity.id,assignment,phase=="lesson")
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
			if not _inside(int(student.peer),room) and student.failure.is_empty():
				student.failure="Left the classroom before completing the assessment."
			if not student.failure.is_empty():_settle(activity,identity,false,student.failure)

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	if multiplayer.is_server() and not classes.is_empty():
		check_clock+=delta
		publish_clock+=delta
		if check_clock>=.2:
			check_clock=0.0
			_check_students()
			_advance()
		if publish_clock>=1.0:
			publish_clock=0.0
			_publish()
	_update_views()

func _advance() -> void:
	var changed := false
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
				changed=true
			"lesson":
				if _begin_assignment(room,activity):changed=true
			"assignment":
				for identity in activity.students:
					var student: Dictionary=activity.students[identity]
					if not student.done:_settle(activity,identity,true,str(student.failure))
	if changed:_publish()

func _begin_assignment(room: String, activity: Dictionary) -> bool:
	var records: Array[Dictionary]=[]
	for identity in activity.students:
		var student: Dictionary=activity.students[identity]
		var connected_peer: Variant=school.identities.find_key(identity)
		var peer := int(connected_peer) if connected_peer!=null else 0
		student.peer=peer
		var record: Dictionary=school._enrollment_record(identity,activity.id,student.project,peer==1)
		record.room_class=true
		records.append(record)
	if not records.is_empty() and Pending.enroll(school.archive,records,school._persist_archive)!=OK:return false
	activity.phase="assignment"
	activity.deadline=_now()+AssignmentSeconds
	var desk := 0
	for record in records:
		var student: Dictionary=activity.students[record.profile]
		student.project.merge(Metadata.from_project(record),true)
		var peer := int(student.peer)
		if not _inside(peer,room):
			student.failure="Was outside the classroom when the assessment started."
			_settle(activity,record.profile,false,student.failure)
			continue
		var id: int=school._give(peer,student.project,false,false,true)
		if id<=0:continue
		var paper: Dictionary=school.papers[id]
		paper.class_round=-1
		paper.assessment_id=activity.id
		paper.room_class=room
		var desk_count: int=activity.room.desks.size()
		paper.position=activity.room.desks[desk%desk_count]+Vector3(.29*floori(float(desk)/desk_count),.045,0)
		paper.held=paper.held and game.dc_lab.held_board(peer)<0
		if str(paper.course_id).begins_with("MTH"):paper.math_policy=school.course_bridge.paper_policy(student.project,false)
		student.paper=id
		school._notice(peer,"Your assessment is ready in room "+str(activity.room.number)+".")
		desk+=1
	school.broadcast()
	return true

func _settle(activity: Dictionary,identity: String,expired: bool,reason: String) -> void:
	var student: Dictionary=activity.students[identity]
	var paper: Dictionary=school.papers.get(student.paper,{})
	if paper.is_empty():
		paper={"identity":identity,"owner":student.peer,"project":student.project,"answers":{},"mark":{},"revision":0,"class_round":-1,"assessment_id":activity.id,"lesson":false}
	school._mark(paper,expired,reason)
	if not paper.mark.is_empty():
		student.done=true
		if school.papers.has(student.paper):
			paper.held=false
			paper.stowed=true
		school.broadcast()

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
	if not multiplayer.is_server():return
	for activity in classes.values():
		if activity.phase!="assignment":continue
		for identity in activity.students:
			if not activity.students[identity].done:_settle(activity,identity,false,"Session ended before the assessment was completed.")

func _reset() -> void:
	classes.clear()
	public_classes.clear()
	if is_instance_valid(picker):
		picker.queue_free()
		picker=null

func _stage(activity: Dictionary) -> Dictionary:
	var elapsed := LessonSeconds-maxf(0.0,float(activity.deadline)-_now())
	var stages: Array=activity.teaching.get("stages",[])
	if stages.is_empty():
		return {"title":activity.title,"text":activity.teaching.get("worked",activity.teaching.get("equipment_text",""))}
	for index in stages.size():
		var stage: Dictionary=stages[index]
		elapsed-=float(stage.get("duration_seconds",stage.get("duration",LessonSeconds/stages.size())))
		if elapsed<0.0 or index==stages.size()-1:
			var current := stage.duplicate()
			current.index=index
			current.count=stages.size()
			return current
	return {}

func _publish() -> void:
	for peer in game.session.roster:
		var public := {}
		var identity := str(school.identities.get(peer,""))
		for room in classes:
			var activity: Dictionary=classes[room]
			var student: Dictionary=activity.students.get(identity,{})
			var stage := _stage(activity) if activity.phase=="lesson" and _inside(int(peer),room) else {}
			public[room]={"id":activity.id,"number":activity.room.number,"course":activity.course,"week":activity.week,"title":activity.title,"phase":activity.phase,"seconds":maxf(0.0,float(activity.deadline)-_now()),"signed":not student.is_empty(),"done":student.get("done",false),"stage":stage}
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
	var desk := center+Vector3(-4.45 if room=="elm253_lecture" else 4.45,.88,-3.85)
	var body := StaticBody3D.new()
	body.position=desk+Vector3(.46,.09,.05)
	body.collision_layer=0
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
	marker.position.y=.48
	marker.text="!"
	marker.font_size=80
	marker.pixel_size=.004
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
	for room in signs:
		var info: Dictionary=public_classes.get(room,{})
		var sign: Dictionary=signs[room]
		var phase := str(info.get("phase",""))
		var remaining := float(info.get("seconds",0))-elapsed
		var signing := phase=="arrival" or (phase=="lesson" and remaining>0)
		sign.body.visible=signing
		sign.body.collision_layer=4 if signing else 0
		sign.marker.text="✓" if info.get("signed",false) else "!"
		var teaching: bool=info.get("phase","")=="lesson" and not info.get("stage",{}).is_empty() and game.front.in_game and game.campus.registry.room_contains(room,game.player.global_position)
		if sign.board.active!=teaching:sign.board.set_room_active(teaching)
		var lesson_key := "%s:%d" % [info.id,int(info.stage.get("index",0))] if teaching else ""
		if sign.lesson_key!=lesson_key:
			sign.lesson_key=lesson_key
			if teaching:sign.board.show_content(info.course,"lesson",info.title,info.stage,"Room "+str(info.number))
		if not game.front.in_game or info.is_empty() or (phase!="arrival" and not teaching and (not info.signed or info.done)):continue
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
		var text := "%s · %s\n%s · Week %d   %d:%02d" % [title,info.number,info.course,info.week,seconds/60,seconds%60]
		var label: Label=cards[room].get_child(0)
		if label.text!=text:label.text=text
	for room in cards.keys():
		if room not in visible_cards:
			cards[room].queue_free()
			cards.erase(room)
