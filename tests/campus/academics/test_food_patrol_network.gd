extends SceneTree
const Faculty=preload("res://scripts/campus/academics/faculty.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
class Session:
 var online:=true
 var roster:={}
 var multiplayer_api: MultiplayerAPI
 func peer_connected_now(id: int) -> bool:return id in multiplayer_api.get_peers()
class Game:
 extends Node
 var session:=Session.new()
var faculty: Node3D
var game:=Game.new()
var deadline: int
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var host:=OS.get_cmdline_user_args()[0]=="host"
 var peer:=ENetMultiplayerPeer.new()
 var error:=peer.create_server(26329,1) if host else peer.create_client("127.0.0.1",26329)
 if error!=OK:push_error("Could not create test peer");quit(1);return
 root.multiplayer.multiplayer_peer=peer
 var world:=Node3D.new();world.name="TestWorld";root.add_child(world)
 faculty=Faculty.new();faculty.name="Faculty";world.add_child(faculty);faculty.set_process(false)
 faculty.game=game;game.session.multiplayer_api=root.multiplayer
 faculty.lunch=Toon.build(Roster.config("ms_lunch"));faculty.add_child(faculty.lunch)
 faculty.lunch.position=faculty.lunch_patrol.position
 deadline=Time.get_ticks_msec()+25000
 if host:print("PATROL_HOST_READY")
 while Time.get_ticks_msec()<deadline and root.multiplayer.get_peers().is_empty():await create_timer(.05).timeout
 if root.multiplayer.get_peers().is_empty():push_error("Test peer did not connect");quit(1);return
 if host:
  game.session.roster[1]={};game.session.roster[root.multiplayer.get_peers()[0]]={}
  faculty.lunch_patrol.pause=0.0
  for i in 100:
   faculty._update_food_patrol(.05)
   await create_timer(.05).timeout
  print("PATROL_HOST PASS")
 else:
  var initial: Vector3=faculty.lunch.position
  while Time.get_ticks_msec()<deadline and faculty.lunch_remote.distance_to(initial)<.5:
   faculty._update_food_patrol(.05)
   await create_timer(.05).timeout
  if faculty.lunch_remote.distance_to(initial)<.5:push_error("No patrol movement received");quit(1);return
  for i in 20:
   faculty._update_food_patrol(.05)
   await create_timer(.05).timeout
  if faculty.lunch.position.distance_to(faculty.lunch_remote)>.5:push_error("Client model did not follow host");quit(1);return
  if faculty.lunch.find_child("Head",true,false)==null:push_error("Teacher model missing");quit(1);return
  print("PATROL_CLIENT PASS")
 world.queue_free();game.free();peer.close()
 await process_frame
 quit(0)
