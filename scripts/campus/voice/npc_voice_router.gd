extends Node
## Explicitly enabled proximity voice turns use the same authoritative character queue as text.
const Targeting=preload("res://scripts/campus/voice/conversation_targeting.gd")
const TeacherAI=preload("res://scripts/campus/academics/teacher_ai.gd")
const MAX_AUDIO_BYTES:=5760000
const CHUNK_BYTES:=12000
var game: Node
var faculty: Node
var microphone: Node
var live_bridge: Node
var current: Dictionary={}
var turn: Dictionary={}
var local_token:=0
var remote_turns: Dictionary={}
var transfers: Dictionary={}
var last_requests: Dictionary={}
var cooldown_until:=0
var refresh:=0.0
var diagnostic: Dictionary={"target":"","reason":"NPC recognition is disabled.","state":"off","last_error":"","segments":0}

func build(owner: Node, owner_faculty: Node) -> void:
 game=owner;faculty=owner_faculty
 microphone=preload("res://scripts/campus/voice/microphone_capture.gd").shared(self)
 microphone.speech_started.connect(_speech_started)
 microphone.speech_segment.connect(_speech_segment)
 microphone.packet_ready.connect(_packet)
 game.session.leaving.connect(clear_session)
 live_bridge=preload("res://scripts/campus/voice/npc_live_conversation.gd").new();live_bridge.name="LiveConversation";add_child(live_bridge);live_bridge.build(game,faculty,self)

func _submission_permitted() -> bool:
 if not is_instance_valid(game) or not is_instance_valid(game.get("voice_chat")):return false
 var prefs: Dictionary=game.client_preferences.values
 if not prefs.get("teacher_automatic_conversation",false) or prefs.get("microphone_muted",false) or prefs.get("microphone_mode","push_to_talk")=="muted":return false
 if not game.front.in_game or game.front.screen.visible or not game.player.enabled or game.player.chat_typing or not get_window().has_focus():return false
 var focus:=get_viewport().gui_get_focus_owner()
 if focus is LineEdit or focus is TextEdit:return false
 if is_instance_valid(game.get("smartphones")) and game.smartphones.comm.local_call.get("state","")=="active":return false
 return true

func _permitted() -> bool:
 return _submission_permitted() and game.voice_chat.talking

func _process(delta: float) -> void:
 refresh+=delta
 if refresh<.2:return
 refresh=0.0
 var now:=Time.get_ticks_msec()
 for key in transfers.keys():
  if now-int(transfers[key].started)>180000:transfers.erase(key)
 if multiplayer.is_server():
  for peer in remote_turns.keys():
   if not game.session.roster.has(peer) or not faculty.voice_target_valid(peer,remote_turns[peer].target) or now-int(remote_turns[peer].started)>300000:_cancel_host(int(peer),str(remote_turns[peer].token))
 if not _permitted():
  # Releasing PTT ends the recorded turn but preserves the conversational target.
  var cancelled:=not _submission_permitted()
  if cancelled and (not current.is_empty() or not turn.is_empty()):cancel_current()
  return
 if not current.is_empty() and not faculty.voice_target_valid(multiplayer.get_unique_id(),current):cancel_current()
 if current.is_empty():diagnostic.state="ready"

func _choose() -> Dictionary:
 var eye: Vector3=game.player.eyes.global_position
 var forward: Vector3=-game.player.eyes.global_basis.z
 var candidates: Array=faculty.voice_candidates(multiplayer.get_unique_id())
 var humans: Array=[]
 for peer in game.session.roster:
  if int(peer)==multiplayer.get_unique_id():continue
  var point: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
  if point.is_finite():humans.append(point+Vector3.UP*1.5)
 return Targeting.select(candidates,eye,forward,str(current.get("id","")),humans)

func force_target(target: Dictionary) -> bool:
 if not game.client_preferences.values.get("teacher_automatic_conversation",false):return false
 if not faculty.voice_target_valid(multiplayer.get_unique_id(),target):return false
 current=target.duplicate();_show_target()
 return true

