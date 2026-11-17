extends SceneTree
const BoardState=preload("res://scripts/campus/academics/lesson_board_state.gd")

func _initialize() -> void:call_deferred("run")

func _capture(path: String) -> bool:
	for i in 16:await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().save_png(path)==OK

func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	var camera:=Camera3D.new()
	game.add_child(camera)
	camera.current=true
	for room in ["elm253_lecture","ety155_lecture"]:
		var sign: Dictionary=game.lecture_classes.signs.get(room,{})
		assert(not sign.is_empty())
		game.campus.request_room(room)
		camera.global_position=sign.board.global_position+Vector3(0,0,7.0)
		camera.look_at(sign.board.global_position)
		game.player.global_position=Vector3(camera.global_position.x,sign.board.global_position.y-1.5,camera.global_position.z)
		var lesson:={"stages":[
			{"title":"Circuit quantities","text":"Voltage, current, and resistance describe the same circuit.","formulas":"V = I R","duration_seconds":10.0},
			{"title":"Substitute measured values","text":"Use 12 V and 2 kΩ. Convert resistance to ohms before dividing.","formulas":"I = 12 V / 2000 Ω","duration_seconds":10.0},
			{"title":"Check the result","text":"The calculated current is six milliamps. Does the meter agree?","formulas":"I = 0.006 A = 6 mA","duration_seconds":10.0}]}
		var stage: Dictionary=BoardState.at(lesson,"DC circuit analysis",25.0,30.0)
		game.lecture_classes.receive({room:{"id":"visual-lesson","number":room,"course":"ETY155","week":1,"title":"DC circuit analysis","phase":"lesson","seconds":100.0,"signed":true,"done":false,"stage":stage}})
		var output:=ProjectSettings.globalize_path("res://.godot/%s-lesson-board.png"%room)
		assert(await _capture(output))
		print("LESSON_BOARD_CAPTURE ",output)
		game.lecture_classes.receive({})
	game.school._ensure_classroom_whiteboards()
	var paper: Dictionary={}
	for item in game.school.papers.values():
		if item.get("classroom_board","")=="ety155_lecture":paper=item;break
	assert(not paper.is_empty())
	paper.board_lines=[[Vector2(.08,.18),Vector2(.34,.18)],[Vector2(.34,.18),Vector2(.48,.37)]]
	paper.board_notes=[{"text":"I = V / R = 12 V / 2 kΩ = 6 mA"}]
	paper.revision=int(paper.revision)+1
	game.school_world.refresh()
	var board_output:=ProjectSettings.globalize_path("res://.godot/ety155-physical-whiteboard.png")
	assert(await _capture(board_output))
	print("PHYSICAL_BOARD_CAPTURE ",board_output)
	var chair_index: int=-1
	for i in game.chairs.size():
		if game.campus.registry.room_contains("ety155_lecture",game.chairs[i].global_position) and game.chairs[i].occupant==0:
			chair_index=i;break
	assert(chair_index>=0)
	game.session.roster[1]={"name":"Student"}
	if not game.school.identities.has(1):game.school._identify(1,game.school.local_identity)
	game.player.global_position=game.chairs[chair_index].global_position+Vector3(0,0,1)
	game._claim_chair(1,chair_index)
	assert(game.player.seated==game.chairs[chair_index])
	game._stand_from_chair()
	assert(game.player.seated==null)
	var classes=game.lecture_classes
	assert(classes._start("ety155_lecture",{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})=="")
	assert(classes._sign(1,"ety155_lecture")=="")
	var activity: Dictionary=classes.classes["ety155_lecture"]
	activity.phase="lesson";activity.deadline=classes._now()+180.0
	var events=preload("res://scripts/campus/academics/classroom_events/controller.gd").new()
	events.name="FixtureClassroomEvents"
	classes.add_child(events)
	events.configure(game)
	events.enabled=true
	classes.classroom_events=events
	for item in game.school.papers.values():
		if item.get("owner",0)==1:item.held=false
	assert(events.service.start("ety155_lecture",classes._now(),[],"board"))
	var event_id: String=events.service.rooms["ety155_lecture"].round.event_id
	var identity: String=str(game.school.identities[1])
	assert(events.service.rooms["ety155_lecture"].hands.call_student(true,event_id,identity))
	game.player.global_position=paper.position+Vector3(0,-1,2)
	await physics_frame
	game.camera.global_position=paper.position+Vector3(0,0,2)
	game.camera.look_at(paper.position)
	assert(game.school_world.use_supply(MOUSE_BUTTON_LEFT))
	assert(paper.board_lines.size()==1)
	var round=events.service.rooms["ety155_lecture"].round
	var answer: Variant=round.private_assignment.questions[round.question_index].answer
	assert(events.service.perform(1,"ety155_lecture",activity.id,event_id,"submit",answer,classes._now())=="accepted")
	game.player.global_position=game.chairs[chair_index].global_position+Vector3(0,0,1)
	game._claim_chair(1,chair_index)
	assert(game.player.seated==game.chairs[chair_index])
	print("WHITEBOARD_PLAYER_FLOW PASS")
	game.queue_free()
	await process_frame
	print("LESSON_WHITEBOARD_VISUAL PASS")
	quit(0)
