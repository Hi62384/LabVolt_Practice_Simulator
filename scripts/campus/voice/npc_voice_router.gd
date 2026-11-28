extends Node
## Explicitly enabled proximity voice turns use the same authoritative character queue as text.
const Targeting=preload("res://scripts/campus/voice/conversation_targeting.gd")
const TeacherAI=preload("res://scripts/campus/academics/teacher_ai.gd")
const MAX_AUDIO_BYTES:=5760000
const CHUNK_BYTES:=12000
var game: Node
var faculty: Node
var microphone: Node
var current: Dictionary={}
var turn: Dictionary={}
var local_token:=0
var remote_turns: Dictionary={}
var transfers: Dictionary={}
var last_requests: Dictionary={}
var cooldown_until:=0
var refresh:=0.0
var capture_enabled:=false
var interrupt_key_held:=false
var diagnostic: Dictionary={"target":"","reason":"NPC recognition is disabled.","state":"off","last_error":"","segments":0}

func build(owner: Node, owner_faculty: Node) -> void:
 game=owner;faculty=owner_faculty
 microphone=preload("res://scripts/campus/voice/microphone_capture.gd").shared(self)
 microphone.speech_started.connect(_speech_started)
 microphone.speech_segment.connect(_speech_segment)
 microphone.packet_ready.connect(_packet)
 game.session.leaving.connect(clear_session)

func _submission_permitted() -> bool:
 if not is_instance_valid(game):return false
 var prefs: Dictionary=game.client_preferences.values
 if not prefs.get("teacher_automatic_conversation",false) or prefs.get("microphone_muted",false) or prefs.get("microphone_mode","push_to_talk")=="muted":return false
 if not game.front.in_game or game.front.screen.visible or not game.player.enabled or game.player.chat_typing or not get_window().has_focus():return false
 var focus:=get_viewport().gui_get_focus_owner()
 if focus is LineEdit or focus is TextEdit:return false
 if is_instance_valid(game.get("smartphones")) and game.smartphones.comm.local_call.get("state","")=="active":return false
 return true

func _permitted() -> bool:
 if not _submission_permitted():return false
 var mode:=str(game.client_preferences.values.get("microphone_mode","push_to_talk"))
 return mode=="voice_activation" or (mode=="push_to_talk" and game.player.down("voice"))

func _process(delta: float) -> void:
 if not is_instance_valid(microphone) or not is_instance_valid(game):return
 var capture_requested:=_permitted()
 if capture_requested!=capture_enabled:
  if capture_enabled and not capture_requested and _submission_permitted() and game.client_preferences.values.get("microphone_mode","")=="push_to_talk":microphone.finish_turn()
  capture_enabled=capture_requested
  microphone.subscribe("npc_conversation",capture_enabled)
  if capture_enabled and turn.is_empty():microphone.reset_turn()
 if capture_enabled and not microphone.is_active():
  if not current.is_empty() or not turn.is_empty():cancel_current()
  diagnostic.state="microphone_unavailable";diagnostic.reason=str(microphone.diagnostic.get("reason","Microphone capture stopped."))
  return
 var interrupt_pressed: bool=game.player.down("voice")
 if capture_requested and interrupt_pressed and not interrupt_key_held and turn.is_empty():
  # Speaker protection may already be ignoring an echo-triggered VAD turn.
  # An explicit key press starts a fresh local onset, so interruption can work
  # before the NPC finishes speaking and before a two-second silent gap.
  microphone.reset_turn()
 interrupt_key_held=interrupt_pressed
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
 if not turn.is_empty():return
 var prefs: Dictionary=game.client_preferences.values
 if prefs.get("microphone_mode","")=="voice_activation" and prefs.get("microphone_echo_mode","speaker_protection")=="speaker_protection" and faculty.any_voice_playing() and not game.player.down("voice"):
  diagnostic.reason="Speaker protection: hold push-to-talk or use headphones to interrupt."
  return
 var selected:=_choose()
 if selected.is_empty():
  diagnostic.reason=Targeting.rejection_reason(faculty.voice_candidates(multiplayer.get_unique_id()),game.player.eyes.global_position,-game.player.eyes.global_basis.z,str(current.get("id","")))
  return
 if str(current.get("id",""))!=str(selected.id) and not current.is_empty():cancel_current(false)
 current=selected;local_token+=1
 var token:="%d:%d:%d"%[multiplayer.get_unique_id(),Time.get_ticks_msec(),local_token]
 turn={"id":turn_id,"token":token,"target":current.duplicate(),"audio":PackedByteArray(),"index":0,"started":Time.get_ticks_msec(),"speech_ms":0,"interrupted":false}
 remote_turns[multiplayer.get_unique_id()]={"token":token,"target":current.duplicate(),"started":Time.get_ticks_msec(),"input_finished":false}
 diagnostic.state="listening";diagnostic.last_error="";diagnostic.recorded_bytes=0;diagnostic.reason=str(selected.get("reason",""));_show_target()
 if multiplayer.is_server():_begin_host(multiplayer.get_unique_id(),token,current)
 elif game.session.online:_begin.rpc_id(1,token,current)

