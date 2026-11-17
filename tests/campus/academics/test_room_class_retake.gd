extends SceneTree
const Adapter=preload("res://scripts/campus/academics/course_progression_adapter.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	var school=game.school
	var classes=game.lecture_classes
	var identity="0123456789abcdef0123456789abcdef0123456789abcdef"
	school.identities[1]=identity;game.session.roster[1]={"name":"Student"}
	var course="ETY155"
	var records: Dictionary={}
	for kind in ["lecture","lab"]:
		for week in range(1,school.course_bridge.weeks(course,kind).size()+1):
			var id="%s:%d"%[kind,week]
			var key="old-"+id
			records[key]={"id":key,"profile":identity,"course_id":course,"kind":kind,"week":week,"gradebook_assessment_id":id,"course_attempt":1,"score":20.0,"time":"2026-01-%02dT12:00:00"%week}
	school.archive[identity]=records.duplicate(true)
	var prior: Dictionary=Adapter.summary(school.archive[identity],identity,course,school.course_bridge)
	assert(prior.status=="failed" and is_equal_approx(float(prior.final_mark),20.0))
	var room="ety155_lecture"
	assert(classes._start(room,{"kind":"lecture","course_id":course,"week":1,"difficulty":0})=="")
	game.player.global_position=classes.signs[room].desk
	assert(classes._sign(1,room)=="")
	var activity: Dictionary=classes.classes[room]
	assert(not activity.students[identity].replay)
	assert(classes._begin_assignment(room,activity))
	var paper: Dictionary=school.papers[activity.students[identity].paper]
	assert(not paper.replay and int(paper.project.get("course_attempt",0))==2)
	for i in paper.project.get("questions",[]).size():
		paper.answers[str(i)]=paper.project.questions[i].answer
	school._mark(paper,false)
	var retake: Dictionary=Adapter.summary(school.archive[identity],identity,course,school.course_bridge)
	assert(retake.final_mark==prior.final_mark)
	assert(retake.open_attempts.size()==1 and int(retake.open_attempts[0].number)==2)
	assert(retake.open_attempts[0].records.has("lecture:1"))
	assert(float(retake.open_attempts[0].records["lecture:1"].score)>20.0)
	assert(school._is_replay(identity,paper.project))
	var extra: Dictionary=paper.project.duplicate(true);extra.official_curriculum_id="midterm-a"
	var extra_record: Dictionary=records["old-lecture:1"].duplicate(true);extra_record.id="old-extra";extra_record.gradebook_assessment_id="midterm-a"
	school.archive[identity]["old-extra"]=extra_record
	assert(school._is_replay(identity,extra))
	print("ROOM_CLASS_RETAKE PASS")
	game.queue_free();await process_frame;quit(0)