func _speech_started(turn_id: int) -> void:
 if not _permitted() or faculty.recording or Time.get_ticks_msec()<cooldown_until:return
 var prefs: Dictionary=game.client_preferences.values
 if prefs.get("microphone_mode","")=="voice_activation" and prefs.get("microphone_echo_mode","speaker_protection")=="speaker_protection" and faculty.any_voice_playing() and not game.player.down("voice"):
  diagnostic.reason="Speaker protection: hold push-to-talk or use headphones to interrupt."
  return
 var selected:=_choose()
 if selected.is_empty():diagnostic.reason="No clearly addressed NPC in hearing range.";return
 if str(current.get("id",""))!=str(selected.id) and not current.is_empty():cancel_current()
 current=selected;local_token+=1
 var token:="%d:%d:%d"%[multiplayer.get_unique_id(),Time.get_ticks_msec(),local_token]
 turn={"id":turn_id,"token":token,"target":current.duplicate(),"audio":PackedByteArray(),"index":0,"started":Time.get_ticks_msec(),"speech_ms":0,"interrupted":false}
 remote_turns[multiplayer.get_unique_id()]={"token":token,"target":current.duplicate(),"started":Time.get_ticks_msec(),"input_finished":false}
 diagnostic.state="listening";diagnostic.reason=str(selected.get("reason",""));_show_target()
 if multiplayer.is_server():_begin_host(multiplayer.get_unique_id(),token,current)
 elif game.session.online:_begin.rpc_id(1,token,current)
 turn.live=live_bridge.begin_turn(token,current)

func _packet(pcm: PackedByteArray, activity: Dictionary) -> void:
 if is_instance_valid(live_bridge):live_bridge.feed_packet(pcm)
 if turn.is_empty() or not _permitted():return
 if activity.get("speech",false):turn.speech_ms=int(turn.speech_ms)+20
 if int(turn.speech_ms)>=400 and not turn.interrupted and game.client_preferences.values.get("npc_interruptions",true):
  turn.interrupted=true
  faculty.pause_voice_target(current)
  if multiplayer.is_server():_interrupt_host(multiplayer.get_unique_id(),str(turn.token))
  elif game.session.online:_interrupt.rpc_id(1,str(turn.token))

func _speech_segment(pcm: PackedByteArray, final: bool, turn_id: int, index: int) -> void:
 if turn.is_empty() or int(turn.id)!=turn_id:return
 if not _submission_permitted():cancel_current();return
 if turn.get("live",false):
  if final:
   live_bridge.finish_turn(str(turn.token));turn.clear();diagnostic.state="waiting"
  return
 if index!=int(turn.index):_error("A microphone segment was lost. Please repeat your question.");cancel_current();return
 turn.index=index+1
 if turn.audio.size()+pcm.size()>MAX_AUDIO_BYTES:
  _error("That question exceeded three minutes. Please pause and ask it in parts.");cancel_current();return
 turn.audio.append_array(pcm);diagnostic.segments=index+1
 if not final:return
 var completed:=turn.duplicate(true);turn.clear()
 if completed.audio.size()<4800:
  faculty.resume_voice_target(completed.target);return
 if not faculty.voice_target_valid(multiplayer.get_unique_id(),completed.target):cancel_current();return
 var wav:=TeacherAI.wav_16k(completed.audio)
 diagnostic.state="waiting"
 if multiplayer.is_server():_deliver(multiplayer.get_unique_id(),str(completed.token),wav)
 elif game.session.online:_send_recording(str(completed.token),wav)

func _send_recording(token: String,wav: PackedByteArray) -> void:
 _upload_begin.rpc_id(1,token,wav.size())
 for offset in range(0,wav.size(),CHUNK_BYTES):
  if not game.session.online or not _submission_permitted() or not is_current(multiplayer.get_unique_id(),token):
   cancel_current();return
  _upload_chunk.rpc_id(1,token,offset,wav.slice(offset,offset+CHUNK_BYTES))
  if offset%(CHUNK_BYTES*8)==0:await get_tree().process_frame

func _show_target() -> void:
 diagnostic.target=str(current.get("name",""))
 faculty.voice_room=str(current.get("room",""));faculty.voice_student=str(current.get("student",""));faculty.voice_class=str(current.get("class_id",""))
 if is_instance_valid(faculty.voice_hint):faculty.voice_hint.text="Speaking with "+str(current.get("name",""));faculty.voice_hint.show()

func cancel_current() -> void:
 var token:=str(remote_turns.get(multiplayer.get_unique_id(),{}).get("token",turn.get("token","")))
 if is_instance_valid(live_bridge):live_bridge.cancel_local(token)
 if not current.is_empty():faculty.resume_voice_target(current)
 if multiplayer.is_server():_cancel_host(multiplayer.get_unique_id(),token)
 elif game.session.online:_cancel.rpc_id(1,token)
 turn.clear();current.clear();remote_turns.erase(multiplayer.get_unique_id());microphone.reset_turn()
 faculty.voice_room="";faculty.voice_class="";faculty.voice_student=""
 if is_instance_valid(faculty.voice_hint):faculty.voice_hint.hide()
 diagnostic.state="ready";diagnostic.target=""

