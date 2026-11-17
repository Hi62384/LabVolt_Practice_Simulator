extends SceneTree

func _initialize() -> void:call_deferred("run")
func fail(message: String) -> void:push_error(message);quit(1)

func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	var classes=game.lecture_classes
	var school=game.school
	var host: String=school.local_identity
	var guest: String="0123456789abcdef0123456789abcdef0123456789abcdef"
	school.identities[1]=host;school.identities[2]=guest
	game.session.roster[1]={"name":"Returning"};game.session.roster[2]={"name":"First-time"}
	var room: String="ety155_lecture"
	var desk: Vector3=classes.signs[room].desk
	game.player.global_position=desk;game.session.poses[2]={"position":desk}
	var prior: Dictionary={"id":"previous-lecture","assessment_id":"previous-lecture","profile":host,"course_id":"ETY155","kind":"lecture","week":1,"score":80.0,"course_attempt":1,"gradebook_assessment_id":"lecture:1","lesson":false,"time":"2026-11-13T12:00:00"}
	school.archive[host]={prior.id:prior.duplicate(true)}
	if classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})!="":fail("Mixed-progress class did not start");return
	if classes._sign(1,room)!="" or classes._sign(2,room)!="":fail("Mixed-progress enrollment failed");return
	var activity: Dictionary=classes.classes[room]
	if not activity.students[host].replay or activity.students[guest].replay:fail("Mixed-progress students received same replay status");return
	if not classes._begin_assignment(room,activity):fail("Mixed-progress assignment failed");return
	var replay: Dictionary=school.papers[int(activity.students[host].paper)]
	var first: Dictionary=school.papers[int(activity.students[guest].paper)]
	if not replay.replay or first.replay:fail("Mixed-progress paper flags differ from enrollment");return
	for i in first.project.get("questions",[]).size():first.answers[str(i)]=first.project.questions[i].answer
	school._mark(replay,false);school._mark(first,false)
	if not str(replay.mark.get("reason","")).begins_with("Replay feedback") or school.archive[host].size()!=1:fail("Returning student received duplicate official credit");return
	if school.archive.get(guest,{}).values().filter(func(row):return row.has("score") and row.get("gradebook_assessment_id","")=="lecture:1").size()!=1:fail("First-time student missed lecture credit");return
	classes.classes.erase(room);school.papers.clear()
	var lab_room: String="dc_lab"
	game.faculty.current[lab_room]="mr_phillips"
	game.player.global_position=classes.signs[lab_room].desk
	var lab_error: String=classes._start(lab_room,{"kind":"lab","course_id":"ETY155","week":1,"difficulty":0})
	if lab_error!="":fail("Separate lab class did not start: "+lab_error);return
	if classes._sign(1,lab_room)!="":fail("Lab attendance failed");return
	if classes.classes[lab_room].students[host].replay:fail("Lecture credit incorrectly consumed lab slot");return
	print("ROOM_MIXED_PROGRESS PASS")
	game.queue_free();await process_frame;quit(0)
