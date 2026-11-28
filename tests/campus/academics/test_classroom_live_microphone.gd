extends SceneTree
## Manual / virtual-cable hardware harness. Use separate isolated user data
## for host and guest, a normal guest audio/display driver, and headphones.
## Start the loopback HTTP fixture at port 28769, then run with -- host / guest.
## Speak after MIC_READY. The optional WAV is played through the selected
## output device and must return through a real virtual cable input; no PCM,
## onset event or conversation target is injected into the game.
## The HTTP fixture supplies fixed transcription/reply text, so a hardware
## PASS establishes capture/routing, not real speech-recognition quality.
## -- load-only verifies Main/script loading without opening an input device
## or connecting either peer. LOAD_ONLY is explicitly NOT a hardware run.
const ROOM := "elm253_lecture"
const KEY := "sk-test-12345678901234567890"
var game: Node
var captured_packets:=0
var captured_onsets:=0

func _initialize() -> void:
	call_deferred("run")

func wait_for(check: Callable, seconds: float, label: String) -> bool:
	var stop:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<stop:
		if check.call():return true
		await create_timer(.05).timeout
	push_error("Classroom microphone timed out: "+label)
	if is_instance_valid(game):
		print("MIC_DIAGNOSTIC ",game.faculty.shared_microphone.diagnostic," route=",game.faculty.natural_voice.diagnostic)
	quit(1)
	return false

