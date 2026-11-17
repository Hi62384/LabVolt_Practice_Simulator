extends SceneTree
## Lightweight ENet fixture: no campus scene, microphone, or saved profiles.
const Voice=preload("res://scripts/campus/voice/voice_chat.gd")
class Session:
 var roster:={}
class Game:
 extends Node
 var session:=Session.new()
var game:=Game.new()
var voice: Node3D
var deadline: int
func _initialize() -> void:call_deferred("run")
func wait_for(check: Callable,label: String) -> bool:
 while Time.get_ticks_msec()<deadline:
  if check.call():return true
  await create_timer(.05).timeout
 push_error("SENSITIVITY NETWORK TIMEOUT "+label+" status="+str(root.multiplayer.multiplayer_peer.get_connection_status())+" peers="+str(root.multiplayer.get_peers()))
 return false
func run() -> void:
 var host:=OS.get_cmdline_user_args()[0]=="host"
 var peer:=ENetMultiplayerPeer.new()
 var error:=peer.create_server(26339,1) if host else peer.create_client("127.0.0.1",26339)
 if error!=OK:push_error("Could not create test peer");quit(1);return
 root.multiplayer.multiplayer_peer=peer
 var world:=Node3D.new();world.name="TestWorld";root.add_child(world)
 voice=Voice.new();voice.name="VoiceChat";world.add_child(voice);voice.set_process(false);voice.game=game
 deadline=Time.get_ticks_msec()+25000
 if host:print("SENSITIVITY_HOST_READY")
 if not await wait_for(func():return not root.multiplayer.get_peers().is_empty(),"peer connection"):quit(1);return
 if host:
  var other: int=root.multiplayer.get_peers()[0]
  game.session.roster[other]={}
  if not await wait_for(func():return voice.teacher_sensitivity.has(other),"sensitivity update"):quit(1);return
  if not is_equal_approx(float(voice.teacher_sensitivity[other]),2.0):push_error("Host failed to clamp sensitivity");quit(1);return
  game.session.roster.erase(other);voice._prune()
  if voice.teacher_sensitivity.has(other):push_error("Disconnected sensitivity retained");quit(1);return
  print("SENSITIVITY_HOST PASS")
 else:
  await create_timer(.5).timeout
  voice._set_teacher_sensitivity.rpc_id(1,100.0)
  await create_timer(1.0).timeout
  print("SENSITIVITY_CLIENT PASS")
 world.queue_free();game.free();peer.close();await process_frame;quit(0)
