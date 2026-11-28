extends Node
## Opt-in microphone routing to host-owned GPT-Live sessions. CharacterMind is
## the only answer authority; the transport releases only transcript-checked PCM.
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const Classmates=preload("res://scripts/campus/academics/classroom_students.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const VoiceDelivery=preload("res://scripts/campus/academics/character_voice_delivery.gd")
const SAMPLE_RATE:=16000
const PACKET_BYTES:=2560 # 80 ms, after the shared microphone's C# processing.
const PRE_ROLL_BYTES:=10240
const MAX_PENDING_BYTES:=SAMPLE_RATE*2*8
const MAX_TURN_BYTES:=SAMPLE_RATE*2*180
var game: Node
var faculty: Node
var router: Node
var sessions: Dictionary={}
var _reasoning_actors: Dictionary={}
var offered:=false
var offered_model:=""
var diagnostic:={"provider":"openai_live","state":"off","last_error":"","active_sessions":0,"guarded_playback":true}
var _local_token:=""
var _sequence:=0
var _pre_roll:=PackedByteArray()
var _outgoing:=PackedByteArray()
var _generation:=0
var _refresh:=0.0
var _packet_clock:=0.0
var _offer_signature:=""

func build(owner: Node,owner_faculty: Node,natural_router: Node) -> void:
	game=owner;faculty=owner_faculty;router=natural_router
	game.session.roster_changed.connect(_roster_changed)
	game.session.leaving.connect(clear_session)
	game.session.restarted.connect(clear_session)
	_publish_offer()

func enabled() -> bool:
	if not is_instance_valid(game):return false
	return bool(game.host_openai.live_enabled) if multiplayer.is_server() else offered

func begin_turn(token: String,target: Dictionary) -> bool:
	# True also means "selected but unavailable". Never turn a Live failure into
	# an unrequested STT request or a replacement voice.
	if not enabled():return false
	if not router._permitted():return true
	_local_token=token;_sequence=0;_outgoing=_pre_roll.duplicate();_pre_roll.clear()
	diagnostic.state="connecting"
	if multiplayer.is_server():_begin_host(multiplayer.get_unique_id(),token,target)
	elif game.session.online:_begin.rpc_id(1,token,target)
	else:_notice("Live conversation needs the connected host.")
	return true

func feed_packet(pcm: PackedByteArray) -> void:
	if not enabled() or not router._permitted():
		_pre_roll.clear();_outgoing.clear()
		return
	if pcm.is_empty() or pcm.size()%2 or pcm.size()>PACKET_BYTES:return
	if _local_token.is_empty():
		_pre_roll.append_array(pcm)
		if _pre_roll.size()>PRE_ROLL_BYTES:_pre_roll=_pre_roll.slice(_pre_roll.size()-PRE_ROLL_BYTES)
		return
	_outgoing.append_array(pcm)
	while _outgoing.size()>=PACKET_BYTES:_flush_packet(PACKET_BYTES)

func finish_turn(token: String) -> void:
	if token!=_local_token:return
	if not _outgoing.is_empty():_flush_packet(_outgoing.size())
	_local_token="";_pre_roll.clear()
	if multiplayer.is_server():_finish_host(multiplayer.get_unique_id(),token)
	elif game.session.online:_finish.rpc_id(1,token)
	diagnostic.state="waiting"

func cancel_local(token: String="") -> void:
	_local_token="";_pre_roll.clear();_outgoing.clear()
	if not is_instance_valid(game):return
	if multiplayer.is_server():_cancel_host(multiplayer.get_unique_id(),token)
	elif game.session.online:_cancel.rpc_id(1,token)
	diagnostic.state="ready" if enabled() else "off"

func _flush_packet(length: int) -> void:
	var pcm:=_outgoing.slice(0,length);_outgoing=_outgoing.slice(length)
	if multiplayer.is_server():_audio_host(multiplayer.get_unique_id(),_local_token,_sequence,pcm)
	elif game.session.online:_audio.rpc_id(1,_local_token,_sequence,pcm)
	_sequence+=1

@rpc("any_peer","call_remote","reliable",10)
func _begin(token: String,target: Dictionary) -> void:
	if multiplayer.is_server():_begin_host(multiplayer.get_remote_sender_id(),token,target)

func _begin_host(peer: int,token: String,target: Dictionary) -> void:
	if not enabled() or token.is_empty() or token.length()>100 or target.size()>16 or not router.is_current(peer,token):return
	if not faculty.voice_target_valid(peer,target):return
	var person: Dictionary=Classmates.profile_for(str(target.get("student",""))) if not str(target.get("student","")).is_empty() else Characters.teacher(str(target.get("id","")))
	var delivery:=Characters.speech(person,str(game.host_openai.live_model),3)
	if not bool(delivery.get("ok",false)) or not Models.available_for(str(delivery.get("model","")),"live"):
		_error_for(peer,str(delivery.get("error","This character's approved model does not support Live. Choose a compatible model explicitly in Character Voices.")))
		return
	var identity:=JSON.stringify([target.get("id",""),target.get("class_id",""),delivery.get("voice"),delivery.get("voice_type"),delivery.get("model"),delivery.get("profile_version",0)])
	var previous: Dictionary=sessions.get(peer,{})
	if not previous.is_empty() and (str(previous.identity)!=identity or not is_instance_valid(previous.node) or previous.node.state in ["closing","closed"]):
		_drop(peer,"character_changed");previous={}
	if previous.is_empty():
		var context:={"summary":"You perform "+str(person.get("name","the addressed character"))+" in a teaching simulation. All answers and actions come only from the authoritative character backend.","history":[],"sample_rate":SAMPLE_RATE}
		var created: Dictionary=game.host_openai.create_live_conversation(context,delivery.get("voice",""),delivery)
		if not created.get("ok",false):_error_for(peer,str(created.get("error","Live conversation is unavailable.")));return
		_generation+=1
		previous={"node":created.session,"generation":_generation,"identity":identity,"last_user_at":Time.get_ticks_msec(),"answer_epoch":0}
		sessions[peer]=previous
		var generation:=_generation
		created.session.transcript_received.connect(func(speaker: String,delta: String,start: int,end: int):_transcript(peer,generation,speaker,delta,start,end))
		created.session.delegation_requested.connect(func(id: String,_history: Array):_delegation(peer,generation,id))
		created.session.audio_segment_ready.connect(func(pcm: PackedByteArray,text: String,_id: String):_verified_audio(peer,generation,pcm,text))
		created.session.failed.connect(func(details: Dictionary):_failed(peer,generation,details))
		created.session.closed.connect(func(summary: Dictionary):_closed(peer,generation,summary))
	else:previous.node.interrupt()
	previous.merge({"token":token,"target":target.duplicate(true),"delivery":delivery,"seq":0,"input_bytes":0,"pending_pcm":PackedByteArray(),"input_finished":false,"user_text":"","delegation":"","answer_started":false,"answer":{},"last_transcript":0,"transcript_floor_ms":previous.node.input_clock_ms(),"started":Time.get_ticks_msec(),"window_at":Time.get_ticks_msec(),"window_bytes":0,"answer_epoch":int(previous.answer_epoch)+1},true)
	previous.node.mute_input(false)
	diagnostic.active_sessions=sessions.size();diagnostic.state="listening"

@rpc("any_peer","call_remote","reliable",10)
func _audio(token: String,sequence: int,pcm: PackedByteArray) -> void:
	if multiplayer.is_server():_audio_host(multiplayer.get_remote_sender_id(),token,sequence,pcm)

func _audio_host(peer: int,token: String,sequence: int,pcm: PackedByteArray) -> void:
	if not sessions.has(peer):return
	var state: Dictionary=sessions[peer]
	if not _valid(peer,int(state.generation),int(state.answer_epoch),token):return
	if state.input_finished or pcm.is_empty() or pcm.size()%2 or pcm.size()>PACKET_BYTES or sequence!=int(state.seq):
		_error_for(peer,"The Live microphone stream was interrupted. Start a new voice turn.");_drop(peer,"invalid_audio");return
	var now:=Time.get_ticks_msec()
	if now-int(state.window_at)>=1000:state.window_at=now;state.window_bytes=0
	state.window_bytes=int(state.window_bytes)+pcm.size()
	state.input_bytes=int(state.input_bytes)+pcm.size()
	if int(state.window_bytes)>96000 or int(state.input_bytes)>MAX_TURN_BYTES or state.pending_pcm.size()+pcm.size()>MAX_PENDING_BYTES:
		_error_for(peer,"The Live microphone stream exceeded its bounded queue. Please pause and try again.");_drop(peer,"audio_budget");return
	state.seq=int(state.seq)+1;state.pending_pcm.append_array(pcm);state.last_user_at=now

@rpc("any_peer","call_remote","reliable",10)
func _finish(token: String) -> void:
	if multiplayer.is_server():_finish_host(multiplayer.get_remote_sender_id(),token)

func _finish_host(peer: int,token: String) -> void:
	if router.has_method("mark_input_finished"):router.mark_input_finished(peer,token)
	if not sessions.has(peer) or str(sessions[peer].token)!=token:return
	sessions[peer].input_finished=true

@rpc("any_peer","call_remote","reliable",10)
func _cancel(token: String) -> void:
	if multiplayer.is_server():_cancel_host(multiplayer.get_remote_sender_id(),token)

func _cancel_host(peer: int,token: String) -> void:
	if sessions.has(peer) and (token.is_empty() or str(sessions[peer].token)==token):_drop(peer,"player_canceled")

func _valid(peer: int,generation: int,epoch: int,token: String) -> bool:
	if not is_instance_valid(game) or not multiplayer.is_server() or not enabled() or not sessions.has(peer):return false
	var state: Dictionary=sessions[peer]
	if state.get("answer_started",false) and int(state.get("authority_epoch",-1))!=int(faculty.character_epoch):return false
	return int(state.generation)==generation and int(state.answer_epoch)==epoch and str(state.token)==token and is_instance_valid(state.node) and state.node.state not in ["closing","closed"] and router.is_current(peer,token) and faculty.voice_target_valid(peer,state.target)

func _transcript(peer: int,generation: int,speaker: String,delta: String,_start: int,end: int) -> void:
	if speaker!="user" or not sessions.has(peer) or int(sessions[peer].generation)!=generation:return
	var state: Dictionary=sessions[peer]
	if state.answer_started or end<=int(state.transcript_floor_ms):return
	state.user_text=str(state.user_text)+delta;state.last_transcript=Time.get_ticks_msec()
	if str(state.user_text).length()>8000:_error_for(peer,"That question exceeded the transcript budget. Please ask it in parts.");_drop(peer,"transcript_budget")

func _delegation(peer: int,generation: int,id: String) -> void:
	if not sessions.has(peer) or int(sessions[peer].generation)!=generation:return
	if not sessions[peer].answer_started:sessions[peer].delegation=id

func _answer(peer: int,generation: int,epoch: int,token: String) -> void:
	if not _valid(peer,generation,epoch,token):return
	# Loading the authoritative profile must happen before reserving this turn;
	# the profile loader correctly refuses to replace state while ai_busy is set.
	if faculty.has_method("_sync_character_profile") and not faculty._sync_character_profile():return
	if not _valid(peer,generation,epoch,token):return
	var state: Dictionary=sessions[peer]
	var actor:=str(state.target.id)
	if _reasoning_actors.has(actor):return
	var channel:="classmate:"+actor if not str(state.target.get("student","")).is_empty() else actor
	if faculty.ai_busy.has(peer) or faculty.ai_busy.size()>=3 or channel in faculty.question_channels.values():return
	var faculty_epoch:=int(faculty.character_epoch)
	state.authority_epoch=faculty_epoch
	var room:=str(state.target.get("room",""))
	faculty.ai_busy[peer]=room;faculty.question_channels[peer]=channel
	var job:=str(peer)+":"+str(generation)+":"+str(epoch)
	_reasoning_actors[actor]=job
	state.answer_started=true
	var guard:=func():return _valid(peer,generation,epoch,token) and int(faculty.character_epoch)==faculty_epoch
	var answer: Dictionary=await faculty.answer_live_delegation(peer,state.target,str(state.user_text).strip_edges(),guard)
	if _reasoning_actors.get(actor)==job:_reasoning_actors.erase(actor)
	if is_instance_valid(faculty) and int(faculty.character_epoch)==faculty_epoch and faculty.ai_busy.get(peer)==room and faculty.question_channels.get(peer)==channel:
		faculty.ai_busy.erase(peer);faculty.question_channels.erase(peer)
	if not guard.call():return
	if not answer.get("ok",false):
		if not answer.get("silent",false):_error_for(peer,str(answer.get("error","The character could not answer this turn.")))
		faculty.resume_voice_target(state.target);return
	var text:=str(answer.get("text",""))
	if text.strip_edges().is_empty():faculty.resume_voice_target(state.target);return
	state.answer=answer
	var delivery:=VoiceDelivery.for_text(answer.get("delivery",state.delivery),text)
	state.answer.delivery=delivery
	# Delivery may change emotion; permanent vocal identity remains immutable.
	if delivery.get("voice",state.delivery.voice)!=state.delivery.voice or str(delivery.get("model",state.delivery.model))!=str(state.delivery.model):
		_error_for(peer,"The character voice changed during this turn. Start a new turn to use the explicitly approved identity.");_drop(peer,"identity_changed");return
	var styled: bool=state.node.apply_delivery(str(delivery.get("instructions","")),str(state.delegation))
	if not styled or not state.node.submit_delegation(str(state.delegation),text):
		faculty.present_live_voice(peer,state.target,text,null,guard,delivery,answer.get("presentation",{}))
		state.answer={};_error_for(peer,"Live could not accept this response's bounded performance instructions. Its validated text remains available.")

func _verified_audio(peer: int,generation: int,pcm: PackedByteArray,text: String) -> void:
	if not sessions.has(peer) or int(sessions[peer].generation)!=generation:return
	var state: Dictionary=sessions[peer]
	var epoch:=int(state.answer_epoch);var token:=str(state.token)
	var guard:=func():return _valid(peer,generation,epoch,token)
	if not guard.call() or state.answer.is_empty() or str(state.answer.get("text",""))!=text:return
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=SAMPLE_RATE;stream.stereo=false;stream.data=pcm
	faculty.present_live_voice(peer,state.target,text,stream,guard,state.answer.get("delivery",state.delivery),state.answer.get("presentation",{}))
	state.answer={};diagnostic.state="ready"

func _failed(peer: int,generation: int,details: Dictionary) -> void:
	if not sessions.has(peer) or int(sessions[peer].generation)!=generation:return
	var state: Dictionary=sessions[peer]
	var epoch:=int(state.answer_epoch);var token:=str(state.token)
	var guard:=func():return _valid(peer,generation,epoch,token)
	if guard.call() and not state.answer.is_empty():
		faculty.present_live_voice(peer,state.target,str(state.answer.get("text","")),null,guard,state.answer.get("delivery",state.delivery),state.answer.get("presentation",{}))
		state.answer={}
	_error_for(peer,str(details.get("error","Live conversation failed.")))
	faculty.resume_voice_target(state.target)

func _closed(peer: int,generation: int,_summary: Dictionary) -> void:
	if not sessions.has(peer) or int(sessions[peer].generation)!=generation:return
	var target: Dictionary=sessions[peer].target
	sessions.erase(peer);diagnostic.active_sessions=sessions.size()
	faculty.resume_voice_target(target)

func _drop(peer: int,reason: String) -> void:
	if not sessions.has(peer):return
	var state: Dictionary=sessions[peer];sessions.erase(peer)
	if is_instance_valid(state.node):state.node.interrupt();state.node.close_session(reason)
	faculty.resume_voice_target(state.target)
	diagnostic.active_sessions=sessions.size()

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	_packet_clock+=delta;_refresh+=delta
	if not multiplayer.is_server():return
	if _packet_clock>=.08:
		_packet_clock=0.0
		for peer in sessions.keys():
			var state: Dictionary=sessions[peer]
			if not is_instance_valid(state.node) or state.node.state!="ready":continue
			for _batch in 2:
				if state.pending_pcm.is_empty():break
				var pcm: PackedByteArray=state.pending_pcm.slice(0,PACKET_BYTES)
				if not state.node.append_audio(pcm):break
				state.pending_pcm=state.pending_pcm.slice(pcm.size())
	if _refresh<.25:return
	_refresh=0.0;_publish_offer()
	var now:=Time.get_ticks_msec()
	for peer in sessions.keys():
		var state: Dictionary=sessions[peer]
		if not _valid(peer,int(state.generation),int(state.answer_epoch),str(state.token)) or now-int(state.last_user_at)>180000:
			_drop(peer,"idle_or_out_of_range");continue
		if state.input_finished and not state.answer_started and not str(state.delegation).is_empty() and not str(state.user_text).strip_edges().is_empty() and now-int(state.last_transcript)>=250:
			_answer(peer,int(state.generation),int(state.answer_epoch),str(state.token))

func _publish_offer(force:=false) -> void:
	if not is_instance_valid(game) or not multiplayer.is_server():return
	var active:=enabled();var choice:=str(game.host_openai.live_model)
	var signature:=str(active)+":"+choice
	if not force and signature==_offer_signature:return
	_offer_signature=signature;offered=active;offered_model=choice
	if game.session.online:
		for value in game.session.roster:
			var peer:=int(value)
			if peer!=multiplayer.get_unique_id() and game.session.peer_connected_now(peer):_offer.rpc_id(peer,active,choice)

@rpc("authority","call_remote","reliable",10)
func _offer(active: bool,choice: String) -> void:
	offered=active;offered_model=choice.left(100)
	if not active:cancel_local()

func _roster_changed() -> void:
	if multiplayer.is_server():
		for peer in sessions.keys():
			if not game.session.roster.has(peer):_drop(peer,"peer_left")
		_publish_offer(true)

func _error_for(peer: int,message: String) -> void:
	diagnostic.last_error=message;diagnostic.state="error"
	if peer==multiplayer.get_unique_id():_notice(message)
	elif game.session.online and game.session.peer_connected_now(peer):_notice.rpc_id(peer,message.left(500))

@rpc("authority","call_remote","reliable",10)
func _notice(message: String) -> void:
	diagnostic.last_error=message.left(500);diagnostic.state="error"
	if is_instance_valid(router):router._error(message.left(500))

func clear_session() -> void:
	for peer in sessions.keys():_drop(peer,"game_session_ended")
	_local_token="";_pre_roll.clear();_outgoing.clear();_offer_signature=""
	_reasoning_actors.clear()
	offered=false;offered_model=""

func _exit_tree() -> void:
	clear_session()
