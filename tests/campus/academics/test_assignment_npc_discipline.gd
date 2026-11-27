extends SceneTree
## Actual classroom geometry, instructor perception and NPC prop/custody state
## during an issued assessment. No model or grading result is fabricated.
const ROOM:="ac_lab"
var checks:=0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:failures.append(message);printerr("ASSIGNMENT NPC DISCIPLINE FAIL: "+message)
	return ok

func finish(game: Node) -> void:
	print("ASSIGNMENT_NPC_DISCIPLINE %s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	create_timer(65.).timeout.connect(func():printerr("ASSIGNMENT NPC DISCIPLINE TIMEOUT");quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 2:await process_frame
	game.player.set_physics_process(false)
	game.faculty.set_process(false);game.lecture_classes.set_process(false);game.school.set_process(false)
	game.host_openai.enabled=false
	game.client_preferences.values.teacher_speech=false;game.client_preferences.values.teacher_subtitles=false
	var faculty: Node=game.faculty
	var classes: Node=game.lecture_classes
	var students: Node=classes.classroom_students
	game.player.global_position=classes.signs[ROOM].desk
	if not check(classes._start(ROOM,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":0,"teacher_override":"mr_stone"})=="","Actual classroom starts with a strict eligible instructor"):
		await finish(game);return
	var activity: Dictionary=classes.classes[ROOM]
	check(classes._sign(1,ROOM)=="","The real human profile signs into the class")
	activity.phase="lesson";activity.deadline=classes._now()+300.
	if not check(classes._begin_assignment(ROOM,activity),"An actual assessment is issued"):
		await finish(game);return
	faculty.current[ROOM]=str(activity.teacher)
	faculty._show_lab(ROOM,str(activity.teacher))
	var teacher: Node3D=faculty._model_for_room(ROOM,str(activity.teacher))
	if not check(is_instance_valid(teacher),"The actual instructor model exists for visibility tests"):
		await finish(game);return
	var now: float=classes._now()
	var origin: Vector3=faculty._teacher_position(ROOM)
	var point: Vector3=origin+teacher.global_basis.z.normalized()*2.
	if not check(game.campus.registry.locate(point)==ROOM,"Observed phone is physically inside the classroom"):
		await finish(game);return
	var member: Dictionary=activity.classmates.values()[0]
	var id:=str(member.profile.id)
	activity.classmates={id:member}
	member.arrival=now-1.;member.arrived=true;member.position=point;member.seat=point
	member.seated=true;member.walking=false;member.action="using phone";member.turns=1
	var due:=float(member.academic_due)
	var human_before:=JSON.stringify(activity.students)
	var project_before:=JSON.stringify(activity.classmate_assessment)
	var papers_before:=JSON.stringify(game.school.papers)
	var marks_before:=JSON.stringify(game.school.archive)
	students.render(ROOM,{ROOM:{"classmates":students.snapshot(activity,now)}},.3)
	var model: Node3D=students.models.get(str(activity.id)+":"+id)
	check(is_instance_valid(model) and model.get_node("Body/ArmR/StudentPhone").visible,"The offending action has an actual visible phone prop")
	await physics_frame
	var rotation:=teacher.rotation.y
	teacher.rotation.y=rotation+PI
	students._observe_student_behavior(ROOM,activity,member,now)
	check(activity.get("discipline_records",{}).get(id,{}).is_empty(),"A teacher looking away cannot observe the phone")
	teacher.rotation.y=rotation
	students._observe_student_behavior(ROOM,activity,member,now)
	var record: Dictionary=activity.get("discipline_records",{}).get(id,{})
	if not check(int(record.get("count",0))==1,"Actual visibility admits one assignment phone incident"):
		print("ASSIGNMENT NPC VISIBILITY origin=",origin," forward=",teacher.global_basis.z," student=",point)
		await finish(game);return
	check(member.action=="listening" and float(member.get("items_away_until",0.))>now,"Put-away instruction actually changes NPC action and held-item availability")
	check(member.last_discipline.get("executed",false) and not member.last_discipline.get("pending",true),"Immediate prop consequence is reported as completed")
	check(faculty.brain.recall(str(activity.teacher),id).size()==1,"Perception and spoken warning share one directional memory event")
	students.render(ROOM,{ROOM:{"classmates":students.snapshot(activity,now)}},.3)
	check(not model.get_node("Body/ArmR/StudentPhone").visible,"Put-away execution removes the actual held phone from view")
	var actions: Array[String]=[str(member.last_discipline.action)]
	member.action="using phone"
	students._observe_student_behavior(ROOM,activity,member,now)
	check(int(activity.discipline_records[id].count)==1,"The same perceived behavior cannot add another strike")
	for incident in 8:
		if member.get("phone_in_custody",false):break
		# Separate actual visible uses after the previous instruction expires;
		# only the real action clock is advanced, never the warning/event counts.
		activity.discipline_records[id].last_action_at=Time.get_ticks_msec()-6001
		member.turns+=1;member.action="using phone"
		students.render(ROOM,{ROOM:{"classmates":students.snapshot(activity,now+130.*float(incident+1))}},.3)
		students._observe_student_behavior(ROOM,activity,member,now+130.*float(incident+1))
		actions.append(str(member.last_discipline.action))
	check(actions.has("put_away") and actions.has("confiscate") and actions.find("put_away")<actions.find("confiscate"),"Repeated perceived use escalates from instruction to existing NPC custody")
	check(member.get("phone_in_custody",false) and member.get("item_custody",{}).get("held_by","")==activity.teacher and member.item_custody.get("class_id","")==activity.id,"Confiscation stores actual teacher/class custody state")
	check(not member.get("removed_from_class",false) and not member.has("walk") and is_equal_approx(float(member.academic_due),due),"Phone consequences preserve room attendance and the original academic clock")
	check(not students.apply_discipline(ROOM,activity,id,{"action":"remove"},now),"Assessment removal remains refused")
	check(faculty.brain.recall(str(activity.teacher),id).size()==int(activity.discipline_records[id].count),"Every distinct incident is remembered exactly once")

	# A pose alone is not audible evidence. A displayed utterance can be heard.
	var quiet_profile: Dictionary=students.population.profile_for("campus_student_00" if id!="campus_student_00" else "campus_student_01")
	var quiet:={"profile":quiet_profile,"position":point+Vector3(.6,0,0),"seat":point+Vector3(.6,0,0),
		"arrived":true,"arrival":now-1.,"seated":true,"walking":false,"action":"whispering","turns":1,
		"next":now+1000.,"academic_due":now+1000.,"behavior_started":now}
	activity.classmates[quiet.profile.id]=quiet
	students._observe_student_behavior(ROOM,activity,quiet,now)
	check(activity.discipline_records.get(quiet.profile.id,{}).is_empty(),"A silent whisper pose cannot manufacture an audible incident")
	quiet.line="We can talk after class."
	students.render(ROOM,{ROOM:{"classmates":students.snapshot(activity,now)}},.3)
	students._observe_student_behavior(ROOM,activity,quiet,now)
	check(int(activity.discipline_records.get(quiet.profile.id,{}).get("count",0))==1,"Actual brief speech can be perceived during an assessment")
	check(not quiet.get("removed_from_class",false),"Audible assignment behavior does not remove a student")
	check(JSON.stringify(activity.students)==human_before and JSON.stringify(activity.classmate_assessment)==project_before and JSON.stringify(game.school.papers)==papers_before and JSON.stringify(game.school.archive)==marks_before,"Discipline changes no human answers, issued project, submission or official mark")
	member.next=now+1000.
	students.step(activity,now+400.,.1,ROOM)
	check(member.get("submitted",false),"A held-away phone and delayed presentation do not prevent the student's own scheduled submission")
	check(JSON.stringify(activity.students)==human_before and JSON.stringify(activity.classmate_assessment)==project_before and JSON.stringify(game.school.papers)==papers_before and JSON.stringify(game.school.archive)==marks_before,"Own NPC completion still leaves all official human work unchanged")
	students.render(ROOM,{ROOM:{"classmates":students.snapshot(activity,now+400.)}},.3)
	check(not model.get_node("Body/ArmR/StudentPhone").visible,"The confiscated phone remains hidden after academic completion")
	print("ASSIGNMENT_NPC_DISCIPLINE_ACTIONS ",actions)
	await finish(game)
