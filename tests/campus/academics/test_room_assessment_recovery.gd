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
	game.queue_free()
	await process_frame
	print("PASS assessment persistence retry, paper retry and guest identity rebind")
	quit()
