extends SceneTree
const ROOM:="elm253_lecture"
const PORT:=26442
var game: Node

func _initialize() -> void:call_deferred("run")

func wait_for(check: Callable,label: String,seconds:=20.) -> bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000.)
	while Time.get_ticks_msec()<until:
		if check.call():return true
		await create_timer(.05).timeout
	push_error("Visual multiplayer test timed out at "+label)
	quit(1)
	return false

func run() -> void:
	var host: bool=OS.get_cmdline_user_args()[0]=="host"
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	game.client_preferences.values.teacher_speech=false
	var classes: Node=game.lecture_classes
	if host:
		assert(game.session.host_game("Visuals Host",PORT)==OK)
		var client: Node=game.host_openai
		assert(client.set_local_test_endpoint("http://127.0.0.1:28771/v1"))
		assert(client.set_session_key("sk-test-12345678901234567890"))
		assert(client.configure("gpt-5.4-mini",128,"",true)==OK)
		assert(classes._start(ROOM,{"kind":"lecture","course_id":"ELM253","week":1,"difficulty":1})=="")
		var state: Dictionary=classes.classes[ROOM]
		state.phase="lesson"
		state.deadline=classes._now()+380.
		classes._publish()
		print("CLASS_VISUAL_HOST_READY")
		if not await wait_for(func():return state.has("visual_playback") and not state.visual_playback.playing,"guest pauses scene",75.):return
		assert(float(state.visual_playback.scene.parameters.frequency[0])==2.)
		assert(not classes.classes.has("dc_lab"))
		if not await wait_for(func():return state.get("visual_surface","")=="projector","guest moves paused scene to projector"):return
		if not await wait_for(func():
			var model: RefCounted=state.visual_playback
			return not model.scene.get("cues",[]).is_empty() and not model.playing and model.clock==1.25,
			"authored cue pauses the host"):return
		print("CLASS_VISUAL_HOST PASS")
		await create_timer(3.).timeout
	else:
		assert(game.session.join_game("127.0.0.1","Visuals Guest",PORT)==OK)
		var point: Vector3=game.campus.registry.activity_room("ELM253","lecture",ROOM).teacher_position+Vector3(0,0,1.3)
		if not await wait_for(func():
			game.player.global_position=point
			game.session.send_pose({"position":point})
			return not classes.public_classes.get(ROOM,{}).get("stage",{}).is_empty(),
		"joining room",40.):return
		var faculty: Node=game.faculty
		var board: Node=classes.signs[ROOM].board
		faculty.open_conversation(ROOM)
		faculty.conversation_input.text="Could you animate a phasor beside its sine wave?"
		faculty._submit_question()
		if not await wait_for(func():return _visual().get("scene",{}).get("title","")=="Rotating phasor" and is_instance_valid(board.animation_canvas) and board.animation_canvas.visible,
		"scene arrives on board"):return
		await create_timer(1.1).timeout
		assert(_visual().scene.objects.size()==3)
		faculty.conversation_input.text="Can we see that graph with twice the frequency?"
		faculty._submit_question()
		if not await wait_for(func():return _visual().get("scene",{}).get("parameters",{}).get("frequency",[]).has(2.),
		"parameter update arrives"):return
		faculty.conversation_input.text="Please pause the animation here."
		faculty._submit_question()
		if not await wait_for(func():return not _visual().is_empty() and not _visual().playing and "paused" in faculty.conversation_text.text,
		"paused animation and reply"):return
		var position_before: float=board.animation_canvas.player.clock
		await create_timer(1.2).timeout
		assert(absf(position_before-board.animation_canvas.player.clock)<.05)
		faculty.conversation_input.text="Could you put the animation on the projector?"
		faculty._submit_question()
		if not await wait_for(func():
			var projector: Node3D=classes.lesson_projector
			return is_instance_valid(projector) and projector.active and projector.animation_canvas.visible,
			"guest projector shows the animation"):return
		assert(not board.active)
		assert(absf(position_before-classes.lesson_projector.animation_canvas.player.clock)<.05)
		faculty.conversation_input.text="Create a guided animation with a pause cue."
		faculty._submit_question()
		if not await wait_for(func():
			var state:=_visual()
			var paused: bool=not state.get("scene",{}).get("cues",[]).is_empty() and not state.playing and absf(float(state.time)-1.25)<.01
			return paused and classes.lesson_projector.animation_canvas.player.cue_label()=="Inspect the phasor",
			"guest receives the exact cue pause"):return
		print("CLASS_VISUAL_GUEST PASS")
		faculty.close_conversation()
	game.session.leave()
	game.queue_free()
	await process_frame
	quit()

func _visual() -> Dictionary:
	return game.lecture_classes.public_classes.get(ROOM,{}).get("animation",{})
