extends SceneTree
## Measured native scheduling and playback signals with an authored transcript.
## This does not measure a live transcription/model service or audio device.
const Faculty = preload("res://scripts/campus/academics/faculty.gd")
const SpeechPlayer = preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Interaction = preload("res://scripts/campus/academics/character_interaction.gd")
const Store = preload("res://scripts/campus/academics/character_dossier_store.gd")
const Reader = preload("res://scripts/campus/ui/character_inspector_snapshot.gd")
const ROOM := "elm253_lecture"
var failures: Array[String] = []
var checks := 0

class Provider extends Node:
	var busy := true
	var transcriptions := 0
	func transcribe_wav(_wav: PackedByteArray) -> Dictionary:
		transcriptions += 1
		var deadline := Time.get_ticks_msec()+120
		while Time.get_ticks_msec()<deadline:await get_tree().process_frame
		return {"ok":true,"text":"An authored timing fixture transcript."}

class SchoolState extends Node:
	var local_identity := "timing_host"
	var identities := {1:"timing_host"}
	func formal_active() -> bool:return false

class SessionState extends Node:
	var roster := {1:{}}
	var online := false

class ClassroomState extends Node:
	var classes := {ROOM:{"id":"timing_class","teacher":"mr_bro","phase":"freeplay"}}
	func _inside(_peer: int, room: String) -> bool:return room==ROOM

class GameState extends Node:
	var school := SchoolState.new()
	var session := SessionState.new()
	var lecture_classes := ClassroomState.new()
	var player := Node3D.new()
	var host_openai := Provider.new()
	func _init() -> void:
		for child in [school,session,lecture_classes,player,host_openai]:add_child(child)

class TimingFaculty extends "res://scripts/campus/academics/faculty.gd":
	var captured: Array[Dictionary] = []
	func _question_status(_peer: int,_room: String,_teacher: String,_message: String) -> void:pass
	func _answer_question(peer: int,_room: String,_id: String,_class_id: String,question: String,_pos: Vector3,_voice_context: Dictionary={},timing: Dictionary={}) -> void:
		captured.append({"question":question,"timing":timing.duplicate(true)})
		_release_question(peer,character_epoch)

func _initialize() -> void:run.call_deferred()

func check(value: bool,message: String) -> void:
	checks += 1
	if not value:failures.append(message);push_error(message)

