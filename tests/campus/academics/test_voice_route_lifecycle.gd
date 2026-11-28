extends SceneTree
const NetworkCase=preload("res://tests/campus/academics/test_speech_audio_network.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game:=NetworkCase.Game.new();root.add_child(game);game.add_child(game.session);game.add_child(game.lecture_classes);game.lecture_classes.add_child(game.lecture_classes.classroom_students);game.add_child(game.host_openai)
	game.session.online=false;game.session.roster={1:{}}
	var faculty:=NetworkCase.ProbeFaculty.new();game.add_child(faculty);faculty.set_process(false);faculty.game=game
	faculty.speech_player=Player.new();faculty.add_child(faculty.speech_player)
	var actor:=Node3D.new();game.add_child(actor)
	var speech: Node=faculty.speech_player
	var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=16000;wav.data=PackedByteArray([1,2,3,4])
	assert(speech.accept("room","Teacher",1,"First.",1,actor,wav))
	var route: Dictionary=faculty._new_speech_route("room",1,"room","teacher",[],actor,NetworkCase.CLASS_ID)
	assert(faculty._speech_route_current("room",1,route))
	speech._finished("room",1)
	assert(not speech.has_utterance("room",1) and faculty._speech_route_current("room",1,route),"Normal host completion must not cancel a slow client's transfer.")
	speech.configure(false,false)
	assert(faculty._speech_route_current("room",1,route),"Local audio/subtitle preferences cannot cancel another player's clip.")
	speech.cancel("room")
	assert(not faculty._speech_route_current("room",1,route),"Explicit cancellation must stop further remote chunks.")
	var remote: Dictionary=faculty._new_speech_route("private",1,"room","teacher",[],actor,NetworkCase.CLASS_ID)
	assert(not remote.local_tracking and faculty._speech_route_current("private",1,remote))
	faculty.character_epoch+=1
	assert(not faculty._speech_route_current("private",1,remote))
	var current: Dictionary=faculty._new_speech_route("private",1,"room","teacher",[],actor,NetworkCase.CLASS_ID)
	faculty.speech_routes["private|1"]=current
	remote.sending=1;faculty._voice_send_finished("private",1,remote)
	assert(faculty.speech_routes.has("private|1"),"An old send coroutine cannot erase a new session's same-numbered route.")
	var one:={"provider":"openai","model":"gpt-4o-mini-tts","voice":"onyx","profile_version":1,"instructions":"Calm.","request_id":"one"}
	var two:=one.duplicate(true);two.request_id="two"
	assert(faculty._provider_speech_key("teacher","Hello.",one)==faculty._provider_speech_key("teacher","Hello.",two))
	two.profile_version=2
	assert(faculty._provider_speech_key("teacher","Hello.",one)!=faculty._provider_speech_key("teacher","Hello.",two))
	two=one.duplicate(true);two.instructions="Genuinely sad, subdued delivery."
	assert(faculty._provider_speech_key("teacher","Hello.",one)!=faculty._provider_speech_key("teacher","Hello.",two))
	game.queue_free();await process_frame
	print("VOICE_ROUTE_LIFECYCLE PASS (normal completion, preferences, explicit cancel, session reuse, stable expressive cache)")
	quit()
