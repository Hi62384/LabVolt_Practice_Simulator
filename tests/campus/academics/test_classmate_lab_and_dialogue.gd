extends SceneTree
const Visuals=preload("res://scripts/campus/academics/classroom_visuals.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Breadboard=preload("res://scripts/breadboard_model.gd")

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
	var original_facing:=model.rotation.y
	classmates.render(room,classes.public_classes,.2)
	assert(absf(angle_difference(original_facing,model.rotation.y))>.1)
	classmates.dialogue_focus.clear()
	classmates.render(room,classes.public_classes,1.)
	assert(absf(angle_difference(model.rotation.y,PI))<.01)
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
	for week in range(1,9):
		classes.classes.erase("dc_lab")
		assert(classes._start("dc_lab",{"kind":"lab","course_id":"DGS266","week":week,"difficulty":1})=="")
		var digital: Dictionary=classes.classes.dc_lab
		digital.phase="lesson"
		digital.deadline=now+300.
		var novice: Dictionary=digital.classmates.values()[0]
		novice.arrival=now-1.
		novice.arrived=true
		novice.position=novice.seat
		var saw_live_scope:=false
		if week==1:
			var scope_scene:={"version":1,"title":"Demonstration scope","duration":10.,
				"parameters":{"bench_hz":[10.,0.,1000.],"bench_scope_vpp":[1.,0.,20.]},
				"objects":[{"type":"text","id":"readout","x":35,"y":150,"width":400,"text":"Scope: {bench_hz} Hz"},
					{"type":"graph","id":"probe","x":35,"y":180,"width":750,"height":280,"x_min":0.,"x_max":90.,
						"y_min":-1.,"y_max":6.,"data_series":"bench_scope_trace"}]}
			assert(Visuals.apply(digital,{"op":"create","scene":scope_scene},now))
		for tick in 180:
			practice.step(digital,now+tick)
			if not practice.work.is_empty():
				var station: RefCounted=game.dc_lab.benches[practice.work.bench]
				if station.generator.enabled:
					for sample in 120:station.step()
				elif station.master:
					for sample in 8:station.step()
				if week==1:
					assert(practice.live_readings("different-class").is_empty())
					Visuals.update_bench(digital,practice.live_readings(digital.id,Visuals.uses_scope_trace(digital)))
					var live:=Visuals.view(digital,false,false)
					if live.live_parameters.has("bench_hz"):
						assert(not live.has("scene") and absf(float(live.live_parameters.bench_hz)-40.)<6.)
						assert(float(live.live_parameters.bench_scope_vpp)>3.)
						assert(float(digital.visual_playback.scene.parameters.bench_hz[0])==10.)
						var trace: PackedVector2Array=live.live_series.bench_scope_trace
						assert(trace.size()>20 and trace.size()<=128 and trace[0].x<trace[-1].x and trace[-1].x<=90.)
						saw_live_scope=true
			if digital.has("lab_practice_result") or digital.has("lab_practice_error"):break
		assert(not digital.has("lab_practice_error"),str(digital.get("lab_practice_error","")))
		var result: Dictionary=digital.get("lab_practice_result",{})
		var samples: Array=result.get("samples",[])
		assert(samples.size()==[1,16,4,4,8,10,4,4][week-1] and samples.all(func(sample):return sample.correct),"Week %d: %s"%[week,result])
		assert(practice.work.is_empty())
		if week==1:
			assert(saw_live_scope)
			Visuals.update_bench(digital,practice.live_readings(digital.id))
			assert(Visuals.view(digital).live_parameters.is_empty() and Visuals.view(digital).live_series.is_empty())
		for bench in game.dc_lab.benches:
			assert(not bench.master and not bench.generator.enabled and bench.wires.is_empty() and bench.board.is_empty())
	assert(not game.session.roster.has(-100))
	classes.classes.erase("dc_lab")
	var lecture_room:="ety155_lecture"
	assert(classes._start(lecture_room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":1})=="")
	var lecture: Dictionary=classes.classes[lecture_room]
	lecture.phase="lesson"
	lecture.deadline=now+300.
	game.player.global_position=lecture.room.teacher_position
	assert(classes._sign(1,lecture_room)=="")
	var partner:=Profiles.student(0)
	lecture.classmates[partner.id]={"seated":true,"profile":partner}
	var events: Node=classes.classroom_events.service
	assert(events.start(lecture_room,now,[],"group"))
	var group: Dictionary=events.rooms[lecture_room]
	var human: String=game.school.identities[1]
	assert(events._classmate_group(group,lecture,now+8.))
	assert(not events._classmate_group(group,lecture,now+9.))
	var shared: Dictionary=group.shared.view(human)
	assert(shared.entries.size()==1 and shared.entries[0].name==partner.name and shared.can_explain)
	assert(group.shared.view("outsider").entries.is_empty())
	assert(group.round.submissions.is_empty() and group.round.participants.size()==1)
	assert(events.perform(1,lecture_room,lecture.id,group.round.event_id,"explain","I checked the units and wrote down the known values.",now+10.)=="accepted")
	assert(faculty.brain.relationship(partner.id,human).positive==1)
	lecture.classmates.erase(partner.id)
	var demo:={"version":1,"title":"Moving between surfaces","duration":10.,
		"objects":[{"type":"circle","id":"marker","x":450.,"y":230.,"radius":28.}]}
	assert(Visuals.apply(lecture,{"op":"create","scene":demo},now))
	assert(Visuals.apply(lecture,{"op":"pause"},now))
	assert(Visuals.apply(lecture,{"op":"seek","value":4.},now))
	classes._publish()
	classes._update_views()
	var board: Node3D=classes.signs[lecture_room].board
	assert(board.active and board.animation_canvas.visible)
	faculty._answer_question(1,lecture_room,lecture.teacher,lecture.id,"Could you put the animation on the projector?",game.player.global_position)
	classes._publish()
	classes._update_views()
	var projection: Node3D=classes.lesson_projector
	assert(projection.active and not board.active and projection.animation_canvas.player.clock==4.)
	assert(Visuals.apply(lecture,{"op":"layout","value":"full"},now))
	classes._publish()
	classes._update_views()
	assert(not projection.lesson_words.visible and projection.animation_canvas.player.clock==4.)
	assert(Visuals.apply(lecture,Visuals.presentation_request("Put the animation on the left"),now))
	assert(Visuals.apply(lecture,{"op":"surface","value":"board"},now))
	classes._publish()
	classes._update_views()
	assert(not projection.active and board.active and board.lesson_row.get_child(0)==board.animation_canvas)
	assert(board.lesson_words.visible and board.animation_canvas.player.clock==4.)
	var file:=Visuals.file_request("Could you please save animation as scope review?")
	assert("scope_review" in Visuals.use_local_file(lecture,file,now))
	assert("already in use" in Visuals.use_local_file(lecture,file,now))
	var later_class:={"phase":"lesson"}
	assert("loaded" in Visuals.use_local_file(later_class,Visuals.file_request("load animation scope review"),now+10.))
	assert(later_class.visual_playback.scene.layout=="left" and later_class.visual_playback.clock==4.)
	assert(not later_class.visual_playback.playing)
	var intro_profile:=Profiles.student(1)
	intro_profile.talk=.8
	var origin: Vector3=lecture.room.teacher_position
	var speaker:={"profile":intro_profile,"position":origin,"arrival":now-1.,"seated":true}
	var listener:={"profile":partner,"position":origin+Vector3(0,0,2),"arrival":now-1.,"seated":true}
	var preclass:={"phase":"arrival","deadline":now+20.,"classmates":{intro_profile.id:speaker,partner.id:listener}}
	classmates._before_class(preclass,now)
	assert(speaker.line.begins_with("Hi, I'm") and not listener.has("line"))
	assert(speaker.look_at==listener.position and listener.look_at==speaker.position)
	assert(faculty.brain.recall(partner.id,intro_profile.id).is_empty())
	classmates._show_preclass_reply(preclass,now+3.)
	assert(listener.line.begins_with("I'm") and faculty.brain.recall(partner.id,intro_profile.id).size()==1)
	classmates._before_class(preclass,now+5.)
	assert(not preclass.has("classmate_reply"))
	classes.classes.erase(lecture_room)
	if faculty.current.get("ac_lab","").is_empty():faculty._rotate("ac_lab")
	var visit: Dictionary=faculty._ai_activity("ac_lab")
	assert(visit.get("phase","")=="office_hours")
	faculty._sync_lab_teachers()
	game.player.global_position=faculty._teacher_position("ac_lab")
	assert(classes._inside(1,"ac_lab"))
	faculty.open_conversation("ac_lab")
	faculty._answer_question(1,"ac_lab",visit.teacher,visit.id,"Do you have a hobby?",game.player.global_position)
	assert("outside of class" in faculty.conversation_text.text)
	faculty._answer_question(1,"ac_lab",visit.teacher,visit.id,"Hello again",game.player.global_position)
	assert("Good to see you again" in faculty.conversation_text.text)
	assert(faculty.brain.recall(visit.teacher,human).size()==2)
	faculty.close_conversation()
	classes.classes[lecture_room]={"teacher":visit.teacher}
	assert(faculty._ai_activity("ac_lab").is_empty())
	classes.classes.erase(lecture_room)
	if faculty.current.get("dc_lab","").is_empty():faculty._rotate("dc_lab")
	var dc_visit: Dictionary=faculty._ai_activity("dc_lab")
	assert(dc_visit.get("phase","")=="office_hours")
	faculty._sync_lab_teachers()
	game.player.global_position=faculty._teacher_position("dc_lab")
	var dc_bench: RefCounted=game.dc_lab.benches[0]
	var design:=Breadboard.empty()
	design.parts=[{"id":"r","type":"r1000","a":"P1","b":"N1"}]
	assert(dc_bench.apply({"op":"board","design":design})=="")
	assert(dc_bench.apply({"op":"wire","a":"CH1+","b":"B1"})=="")
	assert(dc_bench.apply({"op":"wire","a":"CH1-","b":"B2"})=="")
	assert(dc_bench.apply({"op":"channel","index":0,"key":"enabled","value":true})=="")
	assert(dc_bench.apply({"op":"master"})=="")
	for i in 4:dc_bench.step()
	assert("Place your own board" in faculty._inspect_student_circuit(1,"dc_lab",dc_visit.teacher,dc_visit))
	dc_bench.board_owner=1
	assert("host solver has a result" in faculty._inspect_student_circuit(1,"dc_lab",dc_visit.teacher,dc_visit))
	print("CLASSMATE_CONVERSATION_AND_LIVE_LABS PASS")
	game.queue_free()
	await process_frame
	quit()
