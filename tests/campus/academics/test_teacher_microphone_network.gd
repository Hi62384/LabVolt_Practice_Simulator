extends SceneTree
## Synthetic PCM only; no AudioStreamMicrophone is created or opened.
const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
class Session:
 var roster:={}
 var poses:={}
 var online:=true
 func peer_connected_now(_peer: int) -> bool:return true
class Registry:
 func locate(_point: Vector3) -> String:return "ac_lab"
class Campus:
 var registry:=Registry.new()
class Faculty extends Node:
 var calls:=0
 func report_event(_peer: int,_room: String,_kind: String,_position: Vector3,_strength: float) -> void:calls+=1
class Game extends Node:
 var session:=Session.new()
 var campus:=Campus.new()
 var player:=Node3D.new()
 var faculty:=Faculty.new()
 var smartphones: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func wait_for(check: Callable,label: String) -> bool:
 while Time.get_ticks_msec()<deadline:
  if check.call():return true
  await create_timer(.02).timeout
 push_error("MIC NETWORK TIMEOUT "+label);return false
func run() -> void:
 var host:=OS.get_cmdline_user_args()[0]=="host"
 var peer:=ENetMultiplayerPeer.new()
 var error:=peer.create_server(26369,1) if host else peer.create_client("127.0.0.1",26369)
 if error!=OK:quit(1);return
 root.multiplayer.multiplayer_peer=peer
 var world:=Node3D.new();world.name="TestWorld";root.add_child(world)
 var game:=Game.new();world.add_child(game);game.add_child(game.player);game.add_child(game.faculty)
 var voice:=Voice.new();voice.name="VoiceChat";world.add_child(voice);voice.set_process(false);voice.game=game
 deadline=Time.get_ticks_msec()+20000
 if host:print("MIC_NETWORK_HOST_READY")
 if not await wait_for(func():return not root.multiplayer.get_peers().is_empty(),"peer"):quit(1);return
 if host:
  var other: int=root.multiplayer.get_peers()[0]
  game.session.roster={1:{}};game.session.roster[other]={}
  game.session.poses={};game.session.poses[other]={"position":Vector3(1,0,0)}
  if not await wait_for(func():return voice.remotes.has(other),"voice while opted out"):quit(1);return
  if game.faculty.calls!=0 or voice.teacher_sound.state.has(other):push_error("Opted-out audio reached teacher detector");quit(1);return
  if not await wait_for(func():return game.faculty.calls>0,"teacher detection after opt in"):quit(1);return
  await create_timer(1.0).timeout
  print("MIC_NETWORK_HOST PASS")
 else:
  await create_timer(.5).timeout
  var packet:=PackedByteArray();packet.resize(640)
  for i in range(0,640,2):packet.encode_s16(i,6000)
  for i in 8:
   voice._submit.rpc_id(1,packet,false);await create_timer(.03).timeout
  await create_timer(.6).timeout
  for i in 8:
   voice._submit.rpc_id(1,packet,true);await create_timer(.03).timeout
  await create_timer(.5).timeout
  print("MIC_NETWORK_CLIENT PASS")
 peer.close();world.queue_free();await process_frame;await create_timer(.2).timeout;quit(0)
