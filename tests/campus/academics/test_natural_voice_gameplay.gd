extends SceneTree
## Real Main scene, character targeting, HTTP adapter, mind/memory and playback.
## Synthetic device PCM and a loopback provider are explicit fixtures: this is
## not evidence of live microphone recognition or audible character quality.
var game: Node
var checks:=0
var failures: Array[String]=[]
const ROOM:="ac_lab"
const TEACHER:="mr_bro"

func _initialize() -> void:run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message);push_error(message)

func wait_for(condition: Callable,seconds: float,message: String) -> bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000.)
	while Time.get_ticks_msec()<until:
		if condition.call():return true
		await create_timer(.025).timeout
	check(false,message)
	return false

func inject_utterance(speech_packets: int=32,silence_packets: int=105) -> void:
	var microphone: Node=game.faculty.shared_microphone
	for index in speech_packets+silence_packets:
		var voiced:=index<speech_packets
		var pcm:=PackedByteArray();pcm.resize(640)
		if voiced:
			for sample in 320:pcm.encode_s16(sample*2,int(sin(float(index*320+sample)*TAU*220./16000.)*3000.))
		microphone.packet_ready.emit(pcm,{"speech":voiced,"rms":.06 if voiced else 0.})
		microphone._emit_activity(microphone.activity.PushPcm(pcm,voiced))