func is_current(peer: int,token: String) -> bool:
 var state: Dictionary=remote_turns.get(peer,{})
 return not state.is_empty() and str(state.token)==token and faculty.voice_target_valid(peer,state.target)

@rpc("any_peer","call_remote","reliable",10)
func _begin(token: String,target: Dictionary) -> void:
 if multiplayer.is_server():_begin_host(multiplayer.get_remote_sender_id(),token,target)
func _begin_host(peer: int,token: String,target: Dictionary) -> void:
 if not game.session.roster.has(peer) or token.length()>100 or target.size()>16 or not faculty.voice_target_valid(peer,target):return
 var now:=Time.get_ticks_msec()
 if now-int(last_requests.get(peer,-1000))<250:return
 last_requests[peer]=now
 remote_turns[peer]={"token":token,"target":target.duplicate(),"started":now,"input_finished":false}
 faculty.attend_voice_target(peer,target)

@rpc("any_peer","call_remote","reliable",10)
func _interrupt(token: String) -> void:
 if multiplayer.is_server():_interrupt_host(multiplayer.get_remote_sender_id(),token)
func _interrupt_host(peer: int,token: String) -> void:
 if not is_current(peer,token):return
 faculty.pause_voice_target(remote_turns[peer].target)

@rpc("any_peer","call_remote","reliable",10)
func _upload_begin(token: String,total: int) -> void:
 var peer:=multiplayer.get_remote_sender_id()
 if not multiplayer.is_server() or not is_current(peer,token) or total<4844 or total>MAX_AUDIO_BYTES+44:return
 transfers[peer]={"token":token,"total":total,"data":PackedByteArray(),"started":Time.get_ticks_msec()}
@rpc("any_peer","call_remote","reliable",10)
func _upload_chunk(token: String,offset: int,chunk: PackedByteArray) -> void:
 var peer:=multiplayer.get_remote_sender_id()
 if not multiplayer.is_server() or not is_current(peer,token) or not transfers.has(peer):return
 var upload: Dictionary=transfers[peer]
 if str(upload.token)!=token or chunk.is_empty() or chunk.size()>CHUNK_BYTES or offset!=upload.data.size() or offset+chunk.size()>int(upload.total):return
 upload.data.append_array(chunk)
 if upload.data.size()==int(upload.total):
  transfers.erase(peer)
  _deliver(peer,token,upload.data)

func _deliver(peer: int,token: String,wav: PackedByteArray) -> void:
 if not multiplayer.is_server() or not is_current(peer,token):return
 mark_input_finished(peer,token)
 var state: Dictionary=remote_turns[peer]
 faculty.accept_voice_turn(peer,state.target,wav,{"token":token})

func mark_input_finished(peer: int,token: String) -> void:
 if remote_turns.has(peer) and str(remote_turns[peer].token)==token:remote_turns[peer].input_finished=true

func addressed_speech_active(peer: int) -> bool:
 var state: Dictionary=remote_turns.get(peer,{})
 return not state.is_empty() and not state.get("input_finished",false) and Time.get_ticks_msec()-int(state.started)<=180000 and is_current(peer,str(state.token))

@rpc("any_peer","call_remote","reliable",10)
func _cancel(token: String) -> void:
 if multiplayer.is_server():_cancel_host(multiplayer.get_remote_sender_id(),token)
func _cancel_host(peer: int,token: String) -> void:
 if not remote_turns.has(peer) or (not token.is_empty() and remote_turns[peer].token!=token):return
 faculty.resume_voice_target(remote_turns[peer].target)
 remote_turns.erase(peer);transfers.erase(peer)

func _error(message: String) -> void:
 diagnostic.last_error=message
 if is_instance_valid(faculty.voice_hint):faculty.voice_hint.text=message;faculty.voice_hint.show()

func clear_session() -> void:
 if is_instance_valid(live_bridge):live_bridge.clear_session()
 turn.clear();current.clear();remote_turns.clear();transfers.clear();last_requests.clear()
 if is_instance_valid(microphone):microphone.reset_turn()

func _exit_tree() -> void:
 clear_session()
