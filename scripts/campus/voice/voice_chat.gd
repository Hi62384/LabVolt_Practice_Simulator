extends Node3D
## Push-to-talk capture is active only while the bound key is held.
## PCM is relayed by the host, bounded and routed to nearby players only.
const SAMPLE_RATE:=16000
const PACKET_SECONDS:=0.02
const MAX_RANGE:=24.0
var game: Node
var capture: AudioEffectCapture
var mic: AudioStreamPlayer
var talking:=false
var last_packet:={}
var remotes:={}
var badge: Label
var refresh:=0.0
var call_players:={}
var call_last:={}
const MIC_ICON=preload("res://assets/campus/ui/microphone.svg")
var teacher_sound=preload("res://scripts/campus/voice/teacher_sound_activity.gd").new()
var teacher_sensitivity:={}
var sensitivity_refresh:=0.0

func build(owner_game: Node) -> void:
 game=owner_game
 var bus:=AudioServer.get_bus_index("VoiceCapture")
 if bus<0:
  AudioServer.add_bus();bus=AudioServer.bus_count-1;AudioServer.set_bus_name(bus,"VoiceCapture")
  AudioServer.set_bus_send(bus,"Master");AudioServer.set_bus_volume_db(bus,-80.0)
  capture=AudioEffectCapture.new();capture.buffer_length=.3;AudioServer.add_bus_effect(bus,capture)
 else:
  for i in AudioServer.get_bus_effect_count(bus):
   if AudioServer.get_bus_effect(bus,i) is AudioEffectCapture:capture=AudioServer.get_bus_effect(bus,i)
 if capture==null:
  capture=AudioEffectCapture.new();AudioServer.add_bus_effect(bus,capture)
 mic=AudioStreamPlayer.new();mic.bus="VoiceCapture";mic.stream=AudioStreamMicrophone.new();add_child(mic)
 var layer:=CanvasLayer.new();layer.layer=33;add_child(layer)
 var badge_row:=HBoxContainer.new();badge_row.position=Vector2(16,244);layer.add_child(badge_row)
 var mic_icon:=TextureRect.new();mic_icon.texture=MIC_ICON;mic_icon.custom_minimum_size=Vector2(22,22);mic_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;mic_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;badge_row.add_child(mic_icon)
 badge=Label.new();badge.text="MIC";badge.add_theme_font_size_override("font_size",16);badge.add_theme_color_override("font_color",Color("9cebd0"));badge.add_theme_color_override("font_outline_color",Color("102a33"));badge.add_theme_constant_override("outline_size",5);badge_row.hide();badge_row.add_child(badge)
 game.session.roster_changed.connect(_prune)
 game.session.leaving.connect(_stop)
 game.session.leaving.connect(_clear_call_players)
 game.smartphones.comm.changed.connect(_sync_call_state)

func _process(delta: float) -> void:
 if not is_instance_valid(game) or not is_instance_valid(game.front):return
 var on_call: bool=is_instance_valid(game.get("smartphones")) and game.smartphones.comm.local_call.get("state","")=="active"
 var focus:=get_viewport().gui_get_focus_owner()
 var active: bool=game.front.in_game and get_window().has_focus() and (game.player.enabled or on_call) and not game.player.chat_typing and not (focus is LineEdit or focus is TextEdit) and not game.front.screen.visible and (Input.mouse_mode==Input.MOUSE_MODE_CAPTURED or on_call) and game.player.down("voice")
 if active!=talking:
  talking=active
  if talking:capture.clear_buffer();mic.play()
  else:_stop()
 badge.get_parent().visible=talking
 _sync_call_state()
 if talking:
  sensitivity_refresh-=delta
  if sensitivity_refresh<=0.0:
   sensitivity_refresh=2.0
   var sensitivity: float=clampf(float(game.client_preferences.values.get("teacher_mic_sensitivity",1.0)),.5,2.0)
   if multiplayer.is_server():teacher_sensitivity[multiplayer.get_unique_id()]=sensitivity
   elif game.session.online:_set_teacher_sensitivity.rpc_id(1,sensitivity)
  _capture_audio()
 refresh+=delta
 if refresh<.1:return
 refresh=0.0
 for peer in remotes.keys():
  _position_speaker(peer,remotes[peer].player)
 for peer in remotes.keys()+call_last.keys():
  var avatar: Node3D=game.avatars.get(peer)
  if not is_instance_valid(avatar):continue
  var icon: Sprite3D=avatar.get_node_or_null("VoiceIndicator")
  if icon==null:
   icon=Sprite3D.new();icon.name="VoiceIndicator";icon.texture=MIC_ICON;icon.pixel_size=.0035;icon.billboard=BaseMaterial3D.BILLBOARD_ENABLED;icon.position.y=2.30;avatar.add_child(icon)
  var proximity_last:=int(remotes.get(peer,{}).get("last",0))
  icon.visible=Time.get_ticks_msec()-maxi(proximity_last,int(call_last.get(peer,0)))<350

