extends SceneTree
## Use a normal audio driver for the guest. Speak into its default microphone
## after MIC_READY. The host uses the local HTTP transcription fixture.
const ROOM := "elm253_lecture"
const KEY := "sk-test-12345678901234567890"
var game: Node

func _initialize() -> void:
	call_deferred("run")

func wait_for(check: Callable, seconds: float, label: String) -> bool:
	var stop:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<stop:
		if check.call():return true
		await create_timer(.05).timeout
	push_error("Classroom microphone timed out: "+label)
	quit(1)
	return false

func run() -> void:
	var host: bool=OS.get_cmdline_user_args()[0]=="host"
	var port:=int(OS.get_environment("LABVOLT_MIC_TEST_PORT"))
	if port<=0:port=26437
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	game.client_preferences.values.teacher_speech=false
	game.client_preferences.values.teacher_subtitles=true
	var classes: Node=game.lecture_classes
	var faculty: Node=game.faculty
	if host:
		assert(game.session.host_game("Microphone Host",port)==OK)
		assert(game.host_openai.set_local_test_endpoint("http://127.0.0.1:28769/v1"))
		assert(game.host_openai.set_session_key(KEY))
		assert(game.host_openai.configure("gpt-5.4-mini",128,"",true)==OK)
		game.host_openai.stt_enabled=true
		assert(classes._start(ROOM,{"kind":"lecture","course_id":"ELM253","week":1,"difficulty":1})=="")
		var state: Dictionary=classes.classes[ROOM]
		state.phase="lesson"
		state.deadline=classes._now()+classes.lesson_duration(state)+5.
		classes._publish()
		print("MIC_HOST_READY")
		if not await wait_for(func():return game.session.roster.size()==2,45.,"guest joins"):return
		var guest: int=root.multiplayer.get_peers()[0]
		if not await wait_for(func():return classes._inside(guest,ROOM),40.,"guest enters classroom"):return
		var identity: String=game.school.identities.get(guest,"")
		if identity.is_empty():
			identity="0123456789abcdef0123456789abcdef0123456789abcdef"
			game.school.identities[guest]=identity
		var teacher: String=state.teacher
		if not await wait_for(func():return not faculty.brain.recall(teacher,identity).is_empty(),80.,"captured audio transcribed and answered"):return
		var exchanges: Array=faculty.brain.recall(teacher,identity)
		assert(exchanges[-1].student=="What does the board show?")
		print("CLASSROOM_MIC_HOST PASS")
		await create_timer(3.).timeout
	else:
		assert(game.session.join_game("127.0.0.1","Microphone Guest",port)==OK)
		var info: Dictionary=game.campus.registry.activity_room("ELM253","lecture",ROOM)
		var point: Vector3=info.teacher_position+Vector3(0,0,1.3)
		if not await wait_for(func():
			game.player.global_position=point
			game.session.send_pose({"position":point})
			return classes.public_classes.has(ROOM) and faculty._teacher_position(ROOM).is_finite(),
		45.,"classroom teacher appears"):return
		game.client_preferences.values.teacher_automatic_conversation=true
		print("MIC_DEVICES ",AudioServer.get_input_device_list())
		var fixture:=OS.get_environment("LABVOLT_CAPTURE_FIXTURE_WAV")
		if not fixture.is_empty():
			var outputs:=AudioServer.get_output_device_list()
			var inputs:=AudioServer.get_input_device_list()
			var output_name:="CABLE Input (VB-Audio Virtual Cable)"
			var input_name:="CABLE Output (VB-Audio Virtual Cable)"
			if not OS.get_environment("LABVOLT_MIC_TEST_INPUT").is_empty():
				input_name=OS.get_environment("LABVOLT_MIC_TEST_INPUT")
			if not OS.get_environment("LABVOLT_MIC_TEST_OUTPUT").is_empty():
				output_name=OS.get_environment("LABVOLT_MIC_TEST_OUTPUT")
			assert(output_name in outputs and input_name in inputs,"Audio outputs %s / inputs %s"%[outputs,inputs])
			AudioServer.output_device=output_name
			AudioServer.input_device=input_name
			faculty.set_process(false)
			game.voice_chat.set_process(false)
		else:
			root.grab_focus()
			if not await wait_for(func():return root.has_focus(),30.,"guest window focus"):return
		assert(faculty._start_voice_conversation(ROOM,false))
		print("MIC_READY ",AudioServer.input_device)
		if not fixture.is_empty():
			var playback:=AudioStreamPlayer.new()
			playback.stream=AudioStreamWAV.load_from_file(fixture)
			assert(playback.stream!=null)
			root.add_child(playback)
			for i in 20:
				await create_timer(.05).timeout
				faculty._consume_voice_capture()
			print("MIC_ROUTE ",AudioServer.output_device," -> ",AudioServer.input_device)
			playback.play()
		var speech: Node=faculty.speech_player
		if not await wait_for(func():
			if not fixture.is_empty():faculty._consume_voice_capture()
			return speech.subtitles.get(ROOM,{}).get("item",{}).get("text","")=="The board shows a current path." and not faculty.voice_room.is_empty(),
		22.,"teacher response from recorded speech"):return
		assert(AudioServer.get_input_device_list().size()>0)
		print("CLASSROOM_MIC_GUEST PASS")
	faculty._stop_voice_conversation()
	game.session.leave()
	game.queue_free()
	await process_frame
	quit()