func run() -> void:
	create_timer(15.).timeout.connect(func():push_error("Request timing test timed out");quit(1))
	var game := GameState.new();root.add_child(game)
	var faculty := TimingFaculty.new();faculty.game=game;root.add_child(faculty);faculty.set_process(false)
	faculty.brain._host_profile="timing_host";Store.host_identity="timing_host"
	faculty.ai_busy[1]=ROOM
	faculty.question_channels[1]="mr_bro"
	var submitted := Time.get_ticks_msec()
	faculty._question_request(1,ROOM,"A typed timing request.","mr_bro","timing_class")
	check(faculty.questions.size()==1,"Production teacher queue retains work while this player and character have an active reservation")
	var queued: Dictionary=faculty.questions[0]
	check(int(queued._timing.host_received_ms)>=submitted and queued._timing.input_kind=="typed","Typed host receipt is captured from the running clock")
	var queued_until := Time.get_ticks_msec()+80
	while Time.get_ticks_msec()<queued_until:await process_frame
	game.host_openai.busy=false
	faculty._release_question(1,faculty.character_epoch)
	faculty._next_question()
	check(faculty.captured.size()==1,"Production queue forwards typed work to the selected answer path")
	var typed: Dictionary=faculty.captured[0].timing
	check(int(typed.queue_wait_ms)>=70 and int(typed.queue_started_ms)>=int(typed.host_received_ms),"Observed queue delay is carried into the answer path")
	check(not typed.has("transcription_ms"),"Typed requests do not invent a transcription measurement")
	var samples := PackedByteArray();samples.resize(32000)
	var wav: PackedByteArray=Faculty.TeacherAI.wav_16k(samples)
	faculty._speech_question_request(1,ROOM,wav,"mr_bro","timing_class")
	var deadline := Time.get_ticks_msec()+3000
	while faculty.captured.size()<2 and Time.get_ticks_msec()<deadline:await create_timer(.01).timeout
	check(faculty.captured.size()==2 and game.host_openai.transcriptions==1,"Production microphone path awaits its actual transcription coroutine")
	var audio: Dictionary=faculty.captured[1].timing
	check(audio.input_kind=="microphone" and int(audio.transcription_ms)>=110,"Measured transcription delay and microphone input kind reach the answer path")
	check(int(audio.transcription_finished_ms)>=int(audio.transcription_started_ms) and int(audio.transcription_started_ms)>=int(audio.queue_started_ms),"Recorded stage timestamps retain their actual order")
	var response := {"prepared":{"activity":{"phase":"freeplay"},"extra":{"_timing":audio.duplicate(true)}},"turn":{"interpretation":{"question_kind":"casual","domain":"conversation","event":"chat"}}}
	var updated_timing: Dictionary=audio.duplicate(true)
	faculty._mark_character_response_ready(response,updated_timing)
	check(updated_timing.get("stream_safe",false) and updated_timing.host_text_ready_ms==response.prepared.extra._timing.host_text_ready_ms,"Text readiness and safe streaming classification reach the caller")
	var measured := Interaction._response_timing(response.prepared)
	for context in [{"phase":"assignment"},{"domain":"electronics"},{"official":true},{"event":"hazard"}]:
		var restricted: Dictionary=response.duplicate(true)
		restricted.prepared.activity.phase=context.get("phase","freeplay")
		restricted.prepared.extra.official_communication=context.get("official",false)
		restricted.turn.interpretation.domain=context.get("domain","conversation")
		restricted.turn.interpretation.event=context.get("event","chat")
		var restricted_timing: Dictionary={}
		faculty._mark_character_response_ready(restricted,restricted_timing)
		check(not restricted_timing.get("stream_safe",true),"Assessment, technical, official and hazardous speech require full verification")
	check(float(measured.host_to_text_ms)>=float(measured.transcription_ms)+float(measured.queue_wait_ms),"Host-receipt-to-reply timing includes both queue and transcription")
	check(not Interaction._response_timing({}).has("host_to_text_ms"),"Unobserved host receipt stays unknown")
	check(not Interaction._response_timing({"extra":{"_timing":{"host_received_ms":20,"host_text_ready_ms":10}}}).has("host_to_text_ms"),"Reversed timestamps cannot produce fabricated negative latency")

	var player := SpeechPlayer.new();faculty.add_child(player);faculty.speech_player=player
	player.configure(true,false)
	player.playback_started.connect(faculty._character_audio_started)
	var anchor := Node3D.new();root.add_child(anchor)
	var stream := AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=16000;stream.data=samples
	var receipt := int(audio.host_received_ms)
	faculty.character_interaction.diagnostics.append({"event_id":"timed_audio","character":"mr_bro","speaker":"timing_host","timing":{}})
	faculty._track_character_audio("timing",1,"timed_audio",{"host_received_ms":receipt})
	check(player.accept("timing","Timing teacher",1,"An authored playback timing sample.",2,anchor,null,1.0,{"expect_audio":true}),"Native speech player accepts a stream-pending presentation")
	faculty.speech_routes[faculty._voice_key("timing",1)]=faculty._new_speech_route("timing",1,ROOM,"mr_bro",[],anchor)
	faculty._speech_completed("timing",1,"timing_stream",stream,"ok")
	var speech_timing: Dictionary=faculty.character_interaction.diagnostics[-1].timing
	check(player.active.has("timing") and is_instance_valid(player.active.timing.player),"An actual AudioStreamPlayer3D starts the supplied stream")
	check(speech_timing.has("host_to_audio_ready_ms") and speech_timing.has("host_to_playback_started_ms"),"Real stream delivery and playback signals update the matching event")
	check(float(speech_timing.host_to_playback_started_ms)>=float(speech_timing.host_to_audio_ready_ms) and float(speech_timing.host_to_audio_ready_ms)>=110,"Audio readiness and local playback timings include preceding request work")
	var original := speech_timing.duplicate(true)
	faculty._character_audio_started("timing",1,Time.get_ticks_msec()+999)
	check(faculty.character_interaction.diagnostics[-1].timing==original,"A repeated playback callback cannot overwrite the first actual start")
	player.configure(false,false)
	faculty.character_interaction.diagnostics.append({"event_id":"muted_audio","character":"mr_bro","speaker":"timing_host","timing":{}})
	faculty._track_character_audio("muted",1,"muted_audio",{"host_received_ms":receipt})
	player.accept("muted","Muted teacher",1,"An authored muted timing sample.",2,anchor,stream)
	check(not faculty.character_interaction.diagnostics[-1].timing.has("host_to_playback_started_ms"),"Disabled speech does not report an invented playback start")
	var private_trace := Reader.selected_diagnostics(faculty.character_interaction.diagnostics,"mr_bro","timing_host","freeplay")
	check(private_trace.timing.is_empty(),"Selected inspector keeps an unmeasured event's timing unknown")
	var own_trace := Reader.selected_diagnostics([{"event_id":"timed_audio","character":"mr_bro","speaker":"timing_host","timing":original}],"mr_bro","timing_host","freeplay")
	check(own_trace.timing==original,"Authorized inspector forwards actual event timing without estimates")
	print("CHARACTER_REQUEST_TIMING ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," measured=",JSON.stringify({"typed_queue_ms":typed.queue_wait_ms,"microphone":measured,"speech":original})," source=authored transcript; real scheduling and playback signal, no live API or audio-device claim")
	player.clear_session();anchor.queue_free();faculty.queue_free();game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
