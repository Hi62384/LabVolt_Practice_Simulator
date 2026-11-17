extends SceneTree
const RETURNING_ID := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var game: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func until(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.05).timeout
	var in_room: Dictionary={}
	if game.multiplayer.is_server():
		for peer in game.session.roster:in_room[peer]=game.lecture_classes._inside(int(peer),"ety155_lecture")
	print("ROOM MIXED STATE ",label," roster=",game.session.roster.keys()," identities=",game.school.identities," lecture=",game.lecture_classes.public_classes.get("ety155_lecture",{}).get("phase","")," signed=",game.lecture_classes.public_classes.get("ety155_lecture",{}).get("signed",false)," inside=",in_room," poses=",game.session.poses)
	push_error("ROOM MIXED TIMEOUT "+label);quit(1);return false
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var role: String=str(OS.get_cmdline_user_args()[0])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	deadline=Time.get_ticks_msec()+90000
	var classes=game.lecture_classes
	var school=game.school
	var room: String="ety155_lecture"
	var desk: Vector3=classes.signs[room].desk
	if role=="host":
		var prior: Dictionary={"id":"prior-lecture","assessment_id":"prior-lecture","profile":RETURNING_ID,"course_id":"ETY155","kind":"lecture","week":1,"score":80.0,"course_attempt":1,"gradebook_assessment_id":"lecture:1","lesson":false,"time":"2026-11-13T12:00:00"}
		school.archive[RETURNING_ID]={prior.id:prior}
		if game.session.host_game("Host",26370)!=OK:fail("Host failed");return
		game.player.global_position=desk
		print("ROOM_MIXED_HOST_READY")
		if not await until(func():return game.session.roster.size()==3 and school.identities.size()==3 and school.identities.values().has(RETURNING_ID),"three identified peers"):return
		var returning_peer: int=int(school.identities.find_key(RETURNING_ID))
		var new_peer: int=int(school.identities.keys().filter(func(peer):return peer!=1 and peer!=returning_peer)[0])
		var new_id: String=str(school.identities[new_peer])
		var error: String=classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})
		if error!="":fail(error);return
		var activity: Dictionary=classes.classes[room]
		activity.phase="lesson";activity.deadline=classes._now()+180.0;classes._publish()
		if not await until(func():return activity.students.has(RETURNING_ID) and activity.students.has(new_id),"both students signed"):return
		if not activity.students[RETURNING_ID].replay or activity.students[new_id].replay:fail("Mixed replay classification failed");return
		if not classes._begin_assignment(room,activity):fail("Assignment did not start");return
		classes._publish()
		var replay: Dictionary=school.papers[int(activity.students[RETURNING_ID].paper)]
		var first: Dictionary=school.papers[int(activity.students[new_id].paper)]
		if not replay.replay or first.replay:fail("Paper replay flags differ from enrollment");return
		for i in first.project.get("questions",[]).size():first.answers[str(i)]=first.project.questions[i].answer
		school._mark(replay,false);school._mark(first,false)
		if school.archive[RETURNING_ID].size()!=1 or school.archive.get(new_id,{}).values().filter(func(row):return row.has("score") and row.get("gradebook_assessment_id","")=="lecture:1").size()!=1:fail("Mixed official credit was not isolated");return
		school._mark(replay,false);school._mark(first,false)
		if school.archive[RETURNING_ID].size()!=1 or school.archive[new_id].size()!=1:fail("Duplicate mark changed credits");return
		classes.classes.erase(room);classes._publish()
		game.faculty.current.dc_lab="mr_phillips"
		var lab_error: String=classes._start("dc_lab",{"kind":"lab","course_id":"ETY155","week":1,"difficulty":0})
		if lab_error!="":fail(lab_error);return
		var lab: Dictionary=classes.classes.dc_lab
		lab.phase="lesson";lab.deadline=classes._now()+180.0;classes._publish()
		if not await until(func():return lab.students.has(RETURNING_ID),"returning student signed lab"):return
		if lab.students[RETURNING_ID].replay:fail("Lecture credit consumed lab slot");return
		print("ROOM_MIXED_HOST PASS")
		await create_timer(2.0).timeout
	else:
		if role=="client_a":school.local_identity=RETURNING_ID
		game.session.message_received.connect(func(message):print("ROOM_MIXED_NOTICE_",role," ",message))
		if game.session.join_game("127.0.0.1",role,26370)!=OK:fail("Join failed");return
		if not await until(func():
			game.player.global_position=desk;game.session.send_pose({"position":desk})
			return classes.public_classes.get(room,{}).get("phase","")=="lesson"
		,"lecture visible"):return
		await create_timer(.5).timeout
		classes._send("sign",room,{})
		for retry in 5:
			await create_timer(.5).timeout
			print("ROOM_MIXED_SIGN_",role," ",retry," ",game.ui.log_label.text)
			if classes.public_classes.get(room,{}).get("signed",false):break
			game.player.global_position=desk;game.session.send_pose({"position":desk})
			classes._send("sign",room,{})
		if not await until(func():return classes.public_classes.get(room,{}).get("signed",false),"attendance"):return
		if not await until(func():return classes.public_classes.get(room,{}).get("phase","")=="assignment","official assessment"):return
		if role=="client_a":
			if not await until(func():return school.gradebook.values().filter(func(row):return row.get("gradebook_assessment_id","")=="lecture:1").size()==1,"returning credit"):return
			if float(school.gradebook.values()[0].score)!=80.0:fail("Replay replaced returning grade");return
		else:
			if not await until(func():return school.gradebook.values().filter(func(row):return row.get("gradebook_assessment_id","")=="lecture:1" and row.has("score")).size()==1,"first credit"):return
			if float(school.gradebook.values()[0].score)<99.0:fail("First grade incorrect");return
		if not await until(func():return classes.public_classes.get("dc_lab",{}).get("phase","")=="lesson","lab visible"):return
		if role=="client_a":
			var lab_desk: Vector3=classes.signs.dc_lab.desk
			game.player.global_position=lab_desk;game.session.send_pose({"position":lab_desk})
			classes._send("sign","dc_lab",{})
			if not await until(func():return classes.public_classes.get("dc_lab",{}).get("signed",false),"lab attendance"):return
		print("ROOM_MIXED_",role.to_upper()," PASS")
	game.session.leave();await create_timer(.2).timeout
	game.queue_free();await process_frame;quit(0)