func run() -> void:
	create_timer(70.).timeout.connect(func():push_error("Natural voice gameplay timed out");quit(1))
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 3:await process_frame
	check(game.front.in_game,"Singleplayer starts through the ordinary menu route")
	game.player.set_physics_process(false)
	game.voice_chat.set_process(false)
	game.faculty.shared_microphone.set_process(false)
	# The headless driver has no focused physical microphone. Model only that
	# boundary as an active device; leave all NPC target/conversation code real.
	game.client_preferences.set_option("microphone_mode","voice_activation")
	game.client_preferences.set_option("microphone_echo_mode","headphones")
	game.client_preferences.set_option("teacher_mic_detection",false)
	game.client_preferences.set_option("teacher_automatic_conversation",false)
	game.voice_chat.talking=true
	game.faculty.current[ROOM]=TEACHER
	game.faculty._sync_lab_teachers()
	for frame in 3:await process_frame
	var model: Node3D=game.faculty._model_for_room(ROOM,TEACHER)
	check(is_instance_valid(model),"Mr Bro is present in the actual lab scene")
	if not is_instance_valid(model):quit(1);return
	game.faculty.lab_routes.erase(ROOM)
	var teacher_position: Vector3=game.school_world.teacher.global_position
	model.global_position=teacher_position
	game.player.global_position=teacher_position+Vector3(0,0,1.7)
	game.player.eyes.look_at(teacher_position+Vector3.UP*1.5)
	await physics_frame
	check(game.campus.registry.locate(game.player.global_position)==ROOM,"Approach stays inside the lab hearing space")
	check(game.faculty.voice_candidates(1).any(func(candidate: Dictionary):return candidate.id==TEACHER and candidate.visible),"Host-observed line of sight reaches Mr Bro")
	var port:=OS.get_environment("LABVOLT_OPENAI_FIXTURE_PORT")
	if port.is_empty():port="28779"
	check(game.host_openai.set_local_test_endpoint("http://127.0.0.1:%s/v1"%port),"Loopback provider endpoint is accepted")
	check(game.host_openai.set_session_key("sk-test-12345678901234567890"),"Only the synthetic fixture credential is configured")
	check(game.host_openai.configure("gpt-5.4-mini",256,"",true)==OK,"Reasoning fixture uses the production provider adapter")
	game.host_openai.stt_enabled=true;game.host_openai.stt_model="gpt-4o-mini-transcribe"
	game.host_openai.tts_enabled=true;game.host_openai.tts_model="gpt-4o-mini-tts"
	game.client_preferences.set_option("teacher_speech",true)
	var identity:=str(game.school.local_identity)
	inject_utterance()
	await create_timer(.15).timeout
	check(game.faculty.natural_voice.current.is_empty() and game.faculty.brain.recall(TEACHER,identity).is_empty(),"Captured sound cannot begin an AI conversation before recognition opt-in")
	game.client_preferences.set_option("teacher_automatic_conversation",true)
	game.voice_chat.talking=true
	check(not game.faculty.conversation.visible,"No text interaction panel is open")
	inject_utterance()
	check(game.faculty.natural_voice.current.get("id","")==TEACHER,"Speech onset naturally selects the approached NPC without E or an internal conversation-start call")
	if not await wait_for(func():return game.faculty.brain.recall(TEACHER,identity).size()>=1,10.,"Recognized speech reaches the actual character memory pipeline"):
		print("NATURAL_VOICE_DIAGNOSTIC ",game.faculty.natural_voice.diagnostic)
	else:
		var first: Dictionary=game.faculty.brain.recall(TEACHER,identity)[0]
		check(first.student=="What does the board show?","Transcription travels through the production HTTP envelope into memory")
		check(first.teacher=="The board shows a current path.","Validated character reply is stored as the delivered conversation")
		check(not game.faculty.conversation.visible,"Natural voice leaves the text panel closed")
		await wait_for(func():return not game.faculty.speech_player.active.is_empty(),8.,"Synthesized fixture reaches actual positional speech playback")
		await create_timer(.35).timeout
		inject_utterance()
		await wait_for(func():return game.faculty.brain.recall(TEACHER,identity).size()>=2,10.,"Follow-up speech reaches the same character without reopening anything")
		check(game.faculty.natural_voice.current.get("id","")==TEACHER,"Follow-up retains the ongoing character identity")
		# A previous target may differ when a new onset chooses Mr Bro. Canceling
		# the old target must not reset the VAD that owns this brand-new utterance.
		game.faculty.natural_voice.current={"id":"bill_nye","room":ROOM,"class_id":"previous_target","student":""}
		inject_utterance()
		await wait_for(func():return game.faculty.brain.recall(TEACHER,identity).size()>=3,10.,"Switching target at speech onset preserves the complete new utterance")
		await wait_for(func():return game.faculty.natural_voice.diagnostic.state=="response_generated",5.,"Voice diagnostics reach the generated response stage")
		# PTT release flushes through the NPC consumer even while human voice-chat
		# processing is disabled. No silence timeout or UI is required.
		game.client_preferences.set_option("microphone_mode","push_to_talk")
		var press:=InputEventKey.new();press.keycode=KEY_V;press.physical_keycode=KEY_V;press.pressed=true;Input.parse_input_event(press)
		await process_frame
		game.faculty.natural_voice._process(.25)
		inject_utterance(32,0)
		var release:=InputEventKey.new();release.keycode=KEY_V;release.physical_keycode=KEY_V;release.pressed=false;Input.parse_input_event(release)
		await process_frame
		game.faculty.natural_voice._process(.25)
		await wait_for(func():return game.faculty.brain.recall(TEACHER,identity).size()>=4,10.,"Releasing the actual PTT key flushes one recorded NPC turn")
		# Manual recording works while the inspector has released mouse capture
		# and disabled first-person controls.
		game.client_preferences.set_option("microphone_mode","manual")
		game.faculty.open_conversation(ROOM)
		game.faculty._toggle_recording()
		check(game.faculty.recording and not game.player.enabled,"Manual recording starts with the interaction UI open")
		inject_utterance(32,0)
		check(game.faculty.record_samples.size()>=32*640,"Manual recording receives shared packets while first-person controls are disabled")
		game.faculty._finish_recording()
		await wait_for(func():return game.faculty.brain.recall(TEACHER,identity).size()>=5,10.,"Manual completed recording enters the same character memory pipeline")
		game.faculty.close_conversation()
		game.client_preferences.set_option("microphone_mode","voice_activation")
	var remembered: int=game.faculty.brain.recall(TEACHER,identity).size()
	inject_utterance(25,0)
	check(not game.faculty.natural_voice.turn.is_empty(),"A fresh sustained microphone turn is active before a text-input interruption")
	game.player.chat_typing=true
	game.faculty.natural_voice._process(.25)
	check(game.faculty.natural_voice.current.is_empty() and game.faculty.natural_voice.turn.is_empty() and game.faculty.natural_voice.remote_turns.is_empty(),"Opening chat cancels the captured turn and authority token so a paused lecture cannot remain stranded")
	game.player.chat_typing=false
	game.client_preferences.set_option("microphone_muted",true)
	inject_utterance()
	await create_timer(.15).timeout
	check(game.faculty.natural_voice.current.is_empty() and game.faculty.natural_voice.turn.is_empty(),"Mute immediately clears active targeting and captured utterance")
	check(game.faculty.brain.recall(TEACHER,identity).size()==remembered,"Muted synthetic packets never add an AI conversation")
	game.client_preferences.set_option("microphone_muted",false)
	game.voice_chat.talking=true
	game.player.global_position=Vector3(13,0,35)
	inject_utterance()
	await create_timer(.15).timeout
	check(game.faculty.natural_voice.current.is_empty(),"Walking out of hearing range prevents a new NPC conversation")
	check(game.faculty.brain.recall(TEACHER,identity).size()==remembered,"Out-of-range audio is not sent through character memory")
	print("NATURAL_VOICE_GAMEPLAY %s checks=%d failures=%d (synthetic shared capture and loopback provider; real scene routing, memory and playback)"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	game.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
