extends SceneTree

var game: Node
var deadline: int
const ROOM := "ety155_lecture"

func _initialize() -> void: call_deferred("run")

func until(check: Callable, label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call(): return true
		await create_timer(.05).timeout
	push_error("ROOM REPLAY NETWORK TIMEOUT "+label)
	quit(1)
	return false

func run() -> void:
	var host: bool=OS.get_cmdline_user_args()[0]=="host"
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4: await process_frame
	game.front.entered()
	deadline=Time.get_ticks_msec()+90000
	var classes=game.lecture_classes
	var school=game.school
	var desk: Vector3=classes.signs[ROOM].desk
	if host:
		if game.session.host_game("Host",26369)!=OK: quit(1);return
		print("ROOM_REPLAY_HOST_READY")
		if not await until(func():return game.session.roster.size()==2 and school.identities.size()==2,"client identity"):return
		var peer: int=game.session.roster.keys().filter(func(id):return id!=1)[0]
		var identity: String=str(school.identities[peer])
		if not await until(func():return classes._inside(peer,ROOM) and classes._position(peer).distance_to(desk)<.6,"client at desk"):return
		for attempt in 2:
			var start_error: String=classes._start(ROOM,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})
			if not start_error.is_empty():push_error(start_error);quit(1);return
			var activity: Dictionary=classes.classes[ROOM]
			activity.phase="lesson"
			activity.deadline=classes._now()+180.0
			classes._publish()
			if not await until(func():return activity.students.has(identity),"attendance %d"%attempt):return
			if bool(activity.students[identity].get("replay",false))!=(attempt==1):push_error("Wrong replay classification");quit(1);return
			if not classes._begin_assignment(ROOM,activity):push_error("Assignment start failed");quit(1);return
			classes._publish()
			var paper: Dictionary=school.papers[int(activity.students[identity].paper)]
			if bool(paper.get("replay",false))!=(attempt==1):push_error("Wrong paper replay flag");quit(1);return
			if attempt==0:
				for i in paper.project.get("questions",[]).size():paper.answers[str(i)]=paper.project.questions[i].answer
			school._mark(paper,false)
			classes.paper_submitted(paper)
			var records: Array=school.archive.get(identity,{}).values().filter(func(record):return record.get("gradebook_assessment_id","")=="lecture:1" and record.has("score"))
			if records.size()!=1:push_error("Duplicate or missing official credit: "+str(records));quit(1);return
			var saved_record: Dictionary=records[0].duplicate(true)
			school._mark(paper,false)
			var duplicate_records: Array=school.archive.get(identity,{}).values().filter(func(record):return record.get("gradebook_assessment_id","")=="lecture:1" and record.has("score"))
			if duplicate_records.size()!=1 or duplicate_records[0]!=saved_record:push_error("Duplicate marking changed official credit");quit(1);return
			var archive_file:=FileAccess.open("user://teacher_records.json",FileAccess.READ)
			if archive_file==null:push_error("Official archive was not persisted");quit(1);return
			var persisted: Variant=JSON.parse_string(archive_file.get_as_text())
			if not persisted is Dictionary or not persisted.get(identity,{}).has(str(saved_record.id)) or float(persisted[identity][str(saved_record.id)].get("score",-1))!=float(saved_record.score) or str(persisted[identity][str(saved_record.id)].get("gradebook_assessment_id",""))!="lecture:1":
				push_error("Persisted official result differs from live archive");quit(1);return
			if attempt==1 and not str(paper.mark.get("reason","")).begins_with("Replay feedback"):push_error("Replay did not give feedback");quit(1);return
			if attempt==1 and not float(records[0].score)>float(paper.mark.score):push_error("Replay score did not differ from stored mark");quit(1);return
			if attempt==0:
				if not await until(func():return activity.students[identity].done,"first grade settled"):return
				await create_timer(.8).timeout
			else:
				await create_timer(2).timeout
			classes.classes.erase(ROOM)
			classes._publish()
			if attempt==0:
				if not await until(func():return not game.session.roster.has(peer),"first peer disconnected"):return
				if not await until(func():return game.session.roster.size()==2 and school.identities.values().has(identity),"same student rejoined"):return
				peer=int(school.identities.find_key(identity))
				if not await until(func():return classes._inside(peer,ROOM),"rejoined student at desk"):return
			else:await create_timer(.5).timeout
		var next_error: String=classes._start(ROOM,{"kind":"lecture","course_id":"ETY155","week":2,"difficulty":0})
		if not next_error.is_empty():push_error(next_error);quit(1);return
		var departed: Dictionary=classes.classes[ROOM]
		departed.phase="lesson";departed.deadline=classes._now()+180.0;classes._publish()
		if not await until(func():return departed.students.has(identity),"departure class attendance"):return
		if not classes._begin_assignment(ROOM,departed):push_error("Departure assignment failed");quit(1);return
		classes._publish()
		if not await until(func():return not game.session.roster.has(peer),"assessment disconnect"):return
		if not await until(func():return departed.students[identity].done,"departed assessment settled"):return
		var lost: Array=school.archive.get(identity,{}).values().filter(func(record):return record.get("gradebook_assessment_id","")=="lecture:2" and record.has("score"))
		if lost.size()!=1 or float(lost[0].score)!=0.0:push_error("Departure did not create one zero-score result");quit(1);return
		if not await until(func():return game.session.roster.size()==2 and school.identities.values().has(identity),"departed student rejoined"):return
		await create_timer(.8).timeout
		var after_rejoin: Array=school.archive.get(identity,{}).values().filter(func(record):return record.get("gradebook_assessment_id","")=="lecture:2" and record.has("score"))
		if after_rejoin.size()!=1 or after_rejoin[0]!=lost[0]:push_error("Rejoin changed departure grade");quit(1);return
		print("ROOM_REPLAY_HOST PASS")
		await create_timer(3).timeout
	else:
		var join_error: Error=game.session.join_game("127.0.0.1","Student",26369)
		if join_error!=OK:push_error("Join failed: "+str(join_error));quit(1);return
		print("ROOM_REPLAY_CLIENT_JOINED")
		var first_credit: String=""
		var first_score: float=-1.0
		for attempt in 2:
			if not await until(func():
				game.player.global_position=desk
				game.session.send_pose({"position":desk})
				return classes.public_classes.get(ROOM,{}).get("phase","")=="lesson" and not classes.public_classes[ROOM].get("signed",false)
			,"lesson %d"%attempt):return
			classes._send("sign",ROOM,{})
			print("ROOM_REPLAY_CLIENT_SIGNED ",attempt)
			if not await until(func():return classes.public_classes.get(ROOM,{}).get("phase","")=="assignment","assignment %d"%attempt):return
			if not await until(func():return school.gradebook.values().any(func(record):return record.get("gradebook_assessment_id","")=="lecture:1"),"first grade replicated"):return
			var credits: Array=school.gradebook.values().filter(func(record):return record.get("gradebook_assessment_id","")=="lecture:1")
			if credits.size()!=1:push_error("Client double credit");quit(1);return
			var grade_file:=FileAccess.open("user://student_grades.json",FileAccess.READ)
			if grade_file==null:push_error("Student gradebook was not persisted");quit(1);return
			var saved_grades: Variant=JSON.parse_string(grade_file.get_as_text())
			if not saved_grades is Dictionary or not saved_grades.has(str(credits[0].id)) or float(saved_grades[str(credits[0].id)].get("score",-1))!=float(credits[0].score) or str(saved_grades[str(credits[0].id)].get("gradebook_assessment_id",""))!="lecture:1":push_error("Saved student grade differs from live gradebook");quit(1);return
			if attempt==0:first_credit=str(credits[0].id);first_score=float(credits[0].score)
			elif str(credits[0].id)!=first_credit or float(credits[0].score)!=first_score:push_error("Client credit changed on replay");quit(1);return
			if attempt==0:
				if not await until(func():return not classes.public_classes.has(ROOM),"first class cleared"):return
				var old_peer: int=game.multiplayer.get_unique_id()
				game.session.leave()
				await create_timer(2.0).timeout
				if game.session.join_game("127.0.0.1","Student",26369)!=OK:push_error("Assessment rejoin failed");quit(1);return
				if not await until(func():
					game.player.global_position=desk
					game.session.send_pose({"position":desk})
					return game.session.roster.size()==2 and game.multiplayer.get_unique_id()!=old_peer and school.gradebook.has(first_credit)
				,"rejoined gradebook and new peer"):return
		if not await until(func():
			game.player.global_position=desk;game.session.send_pose({"position":desk})
			return classes.public_classes.get(ROOM,{}).get("phase","")=="lesson" and not classes.public_classes[ROOM].get("signed",false)
		,"departure class visible"):return
		classes._send("sign",ROOM,{})
		if not await until(func():return classes.public_classes.get(ROOM,{}).get("phase","")=="assignment","departure assignment visible"):return
		game.session.leave()
		await create_timer(2.0).timeout
		if game.session.join_game("127.0.0.1","Student",26369)!=OK:push_error("Departure rejoin failed");quit(1);return
		if not await until(func():return school.gradebook.values().any(func(record):return record.get("gradebook_assessment_id","")=="lecture:2" and float(record.get("score",-1))==0.0),"departure grade restored"):return
		var second_credits: Array=school.gradebook.values().filter(func(record):return record.get("gradebook_assessment_id","")=="lecture:2")
		if second_credits.size()!=1:push_error("Departure produced duplicate credit");quit(1);return
		print("ROOM_REPLAY_CLIENT PASS")
	game.session.leave()
	await create_timer(.2).timeout
	game.queue_free()
	await process_frame
	quit(0)
