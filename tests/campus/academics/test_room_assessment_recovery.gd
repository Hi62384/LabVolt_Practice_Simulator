extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in range(4):
		await process_frame
	game.front.entered()
	var school: Node = game.school
	var classes: Node = game.lecture_classes
	var room := "ac_lab"
	var identity := "0123456789abcdef0123456789abcdef0123456789abcdef"
	var guest := 99
	var desk: Vector3 = classes.signs[room].desk
	school.identities[guest] = identity
	game.session.roster[guest] = {"name":"Student"}
	game.session.poses[guest] = {"position":desk}
	game.faculty.current[room] = "mr_phillips"
	assert(classes._start(room,{"kind":"lab","course_id":"ELM253","week":2,"difficulty":1}) == "")
	assert(classes._sign(guest,room) == "")
	var activity: Dictionary = classes.classes[room]
	var student: Dictionary = activity.students[identity]
	var obstructed_save := ProjectSettings.globalize_path("user://teacher_records.json.tmp")
	assert(DirAccess.make_dir_absolute(obstructed_save) == OK)
	assert(not classes._begin_assignment(room,activity))
	assert(student.paper == 0 and not student.done and activity.phase == "arrival")
	assert(DirAccess.remove_absolute(obstructed_save) == OK)
	student.project.practice_scope = "ungraded"
	assert(classes._begin_assignment(room,activity))
	assert(student.paper == 0 and not student.done and activity.phase == "assignment")
	var deadline: float = activity.deadline
	student.project.erase("practice_scope")
	student.retry_at = 0.0
	classes._check_students()
	assert(student.paper > 0 and not student.done)
	var paper: Dictionary = school.papers[student.paper]
	paper.answers["0"] = "saved answer"
	game.session.poses[guest].position = Vector3.INF
	classes._check_students()
	assert(not student.done and activity.deadline == deadline)
	game.session.roster.erase(guest)
	game.session.poses.erase(guest)
	school.roster_changed()
	assert(paper.owner == 0 and paper.answers["0"] == "saved answer")
	var returning := 100
	game.session.roster[returning] = {"name":"Student"}
	game.session.poses[returning] = {"position":desk}
	school._identify(returning,identity)
	classes._check_students()
	assert(paper.owner == returning and paper.answers["0"] == "saved answer")
	assert(school.papers.size() == 1 and school.archive[identity].size() == 1)
	assert(not student.done and activity.deadline == deadline)
	_check_background_transition(game)
	game.queue_free()
	await process_frame
	print("PASS assessment persistence, guest identity rebind and background lecture transition")
	quit()

func _check_background_transition(game: Node) -> void:
	var school: Node = game.school
	var classes: Node = game.lecture_classes
	var guard: Node = game.assessment_focus_guard
	var lecture := "ety155_lecture"
	var identity: String = school.local_identity
	assert(not identity.is_empty())
	school.identities[1] = identity
	game.player.global_position = classes.signs[lecture].desk
	assert(classes._start(lecture,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":1}) == "")
	assert(classes._sign(1,lecture) == "")
	var activity: Dictionary = classes.classes[lecture]
	activity.phase = "lesson"
	activity.deadline = classes._now() - 1.0
	guard.set_process(false)
	guard.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	guard.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	guard._process(.1)
	classes._advance()
	assert(activity.phase == "assignment")
	var student: Dictionary = activity.students[identity]
	assert(student.paper > 0)
	var paper: Dictionary = school.papers[student.paper]
	guard.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	guard._process(6.0)
	assert(not guard.reports.has(1) and paper.mark.is_empty() and not student.done)
	guard.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	guard._process(.1)
	classes._advance()
	assert(classes.classes.has(lecture) and classes.classes[lecture].id == activity.id)
	guard.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	guard._process(.1)
	assert(guard.reports.get(1,{}).get("id","") == activity.id)
	guard.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	guard._process(.1)
	assert(not guard.reports.has(1) and paper.mark.is_empty() and not student.done)