func run() -> void:
	var arguments:=OS.get_cmdline_user_args()
	var mode:=str(arguments[0]) if not arguments.is_empty() else ""
	if mode not in ["host","guest","load-only"]:
		push_error("Use -- host, -- guest or -- load-only. Hardware verification requires an actual microphone or virtual-cable input.")
		quit(1);return
	var host:=mode=="host"
	var port:=int(OS.get_environment("LABVOLT_MIC_TEST_PORT"))
	if port<=0:port=26437
	var requested_seconds:=float(OS.get_environment("LABVOLT_MIC_LISTEN_SECONDS"))
	var listen_seconds:=clampf(requested_seconds,22.,120.) if requested_seconds>0. else 22.
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	var preferences=game.client_preferences
	preferences.set_option("microphone_muted",true)
	preferences.set_option("teacher_automatic_conversation",false)
	if mode=="load-only":
		assert(game.faculty.shared_microphone==game.voice_chat.microphone)
		assert(not game.faculty.shared_microphone.is_active())
		print("CLASSROOM_MIC_LOAD_ONLY PASS (Main loaded; NOT hardware-run; no microphone input or network fixture exercised)")
		game.queue_free();await process_frame;await process_frame;quit();return
	game.capture()
	game.player.set_physics_process(false)
	preferences.set_option("teacher_speech",false)
	preferences.set_option("teacher_subtitles",true)
	# This harness isolates addressed speech; amplitude-based classroom noise
	# discipline is exercised by its own fixtures.
	preferences.set_option("teacher_mic_detection",false)
	var classes: Node=game.lecture_classes
	var faculty: Node=game.faculty
	if host:
		assert(game.session.host_game("Microphone Host",port)==OK)
		assert(game.host_openai.set_local_test_endpoint("http://127.0.0.1:28769/v1"))
		assert(game.host_openai.set_session_key(KEY))
		assert(game.host_openai.configure("gpt-5.4-mini",128,"",true)==OK)
		game.host_openai.stt_enabled=true
		game.host_openai.stt_model="gpt-4o-mini-transcribe"
		game.host_openai.live_enabled=false
		game.host_openai.tts_enabled=false
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
			# Existing test-only learner identity for the unauthenticated ENet
			# fixture; production sign-in is outside this hardware harness.
			identity="0123456789abcdef0123456789abcdef0123456789abcdef"
			game.school.identities[guest]=identity
		var teacher: String=state.teacher
		if not await wait_for(func():return not faculty.brain.recall(teacher,identity).is_empty(),maxf(80.,listen_seconds+40.),"captured audio transcribed and answered"):return
		var exchanges: Array=faculty.brain.recall(teacher,identity)
		assert(exchanges[-1].student=="What does the board show?")
		print("CLASSROOM_MIC_HOST PASS (captured guest input; fixture transcription/reply)")
		await create_timer(3.).timeout
	else:
		assert(DisplayServer.get_name()!="headless","The hardware guest needs a focused real window; use -- load-only for headless verification.")
		assert(game.session.join_game("127.0.0.1","Microphone Guest",port)==OK)
		var info: Dictionary=game.campus.registry.activity_room("ELM253","lecture",ROOM)
		var point: Vector3=info.teacher_position+Vector3(0,0,1.7)
		if not await wait_for(func():
			game.player.global_position=point
			game.session.send_pose({"position":point})
			return classes.public_classes.has(ROOM) and faculty._teacher_position(ROOM).is_finite(),
		45.,"classroom teacher appears"):return
		var teacher:=str(classes.public_classes[ROOM].teacher)
		var teacher_position: Vector3=faculty._teacher_position(ROOM)
		game.player.global_position=teacher_position+Vector3(0,0,1.7)
		game.player.look_at(Vector3(teacher_position.x,game.player.global_position.y,teacher_position.z))
		game.player.eyes.look_at(teacher_position+Vector3.UP*1.5)
		game.session.send_pose({"position":game.player.global_position,"yaw":game.player.rotation.y,"pitch":game.player.eyes.rotation.x})
		await physics_frame
		assert(faculty.voice_candidates(root.multiplayer.get_unique_id()).any(func(candidate: Dictionary):return candidate.id==teacher and candidate.visible),"The actual teacher must be in the guest's hearing space and line of sight.")
		print("MIC_DEVICES ",AudioServer.get_input_device_list())
		var fixture:=OS.get_environment("LABVOLT_CAPTURE_FIXTURE_WAV")
		var requested_input:=OS.get_environment("LABVOLT_MIC_TEST_INPUT")
		var requested_output:=OS.get_environment("LABVOLT_MIC_TEST_OUTPUT")
		var input_name:="Default" if requested_input.is_empty() else requested_input
		var output_name:="Default" if requested_output.is_empty() else requested_output
		if not fixture.is_empty():
			if requested_output.is_empty():output_name="CABLE Input (VB-Audio Virtual Cable)"
			if requested_input.is_empty():input_name="CABLE Output (VB-Audio Virtual Cable)"
			# Route only the fixture WAV into the cable; game ambience or other
			# players must not accidentally become this fixture's microphone input.
			for bus: String in ["effects","ambience","interface","npc_speech","human_voice","phone_calls"]:preferences.set_option(bus,0.0)
		assert(input_name in AudioServer.get_input_device_list(),"Microphone is unavailable: "+input_name)
		assert(output_name in AudioServer.get_output_device_list(),"Audio output is unavailable: "+output_name)
		preferences.set_option("output_device",output_name)
		preferences.set_option("microphone_device",input_name)
		preferences.set_option("microphone_mode","voice_activation")
		preferences.set_option("microphone_echo_mode","headphones")
		preferences.set_option("microphone_noise_gate",true)
		preferences.set_option("teacher_mic_sensitivity",1.0)
		root.grab_focus()
		if not await wait_for(func():return root.has_focus(),30.,"guest window focus"):return
		game.capture()
		var microphone: Node=faculty.shared_microphone
		assert(microphone==game.voice_chat.microphone and microphone==root.get_node("MicrophoneCapture"),"Human voice and NPC recognition must share one microphone owner.")
		microphone.packet_ready.connect(func(_pcm: PackedByteArray,_activity: Dictionary):captured_packets+=1)
		microphone.speech_started.connect(func(_turn_id: int):captured_onsets+=1)
		assert(faculty.natural_voice.current.is_empty(),"No NPC conversation is forced before real speech onset.")
		preferences.set_option("teacher_automatic_conversation",true)
		preferences.set_option("microphone_muted",false)
		if not await wait_for(func():return game.voice_chat.talking and microphone.is_active(),5.,"shared microphone activates through normal game controls"):return
		print("MIC_READY ",AudioServer.input_device," · face the teacher and speak normally; no E or V is required")
		if not fixture.is_empty():
			var playback:=AudioStreamPlayer.new()
			playback.stream=AudioStreamWAV.load_from_file(fixture)
			assert(playback.stream!=null)
			root.add_child(playback)
			await create_timer(1.).timeout
			print("MIC_ROUTE ",AudioServer.output_device," -> ",AudioServer.input_device)
			playback.play()
		var speech: Node=faculty.speech_player
		if not await wait_for(func():
			return speech.subtitles.get(ROOM,{}).get("item",{}).get("text","")=="The board shows a current path." and faculty.natural_voice.current.get("id","")==teacher,
		listen_seconds,"teacher response from recorded speech"):return
		assert(AudioServer.get_input_device_list().size()>0)
		assert(captured_packets>0 and captured_onsets>0,"A real shared capture packet and VAD onset must precede the reply.")
		assert(not faculty.conversation.visible,"Natural speech does not open the text conversation panel.")
		print("CLASSROOM_MIC_GUEST PASS (shared capture packets=",captured_packets," onsets=",captured_onsets,"; natural NPC targeting; fixture transcription/reply)")
	preferences.set_option("microphone_muted",true)
	game.session.leave()
	game.queue_free()
	await process_frame
	quit()
