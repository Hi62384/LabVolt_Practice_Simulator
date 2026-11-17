extends SceneTree
const Progression=preload("res://scripts/campus/academics/course_progression_adapter.gd")

func _initialize() -> void:call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	var classes=game.lecture_classes
	var school=game.school
	var identity: String=school.local_identity
	school.identities[1]=identity
	game.session.roster[1]={"name":"Student"}
	var previous: Dictionary={}
	for kind in ["lecture","lab"]:
		for week in school.course_bridge.weeks("ETY155",kind):
			var slot: String="%s:%d"%[kind,int(week.week)]
			var id: String="failed-%s"%slot
			previous[id]={"id":id,"assessment_id":id,"profile":identity,"course_id":"ETY155","kind":kind,"week":int(week.week),"score":0.0,"course_attempt":1,"gradebook_assessment_id":slot,"lesson":false,"time":"2026-11-13T12:00:00"}
	school.archive[identity]=previous
	var before: Dictionary=Progression.summary(school.archive[identity],identity,"ETY155",school.course_bridge)
	if before.status!="failed" or before.completed_attempts.size()!=1:fail("Fixture did not form a complete failed course attempt: "+str(before.status));return
	var room: String="ety155_lecture"
	if classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})!="":fail("Retake class could not start");return
	game.player.global_position=classes.signs[room].desk
	if classes._sign(1,room)!="":fail("Retake attendance rejected");return
	var activity: Dictionary=classes.classes[room]
	if activity.students[identity].replay:fail("Failed complete attempt was treated as feedback-only replay");return
	if not classes._begin_assignment(room,activity):fail("Retake assignment failed to start");return
	var paper: Dictionary=school.papers[int(activity.students[identity].paper)]
	if paper.replay or int(paper.project.course_attempt)!=2:fail("Retake paper lacks distinct graded attempt 2");return
	for i in paper.project.get("questions",[]).size():paper.answers[str(i)]=paper.project.questions[i].answer
	school._mark(paper,false)
	if paper.mark.is_empty():fail("Retake was not marked");return
	var new_records: Array=school.archive[identity].values().filter(func(row):return int(row.get("course_attempt",0))==2 and row.get("gradebook_assessment_id","")=="lecture:1" and row.has("score"))
	if new_records.size()!=1 or float(new_records[0].score)<99.0 or school.archive[identity].size()!=previous.size()+1:fail("Retake did not add exactly one distinct grade");return
	print("ROOM_FAILED_RETAKE PASS")
	game.queue_free()
	await process_frame
	quit(0)
