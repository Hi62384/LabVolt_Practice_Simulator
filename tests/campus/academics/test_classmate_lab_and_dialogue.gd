extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(35.).timeout.connect(func():quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	var classes: Node=game.lecture_classes
	var classmates: Node=classes.classroom_students
	var faculty: Node=game.faculty
	var room:="ac_lab"
	game.player.global_position=classes.signs[room].desk
	assert(classes._start(room,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":1})=="")
	var activity: Dictionary=classes.classes[room]
	var now: float=classes._now()
	assert(not activity.classmates.is_empty())
	var member: Dictionary=activity.classmates.values()[0]
	member.arrival=now-10.
	member.position=member.seat
	member.arrived=true
	classes._publish()
	game.player.global_position=member.position+Vector3(.5,0,0)
	classes._publish()
	classmates.render(room,classes.public_classes,.1)
	var model: Node3D=classmates.models.get(activity.id+":"+member.profile.id)
	assert(is_instance_valid(model))
	var target: StaticBody3D
	for child in model.get_children():
		if child.get_meta("role","")=="classroom_student":target=child
	assert(is_instance_valid(target) and faculty.interact(target))
	assert(faculty.conversation_name.text==member.profile.name)
	game.school.identities[1]="0123456789abcdef0123456789abcdef0123456789abcdef"
	faculty.conversation_input.text="What is your hobby?"
	faculty._submit_question()
	assert(member.profile.interest in faculty.conversation_text.text)
	var exchanges: Array=faculty.brain.recall(member.profile.id,game.school.identities[1])
	assert(exchanges.size()==1)
	var previous: String=faculty.conversation_text.text
	faculty._classmate_question(1,room,"old_class",member.profile.id,"Thanks")
	assert(faculty.conversation_text.text==previous)
	game.player.global_position=Vector3(13,0,35)
	faculty._classmate_question(1,room,activity.id,member.profile.id,"Thanks")
	assert(faculty.conversation_text.text==previous)
	faculty.close_conversation()
	activity.phase="lesson"
	activity.deadline=now+300.
	var practice: RefCounted=classes.lab_practice
	assert(practice._commands(game.session.labs[0],activity.lab_practice).size()>0,"No trusted AC exercise commands for %s"%activity.lab_practice)
	var saw_wiring:=false
	for step in 180:
		practice.step(activity,now+step)
		if not practice.work.is_empty():
			var station: RefCounted=game.session.labs[practice.work.bench]
			if not station.completed().is_empty():saw_wiring=true
		if activity.has("lab_practice_result") or activity.has("lab_practice_error"):break
	assert(not activity.has("lab_practice_error"),str(activity.get("lab_practice_error","")))
	assert(saw_wiring and float(activity.get("lab_practice_result",{}).get("v",0))>1.,"result=%s plan=%s stations=%s"%[
		activity.get("lab_practice_result",{}),not activity.lab_practice.is_empty(),game.session.labs.map(func(station):
			return [station.mode,station.positions.get("power","missing"),station.powered,station.external_connections,station.protective_earth_profile])])
	assert(practice.work.is_empty())
	for station in game.session.labs:
		assert(not station.powered and station.cables.is_empty())
	classes.classes.erase(room)
	assert(classes._start("dc_lab",{"kind":"lab","course_id":"ETY155","week":2,"difficulty":1})=="")
	var dc: Dictionary=classes.classes.dc_lab
	dc.phase="lesson"
	dc.deadline=now+300.
	var worker: Dictionary=dc.classmates.values()[0]
	worker.arrival=now-1.
	worker.arrived=true
	worker.position=worker.seat
	for step in 20:
		practice.step(dc,now+step)
		if not practice.work.is_empty():
			game.dc_lab.benches[practice.work.bench].step()
	assert(not dc.has("lab_practice_error"),str(dc.get("lab_practice_error","")))
	var dc_result: Dictionary=dc.get("lab_practice_result",{})
	assert(absf(float(dc_result.get("v",0.))-5.)<.05,str(dc_result))
	assert(practice.work.is_empty())
	for bench in game.dc_lab.benches:
		assert(not bench.master and bench.wires.is_empty())
	dc.phase="assignment"
	classmates.begin_assessment(dc,now)
	classmates.step(dc,now+30.,.2)
	assert(worker.action=="handed in work" and classmates.records.has_section_key(worker.profile.id,"ETY155.last_score"))
	assert(not game.session.roster.has(-100))
	print("CLASSMATE_CONVERSATION_AND_LIVE_LABS PASS")
	game.queue_free()
	await process_frame
	quit()
