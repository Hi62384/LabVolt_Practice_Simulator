extends SceneTree
## Real ENet transport and real Faculty/scheduler/player paths; synthetic provider only.
const FacultyScript=preload("res://scripts/campus/academics/faculty.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const People=preload("res://scripts/campus/academics/class_character_profile.gd")
const StudentsScript=preload("res://scripts/campus/academics/classroom_students.gd")
const Transfer=preload("res://scripts/campus/voice/speech_audio_transfer.gd")
const ACTOR:="campus_student_14"
const ROOM:="ac_lab"
const CLASS_ID:="voice-network-class"
const CHANNEL:="classmate:"+ACTOR
const LONG_REPLY:="Start with the voltage across the resistor and keep the exact value of 12.5 volts while we work through the next calculation. The current follows Ohm's law; use the same units throughout the calculation and explain the physical meaning. Check the polarity before connecting a meter and be certain that its selected range can measure the expected value. Each step should preserve the same circuit assumptions so the numerical answer corresponds to what you would observe on the bench."
class Session extends Node:
	var online:=true
	var roster: Dictionary={}
	func peer_connected_now(peer: int) -> bool:return peer==multiplayer.get_unique_id() or peer in multiplayer.get_peers()
class StudentWorld extends Node:
	var models: Dictionary={}
	func focus_on_player(_class_id: String,_actor: String) -> void:pass
class Classes extends Node:
	var classroom_students:=StudentWorld.new()
	func _inside(_peer: int,_room: String) -> bool:return true
	func _position(_peer: int) -> Vector3:return Vector3.ZERO
class Preferences extends RefCounted:
	var values:={"teacher_speech":true,"teacher_subtitles":true}
class Provider extends Node:
	var enabled:=true
	var tts_enabled:=true
	var tts_model:="gpt-4o-mini-tts"
	var held:=false
	var starts:=0
	var cancelled: Array=[]
	var fail_tail:=false
	var clip_bytes:=256000
	func configured() -> bool:return true
	func cancel_speech_request(request_id: String) -> void:cancelled.append(request_id)
	func speak(_text: String,_draft: Dictionary,_voice: Variant,_delivery: Dictionary) -> Dictionary:
		starts+=1
		await get_tree().process_frame
		while held:await get_tree().process_frame
		if fail_tail and str(_delivery.get("request_id","")).ends_with("-part-1"):return {"ok":false,"error":"fixture tail unavailable","retryable":false}
		var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=16000
		var data:=PackedByteArray();data.resize(clip_bytes);data.fill(24);wav.data=data
		return {"ok":true,"stream":wav}
class Game extends Node:
	var session:=Session.new()
	var lecture_classes:=Classes.new()
	var client_preferences:=Preferences.new()
	var host_openai:=Provider.new()
	var faculty: Node
class ProbeFaculty extends FacultyScript:
	var deferred_failure_observed:=false
	func _speech_completed(channel: String,serial: int,key: String,stream: AudioStreamWAV,status: String) -> void:
		super._speech_completed(channel,serial,key,stream,status)
		var route: Dictionary=speech_routes.get(_voice_key(channel,serial),{})
		if route.has("final_failure") and int(route.get("sending",0))>0:deferred_failure_observed=true
	func _ai_activity(_room: String) -> Dictionary:return {"id":CLASS_ID,"phase":"lesson","teacher":"mr_bro"}
	func _voice_recipients(_room: String) -> Array[int]:
		var result: Array[int]=[]
		for peer in multiplayer.get_peers():result.append(peer)
		return result
	func _character_gesture(key: String,_model: Node3D,mood: String,raised: bool,gesture:="",_point:=Vector3.INF) -> void:
		reaction_pose[key]={"mood":mood,"raised":raised,"gesture":gesture}
class Bus extends Node:
	var stage:=0
	var checksum:=""
	var acknowledged:=0
	@rpc("authority","call_remote","reliable")
	func announce(value: int,hash_value: String="") -> void:stage=value;checksum=hash_value
	@rpc("any_peer","call_remote","reliable")
	func acknowledge(value: int) -> void:
		if multiplayer.is_server():acknowledged=value
var deadline:=0
var game: Game
var faculty: ProbeFaculty
var bus: Bus
func _initialize() -> void:call_deferred("run")
func until(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.01).timeout
	push_error("SPEECH AUDIO NETWORK timeout: "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var host:=args.size()>0 and args[0]=="host"
	var port:=int(args[1]) if args.size()>1 else 26418
	var network:=ENetMultiplayerPeer.new()
	if (network.create_server(port,1) if host else network.create_client("127.0.0.1",port))!=OK:quit(1);return
	root.multiplayer.multiplayer_peer=network
	bus=Bus.new();bus.name="Verification";root.add_child(bus)
	game=Game.new();game.name="Game";root.add_child(game)
	game.add_child(game.session);game.add_child(game.host_openai);game.add_child(game.lecture_classes);game.lecture_classes.add_child(game.lecture_classes.classroom_students)
	faculty=ProbeFaculty.new();faculty.name="Faculty";game.add_child(faculty);faculty.set_process(false);faculty.game=game;game.faculty=faculty
	faculty.conversation=PanelContainer.new();faculty.add_child(faculty.conversation);faculty.conversation.hide()
	faculty.voice_hint=Label.new();faculty.add_child(faculty.voice_hint)
	faculty.speech_player=Player.new();faculty.speech_player.name="TeacherSpeechPlayer";faculty.add_child(faculty.speech_player)
	faculty.speech_synth=Synth.new();faculty.add_child(faculty.speech_synth);faculty.speech_synth.configure_provider(game.host_openai)
	faculty.speech_synth.completed.connect(faculty._speech_completed)
	faculty.speech_synth.segment_completed.connect(faculty._speech_segment_completed)
	var actor:=Node3D.new();game.add_child(actor)
	game.lecture_classes.classroom_students.models[CLASS_ID+":"+ACTOR]=actor
	StudentsScript.known_profiles[ACTOR]=People.legacy_student(14)
	deadline=Time.get_ticks_msec()+25000
	if host:print("SPEECH_AUDIO_HOST_READY")
	if not await until(func():return not root.multiplayer.get_peers().is_empty(),"connection"):return
	game.session.roster[1]={}
	var client:=int(root.multiplayer.get_peers()[0]) if host else root.multiplayer.get_unique_id()
	game.session.roster[client]={}
	if host:
		faculty._notify_classmate(client,ROOM,CLASS_ID,ACTOR,LONG_REPLY,true)
		if not await until(func():return not faculty.speech_player.cached.is_empty() and faculty.speech_routes.is_empty(),"remote-only synthesis and chunk sends"):return
		assert(not faculty.speech_player.active.has(CHANNEL) and not faculty.speech_player.subtitles.has(CHANNEL),"A remote private reply must remain silent and hidden on the host while its presentation clock stays authoritative.")
		var wav: AudioStreamWAV=faculty.speech_player.cached.values()[0]
		assert(game.host_openai.starts==2,"The long response has exactly two voice renders.")
		bus.announce.rpc_id(client,1,Transfer.digest(wav.data))
		if not await until(func():return bus.acknowledged>=1,"identical delivered PCM"):return
		faculty.pause_voice_target({"student":ACTOR,"room":ROOM,"class_id":CLASS_ID})
		bus.announce.rpc_id(client,2)
		if not await until(func():return bus.acknowledged>=2,"remote pause"):return
		faculty.resume_voice_channel(CHANNEL,ROOM);bus.announce.rpc_id(client,3)
		if not await until(func():return bus.acknowledged>=3,"remote resume"):return
		game.host_openai.held=true
		faculty._notify_classmate(client,ROOM,CLASS_ID,ACTOR,"This cancelled reply must never play.",true)
		if not await until(func():return game.host_openai.starts>=3,"cancelled request started"):return
		faculty.speech_synth.cancel(CHANNEL);game.host_openai.held=false
		for frame in 8:await process_frame
		bus.announce.rpc_id(client,4)
		if not await until(func():return bus.acknowledged>=4,"cancelled late result rejected"):return
		game.host_openai.held=true
		faculty._notify_classmate(client,ROOM,CLASS_ID,ACTOR,"This previous session reply must never play.",true)
		if not await until(func():return game.host_openai.starts>=4,"old session request started"):return
		faculty.character_epoch+=1;game.host_openai.held=false
		for frame in 8:await process_frame
		bus.announce.rpc_id(client,5)
		if not await until(func():return bus.acknowledged>=5,"stale session rejected"):return
		faculty._voice_cancel(CHANNEL,1);faculty._voice_cancel.rpc_id(client,CHANNEL,1)
		game.host_openai.clip_bytes=960000;game.host_openai.fail_tail=true
		faculty._notify_classmate(client,ROOM,CLASS_ID,ACTOR,LONG_REPLY+" The next turn preserves its first part if the remainder fails.",true)
		if not await until(func():return faculty.deferred_failure_observed and faculty.speech_routes.is_empty(),"tail failure waits for in-flight prefix transfer"):return
		var prefix: AudioStreamWAV=faculty.speech_player.presentations[CHANNEL].item.stream
		bus.announce.rpc_id(client,6,Transfer.digest(prefix.data))
		if not await until(func():return bus.acknowledged>=6,"failed tail preserves delivered first part"):return
		print("SPEECH_AUDIO_HOST PASS (segmented private voice, identical PCM, interruption, cancellation, session guard, deferred failure)")
	else:
		if not await until(func():return bus.stage>=1 and faculty.speech_player.active.has(CHANNEL),"first actual audio"):return
		var player: AudioStreamPlayer3D=faculty.speech_player.active[CHANNEL].player
		var item: Dictionary=faculty.speech_player.active[CHANNEL].item
		assert(item.segment_count==2 and item.segments.size()==2)
		var combined: PackedByteArray=item.segments[0].stream.data.duplicate();combined.append_array(item.segments[1].stream.data)
		assert(Transfer.digest(combined)==bus.checksum and item.segment_index==0)
		assert(faculty.speech_player.active[CHANNEL].serial==1)
		bus.acknowledge.rpc_id(1,1)
		if not await until(func():return bus.stage>=2 and faculty.speech_player.has_suspended(CHANNEL),"pause"):return
		assert(not faculty.speech_player.active.has(CHANNEL));bus.acknowledge.rpc_id(1,2)
		if not await until(func():return bus.stage>=3 and faculty.speech_player.active.has(CHANNEL),"resume"):return
		assert(faculty.speech_player.active[CHANNEL].player==player and not faculty.speech_player.has_suspended(CHANNEL));bus.acknowledge.rpc_id(1,3)
		if not await until(func():return bus.stage>=4,"cancellation"):return
		assert(not faculty.speech_player.has_utterance(CHANNEL,2) and faculty.speech_player.active[CHANNEL].serial==1)
		bus.acknowledge.rpc_id(1,4)
		if not await until(func():return bus.stage>=5,"old session"):return
		assert(not faculty.speech_player.has_utterance(CHANNEL,3) and faculty.pending_voice.is_empty())
		bus.acknowledge.rpc_id(1,5)
		if not await until(func():return bus.stage>=6 and faculty.speech_player.active.has(CHANNEL) and int(faculty.speech_player.active[CHANNEL].serial)==4,"prefix audio after tail failure"):return
		var partial: Dictionary=faculty.speech_player.active[CHANNEL].item
		assert(partial.segment_index==0 and partial.segments.size()==1 and partial.segments_closed)
		assert(Transfer.digest(partial.stream.data)==bus.checksum and faculty.pending_voice.is_empty(),"The entire first part must arrive before failure clears the transfer.")
		faculty.speech_player._finished(CHANNEL,4)
		assert(not faculty.speech_player.active.has(CHANNEL) and faculty.speech_player.subtitles[CHANNEL].item.text==Synth.speech_parts(LONG_REPLY+" The next turn preserves its first part if the remainder fails.")[1])
		bus.acknowledge.rpc_id(1,6)
		await create_timer(.15).timeout
		print("SPEECH_AUDIO_CLIENT PASS (segmented private voice, identical PCM, interruption, cancellation, session guard, deferred failure)")
	network.close();game.queue_free();bus.queue_free();await process_frame;await process_frame
	# Let AudioServer consume stopped playback cleanup before process teardown.
	await create_timer(.12).timeout
	quit()
