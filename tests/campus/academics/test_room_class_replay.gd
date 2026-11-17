extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4: await process_frame
	game.front.entered()
	var classes=game.lecture_classes
	var school=game.school
	var identity="0123456789abcdef0123456789abcdef0123456789abcdef"
	school.identities[1]=identity
	game.session.roster[1]={"name":"Student"}
	var room="ety155_lecture"
	assert(classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})=="")
	game.player.global_position=classes.signs[room].desk
	assert(classes._sign(1,room)=="")
	var first: Dictionary=classes.classes[room]
	assert(not first.students[identity].replay)
	assert(classes._begin_assignment(room,first))
	var first_paper: Dictionary=school.papers[first.students[identity].paper]
	for i in first_paper.project.get("questions",[]).size():first_paper.answers[str(i)]=first_paper.project.questions[i].answer
	school._mark(first_paper,false)
	var first_record: Dictionary=school.archive[identity].values().filter(func(record: Dictionary):return record.get("assessment_id","")==first.id)[0].duplicate(true)
	assert(not first_record.has("pending_assessment_version"))
	var first_summary: Dictionary=preload("res://scripts/campus/academics/course_progression_adapter.gd").summary(school.archive[identity],identity,"ETY155",school.course_bridge)
	classes.classes.erase(room)
	school.papers.clear()
	assert(classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})=="")
	assert(classes._sign(1,room)=="")
	var replay: Dictionary=classes.classes[room]
	assert(replay.students[identity].replay)
	assert(classes._begin_assignment(room,replay))
	assert(school.archive[identity].values().filter(func(record: Dictionary):return record.get("assessment_id","")==replay.id).is_empty())
	var paper: Dictionary=school.papers[replay.students[identity].paper]
	assert(paper.replay)
	school._mark(paper,false)
	assert(paper.mark.reason.begins_with("Replay feedback"))
	assert(float(first_record.score)>float(paper.mark.score))
	assert(school.archive[identity].values().filter(func(record: Dictionary):return record.get("assessment_id","")==replay.id).is_empty())
	assert(school.archive[identity].values().any(func(record: Dictionary):return record.get("assessment_id","")==first.id and record.get("score",-1)==first_record.score))
	var replay_summary: Dictionary=preload("res://scripts/campus/academics/course_progression_adapter.gd").summary(school.archive[identity],identity,"ETY155",school.course_bridge)
	assert(replay_summary.current_attempt.earned_to_date==first_summary.current_attempt.earned_to_date)
	classes.classes.erase(room)
	school.papers.clear()
	assert(classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})=="")
	assert(classes._sign(1,room)=="")
	var missing: Dictionary=classes.classes[room]
	assert(missing.students[identity].replay)
	assert(classes._begin_assignment(room,missing))
	school.papers.erase(int(missing.students[identity].paper))
	classes._settle(missing,identity,false,"Paper was lost during replay.")
	assert(missing.students[identity].done)
	assert(school.archive[identity].values().filter(func(record: Dictionary):return record.get("assessment_id","")==missing.id).is_empty())
	print("ROOM_CLASS_REPLAY PASS")
	game.queue_free()
	await process_frame
	quit(0)