func _packet(_pcm: PackedByteArray, activity: Dictionary) -> void:
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
 if index!=int(turn.index):_error("A microphone segment was lost. Please repeat your question.");cancel_current();return
 turn.index=index+1
 if turn.audio.size()+pcm.size()>MAX_AUDIO_BYTES:
  _error("That question exceeded three minutes. Please pause and ask it in parts.");cancel_current();return
 turn.audio.append_array(pcm);diagnostic.segments=index+1
 if not final:return
 var completed:=turn.duplicate(true);turn.clear()
 if completed.audio.size()<4800:
  _finish_without_submission(str(completed.token),"The recorded utterance was too short. Please try again.");return
 if not faculty.voice_target_valid(multiplayer.get_unique_id(),completed.target):cancel_current();return
 var wav:=TeacherAI.wav_16k(completed.audio)
 diagnostic.state="transcribing";diagnostic.recorded_bytes=completed.audio.size();diagnostic.recording_completed_ms=Time.get_ticks_msec()
 if multiplayer.is_server():_deliver(multiplayer.get_unique_id(),str(completed.token),wav)
 elif game.session.online:_send_recording(str(completed.token),wav)

func _finish_without_submission(token: String,reason: String) -> void:
 if multiplayer.is_server():_cancel_host(multiplayer.get_unique_id(),token)
 elif game.session.online:_cancel.rpc_id(1,token)
 remote_turns.erase(multiplayer.get_unique_id())
 if not current.is_empty():faculty.resume_voice_target(current)
 diagnostic.state="ready";diagnostic.reason=reason

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

func cancel_current(reset_segment: bool=true) -> void:
 var token:=str(remote_turns.get(multiplayer.get_unique_id(),{}).get("token",turn.get("token","")))
 if not current.is_empty():faculty.resume_voice_target(current)
 if multiplayer.is_server():_cancel_host(multiplayer.get_unique_id(),token)
 elif game.session.online:_cancel.rpc_id(1,token)
 turn.clear();current.clear();remote_turns.erase(multiplayer.get_unique_id())
 if reset_segment:microphone.reset_turn()
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
 if not game.session.roster.has(peer) or token.is_empty() or token.length()>100 or target.size()>16 or not faculty.voice_target_valid(peer,target):return
 var now:=Time.get_ticks_msec()
 if now-int(last_requests.get(peer,-1000))<250:return
 last_requests[peer]=now
 var canonical: Dictionary={}
 for candidate in faculty.voice_candidates(peer):
  if str(candidate.get("id",""))==str(target.get("id","")) and str(candidate.get("class_id",""))==str(target.get("class_id","")) and str(candidate.get("student",""))==str(target.get("student","")):
   canonical=candidate.duplicate();break
 if canonical.is_empty():return
 remote_turns[peer]={"token":token,"target":canonical,"started":now,"input_finished":false}
 faculty.attend_voice_target(peer,canonical)

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
 report_stage(peer,{"token":token},"recording_submitted")
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

func report_stage(peer: int,context: Dictionary,stage: String,message: String="") -> void:
 if not multiplayer.is_server():return
 var token:=str(context.get("token",""))
 if token.is_empty() or not is_current(peer,token):return
 if peer==multiplayer.get_unique_id():_receive_stage(token,stage,message)
 elif game.session.online and game.session.peer_connected_now(peer):_receive_stage.rpc_id(peer,token,stage,message.left(500))

@rpc("authority","call_remote","reliable",10)
func _receive_stage(token: String,stage: String,message: String) -> void:
 if not is_current(multiplayer.get_unique_id(),token):return
 if stage not in ["recording_submitted","transcription_received","transcription_failed","response_generated","response_failed","intentional_silence","playback_started","playback_completed"]:return
 diagnostic.state=stage;diagnostic.last_stage_ms=Time.get_ticks_msec()
 if not message.is_empty():_error(message.left(500))

func _error(message: String) -> void:
 diagnostic.last_error=message
 if is_instance_valid(faculty.voice_hint):faculty.voice_hint.text=message;faculty.voice_hint.show()

func clear_session() -> void:
 turn.clear();current.clear();remote_turns.clear();transfers.clear();last_requests.clear()
 if is_instance_valid(microphone):
  microphone.subscribe("npc_conversation",false)
  microphone.reset_turn()
 capture_enabled=false;interrupt_key_held=false

func _exit_tree() -> void:
 clear_session()
 if is_instance_valid(microphone):
  if microphone.speech_started.is_connected(_speech_started):microphone.speech_started.disconnect(_speech_started)
  if microphone.speech_segment.is_connected(_speech_segment):microphone.speech_segment.disconnect(_speech_segment)
  if microphone.packet_ready.is_connected(_packet):microphone.packet_ready.disconnect(_packet)