func _capture_audio() -> void:
 var input_rate:=AudioServer.get_mix_rate()
 var count:=int(input_rate*PACKET_SECONDS)
 if capture.get_frames_available()<count:return
 var frames:=capture.get_buffer(count)
 var output_count:=int(SAMPLE_RATE*PACKET_SECONDS)
 var packet:=PackedByteArray();packet.resize(output_count*2)
 for i in output_count:
  var index:=mini(frames.size()-1,int(float(i)*float(frames.size())/float(output_count)))
  var sample: float=clampf((frames[index].x+frames[index].y)*.5,-1.0,1.0)
  packet.encode_s16(i*2,roundi(sample*32767.0))
 var detect: bool=bool(game.client_preferences.values.get("teacher_mic_detection",true))
 if not game.session.online:
  if detect and multiplayer.is_server():_observe_teacher_sound(multiplayer.get_unique_id(),packet)
  return
 if multiplayer.is_server():_relay(multiplayer.get_unique_id(),packet,detect)
 else:_submit.rpc_id(1,packet,detect)

@rpc("any_peer","call_remote","unreliable_ordered",9)
func _submit(packet: PackedByteArray,detect: bool=true) -> void:
 if multiplayer.is_server():_relay(multiplayer.get_remote_sender_id(),packet,detect)

func _relay(peer: int,packet: PackedByteArray,detect: bool=true) -> void:
 if not game.session.roster.has(peer) or packet.size()!=int(SAMPLE_RATE*PACKET_SECONDS)*2:return
 if not detect:teacher_sound.forget(peer)
 var now:=Time.get_ticks_msec()
 if now-int(last_packet.get(peer,-1000))<10:return
 last_packet[peer]=now
 var source: Vector3=_position(peer)
 if not source.is_finite():return
 if detect:_observe_teacher_sound(peer,packet)
 for target in game.session.roster:
  if int(target)==peer:continue
  if is_instance_valid(game.get("smartphones")) and game.smartphones.comm.connected(peer,int(target)):
   if int(target)==multiplayer.get_unique_id():_play_call_packet(peer,packet)
   elif game.session.peer_connected_now(int(target)):_receive_call.rpc_id(int(target),peer,packet)
   continue
  var destination: Vector3=_position(int(target))
  if not destination.is_finite() or source.distance_squared_to(destination)>MAX_RANGE*MAX_RANGE:continue
  if int(target)==multiplayer.get_unique_id():_play_packet(peer,packet)
  elif game.session.peer_connected_now(int(target)):_receive.rpc_id(int(target),peer,packet)

@rpc("authority","call_remote","unreliable_ordered",9)
func _receive(peer: int,packet: PackedByteArray) -> void:
 if multiplayer.get_remote_sender_id()!=1 or not game.session.roster.has(peer) or packet.size()!=int(SAMPLE_RATE*PACKET_SECONDS)*2:return
 _play_packet(peer,packet)

@rpc("authority","call_remote","unreliable_ordered",9)
func _receive_call(peer: int,packet: PackedByteArray) -> void:
 if multiplayer.get_remote_sender_id()!=1 or not game.session.roster.has(peer) or packet.size()!=int(SAMPLE_RATE*PACKET_SECONDS)*2:return
 if game.smartphones.comm.local_call.get("state","")!="active" or int(game.smartphones.comm.local_call.get("peer",0))!=peer:return
 _play_call_packet(peer,packet)

func _play_call_packet(peer: int,packet: PackedByteArray) -> void:
 call_last[peer]=Time.get_ticks_msec()
 if not call_players.has(peer):
  var stream:=AudioStreamGenerator.new();stream.mix_rate=SAMPLE_RATE;stream.buffer_length=.3
  var player:=AudioStreamPlayer.new();player.stream=stream;add_child(player);player.play();call_players[peer]=player
 var playback: AudioStreamGeneratorPlayback=call_players[peer].get_stream_playback()
 if playback==null:return
 var count:=int(packet.size()/2)
 if not playback.can_push_buffer(count):playback.clear_buffer()
 var frames:=PackedVector2Array();frames.resize(count)
 for i in count:
  var sample: float=float(packet.decode_s16(i*2))/32768.0;frames[i]=Vector2(sample,sample)
 playback.push_buffer(frames)

func _position(peer: int) -> Vector3:
 if peer==multiplayer.get_unique_id():return game.player.global_position
 return game.session.poses.get(peer,{}).get("position",Vector3.INF)

func _play_packet(peer: int,packet: PackedByteArray) -> void:
 if not remotes.has(peer):_create_remote(peer)
 var voice: Dictionary=remotes[peer];voice.last=Time.get_ticks_msec()
 var playback: AudioStreamGeneratorPlayback=voice.player.get_stream_playback()
 if playback==null:return
 var count:=int(packet.size()/2)
 if not playback.can_push_buffer(count):playback.clear_buffer()
 var frames:=PackedVector2Array();frames.resize(count)
 for i in count:
  var sample:=float(packet.decode_s16(i*2))/32768.0
  frames[i]=Vector2(sample,sample)
 playback.push_buffer(frames)

