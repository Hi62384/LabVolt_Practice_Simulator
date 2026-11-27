extends SceneTree
## Real Main, profile, active assessment, perceived phone use, and inventory save.
const Profile=preload("res://scripts/electronics_profile.gd")
const ROOM:="ac_lab"
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> bool:
	if not ok:failures.append(message);printerr("PHONE DISCIPLINE FAIL: "+message)
	return ok

func finish(game: Node) -> void:
	print("PHONE_DISCIPLINE_INTEGRATION %s"%("PASS" if failures.is_empty() else "FAIL"))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	create_timer(45.).timeout.connect(func():quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	for button in game.front.body.find_children("*","Button",true,false):
		if button.text=="Singleplayer":button.pressed.emit();break
	await process_frame
	for button in game.front.body.find_children("*","Button",true,false):
		if button.text=="Play":button.pressed.emit();break
	for frame in 2:await process_frame
	check(game.front.in_game and not game.session.online,"singleplayer session enters normally")
	game.player.set_physics_process(false)
	game.client_preferences.values.teacher_speech=false
	game.client_preferences.values.teacher_subtitles=true
	game.faculty.set_process(false)
	var classes: Node=game.lecture_classes
	classes.set_process(false)
	classes.classroom_events.enabled=true
	var phone: Node=game.smartphones
	phone.set_process(false)
	var profile: RefCounted=game.electronics.profile
	profile.data.dollars=10000
	profile.buy_smartphone("basic")
	if not check(profile.operation_succeeded and profile.data.dorm.get("smartphones",{}).size()==1,"owned phone purchase succeeds"):
		await finish(game);return
	var id: String=profile.data.dorm.smartphones.keys()[0]
	var identity:=str(game.school.local_identity)
	check(game.dorm_interactions.authenticated_identity(1)==identity,"local player is authenticated")
	check(phone._valid_classroom_phone(1,id,identity),"owned phone is in the player's hotbar")
	game.player.global_position=classes.signs[ROOM].desk
	if not check(classes._start(ROOM,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":0,"teacher_override":"dr_volts"})=="","actual class starts"):
		await finish(game);return
	var activity: Dictionary=classes.classes[ROOM]
	var attendance: String=classes._sign(1,ROOM)
	if not check(attendance.is_empty(),"authenticated player signs attendance: "+attendance):
		await finish(game);return
	activity.phase="lesson"
	activity.deadline=classes._now()+300.
	if not check(classes._begin_assignment(ROOM,activity),"actual assessment is issued"):
		await finish(game);return
	classes._publish()
	game.faculty.current[ROOM]=str(activity.teacher)
	game.faculty._show_lab(ROOM,str(activity.teacher))
	var teacher: Node3D=game.faculty._model_for_room(ROOM,str(activity.teacher))
	if not check(is_instance_valid(teacher),"instructor exists for real visibility checks"):
		await finish(game);return
	var origin: Vector3=game.faculty._teacher_position(ROOM)
	var point: Vector3=origin+teacher.global_basis.z.normalized()*2.
	game.player.global_position=point
	await physics_frame
	check(game.campus.registry.locate(point)==ROOM,"phone use occurs inside the classroom")
	check(not phone._classroom_context(1).is_empty(),"active assessment permits a verified phone observation")
	var paper_id:=int(activity.students[identity].paper)
	if not check(paper_id>0 and game.school.papers.has(paper_id),"active work exists during discipline"):
		await finish(game);return
	game.school.papers[paper_id].answers["0"]="unfinished working"
	var paper_before: Dictionary=game.school.papers[paper_id].duplicate(true)
	var archive_before: Dictionary=game.school.archive.duplicate(true)
	var inventory_before: Dictionary=profile.data.dorm.smartphones.duplicate(true)
	var record_key:=str(activity.id)+":"+identity
	phone._apply_classroom_open(999,true,id)
	phone._apply_classroom_open(1,true,"f".repeat(32))
	check(not game.faculty.discipline_records.has(record_key),"unauthenticated or unowned phone evidence is ignored")
	phone._apply_classroom_open(1,true,id)
	var record: Dictionary=game.faculty.discipline_records.get(record_key,{})
	if not check(int(record.get("count",0))==1,"the actual visible phone reaches teacher discipline"):
		print("PHONE DISCIPLINE DEBUG teacher=",origin," forward=",teacher.global_basis.z," player=",point," open=",phone.classroom_open)
		await finish(game);return
	check(phone._saved_custody(identity).is_empty(),"first observed phone use cannot confiscate")
	phone._apply_classroom_open(1,true,id)
	check(int(game.faculty.discipline_records[record_key].count)==1,"rapid repeated reports obey observation cooldown")
	var actions: Array[String]=[str(record.get("decision",{}).get("action",""))]
	for observation in 12:
		if not phone._saved_custody(identity).is_empty():break
		# Advance only the two real observation/action clocks, preserving all
		# evidence counts and warnings. This models separated visible uses.
		phone.classroom_report_at[1]=0.
		game.faculty.discipline_records[record_key].last_action_at=Time.get_ticks_msec()-6001
		phone._apply_classroom_open(1,true,id)
		var decision: Dictionary=game.faculty.discipline_action_for(1,ROOM)
		actions.append(str(decision.get("action","")))
		check(not decision.has("record"),"diagnostic decision does not recursively embed history")
		await process_frame
	var custody: Dictionary=phone._saved_custody(identity)
	check(custody.get("id","")==id and custody.get("teacher","")==activity.teacher,"continued use creates actual inventory custody")
	check(actions.has("put_away") and actions.has("confiscate") and actions.find("put_away")<actions.find("confiscate"),"put-away instruction precedes confiscation")
	var executed: Dictionary=game.faculty.discipline_action_for(1,ROOM).get("execution",{})
	check(executed.get("executed",false) and not executed.get("pending",true),"saved custody completes the host consequence")
	check(phone.handed_phone_id==id and phone._locally_in_custody(id),"local held-phone use is blocked by custody")
	check(profile.data.dorm.smartphones==inventory_before,"custody preserves the owned phone")
	var saved: Variant=Profile._read_profile_file(profile.path)
	check(saved is Dictionary and saved.get("dorm",{}).get("teacher_phone_custody",{}).get("id","")==id,"custody is persisted through the existing profile save")
	phone.release_class_handoffs(ROOM,str(activity.id))
	check(phone._saved_custody(identity).get("id","")==id,"custody survives class end until requested return")
	var returned: String=phone.teacher_handoff(1,ROOM,str(activity.teacher),true)
	check(returned.contains("phone is back") and phone._saved_custody(identity).is_empty() and phone.handed_phone_id.is_empty(),"existing reclaim action returns the same phone")
	check(profile.data.dorm.smartphones==inventory_before,"return neither loses nor duplicates inventory")
	check(game.school.papers[paper_id]==paper_before and game.school.archive==archive_before and not activity.students[identity].done,"discipline and return preserve answers, enrollment, and marks")
	print("PHONE_DISCIPLINE_ACTIONS ",actions)
	await finish(game)