func _create_remote(peer: int) -> void:
 var stream:=AudioStreamGenerator.new();stream.mix_rate=SAMPLE_RATE;stream.buffer_length=.3
 var player:=AudioStreamPlayer3D.new()
 player.stream=stream
 player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
 player.volume_db=-63.0
 player.max_distance=MAX_RANGE
 add_child(player)
 _position_speaker(peer,player)
 player.play()
 remotes[peer]={"player":player,"last":0}

func _position_speaker(peer: int,speaker: AudioStreamPlayer3D) -> void:
 var point: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
 if not point.is_finite():
  speaker.volume_db=-63.0
  return
 speaker.global_position=point+Vector3.UP*1.6
 var distance:=point.distance_to(game.player.global_position)
 var level:=minf(1.0,5.0/maxf(5.0,distance))*(1.0-smoothstep(MAX_RANGE*.7,MAX_RANGE,distance))
 speaker.volume_db=linear_to_db(maxf(.001,level))-3.0

func _stop() -> void:
 talking=false
 sensitivity_refresh=0.0
 var peer:=multiplayer.multiplayer_peer
 if peer!=null and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED and multiplayer.is_server():
  teacher_sound.forget(multiplayer.get_unique_id())
 if is_instance_valid(mic):mic.stop()
 if capture!=null:capture.clear_buffer()
 if is_instance_valid(badge):badge.get_parent().hide()
func _clear_call_players() -> void:
 for player in call_players.values():
  if is_instance_valid(player):player.queue_free()
 call_players.clear()
 call_last.clear()
 teacher_sound.state.clear()
 teacher_sensitivity.clear()
 _refresh_call_indicators()
func _sync_call_state() -> void:
 if not is_instance_valid(game) or not is_instance_valid(game.get("smartphones")):return
 var call: Dictionary=game.smartphones.comm.local_call
 var active_peer:=int(call.get("peer",0)) if call.get("state","")=="active" else 0
 for peer in call_players.keys():
  if int(peer)!=active_peer:
   if is_instance_valid(call_players[peer]):call_players[peer].stop();call_players[peer].queue_free()
   call_players.erase(peer)
   call_last.erase(peer)
 _refresh_call_indicators()
func _refresh_call_indicators() -> void:
 if not is_instance_valid(game):return
 for peer in game.avatars.keys():
  var avatar: Node3D=game.avatars.get(peer)
  if not is_instance_valid(avatar):continue
  var icon: Sprite3D=avatar.get_node_or_null("VoiceIndicator")
  if icon!=null:icon.visible=Time.get_ticks_msec()-maxi(int(remotes.get(peer,{}).get("last",0)),int(call_last.get(peer,0)))<350
func _prune() -> void:
 for peer in teacher_sound.state.keys():
  if not game.session.roster.has(peer):teacher_sound.forget(peer)
 for peer in last_packet.keys():
  if not game.session.roster.has(peer):last_packet.erase(peer)
 for peer in teacher_sensitivity.keys():
  if not game.session.roster.has(peer):teacher_sensitivity.erase(peer)
 for peer in call_players.keys():
  if not game.session.roster.has(peer):call_players[peer].queue_free();call_players.erase(peer);call_last.erase(peer)
 for peer in remotes.keys():
  if not game.session.roster.has(peer):
   var data: Dictionary=remotes[peer]
   if is_instance_valid(data.player):data.player.queue_free()
   remotes.erase(peer)
   last_packet.erase(peer)

func _observe_teacher_sound(peer: int,packet: PackedByteArray) -> void:
 if peer!=multiplayer.get_unique_id():
  var last_poses: Variant=game.session.get("last_pose")
  if last_poses is Dictionary and (not last_poses.has(peer) or int(last_poses[peer])<=0 or Time.get_ticks_msec()-int(last_poses[peer])>3000):
   teacher_sound.forget(peer)
   return
 var strength: float=teacher_sound.observe(peer,packet,Time.get_ticks_msec(),float(teacher_sensitivity.get(peer,1.0)))
 if strength<=0.0 or not is_instance_valid(game.get("faculty")):return
 var point:=_position(peer)
 if not point.is_finite():return
 var room: String=game.campus.registry.locate(point)
 game.faculty.report_event(peer,room,"voice_noise",point,strength)

@rpc("any_peer","call_remote","reliable")
func _set_teacher_sensitivity(value: float) -> void:
 var peer:=multiplayer.get_remote_sender_id()
 if not multiplayer.is_server() or not game.session.roster.has(peer) or not is_finite(value):return
 teacher_sensitivity[peer]=clampf(value,.5,2.0)
func _exit_tree() -> void:
 _stop()
 var capture_bus:=AudioServer.get_bus_index("VoiceCapture")
 if capture_bus>0:AudioServer.remove_bus(capture_bus)
