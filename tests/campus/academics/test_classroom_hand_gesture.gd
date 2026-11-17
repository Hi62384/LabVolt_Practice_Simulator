extends SceneTree
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
const Avatar=preload("res://scripts/avatar_model.gd")
class Session:
 var roster:={1:{},2:{}}
 var online:=false
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice",2:"bob"}
 var random:=RandomNumberGenerator.new()
class Classes:
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":300.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}}
 var present:={1:true,2:true}
 func _inside(peer: int,_room: String) -> bool:return present.get(peer,false)
class Game:
 extends Node
 var session:=Session.new()
 var school:=School.new()
 var lecture_classes:=Classes.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=Game.new();root.add_child(game)
 var service:=Service.new();root.add_child(service);service.configure(game)
 assert(service.start("room",100.0,[],"practice"))
 var id: String=service.rooms.room.round.event_id
 assert(service.perform(2,"room","class-1",id,"hand",true,101.0)=="accepted")
 assert(service.view(1,"room",101.0).raised_peers==[2])
 assert(service.view(2,"room",101.0).hands.raised)
 var model:=Node3D.new();var arm:=Node3D.new();arm.name="ArmR";model.add_child(arm);root.add_child(model)
 Avatar.raise_hand(model,true,.1)
 assert(arm.rotation.z>1.0)
 assert(service.perform(2,"room","class-1",id,"hand",false,102.0)=="accepted")
 assert(service.view(1,"room",102.0).raised_peers.is_empty())
 Avatar.raise_hand(model,false,1.0)
 assert(arm.rotation.is_equal_approx(Vector3.ZERO))
 var fallback:=Avatar.build(FileAccess.get_file_as_bytes("res://assets/default_avatar.glb"))
 assert(is_instance_valid(fallback));root.add_child(fallback)
 var fallback_arm:=fallback.find_child("ArmR",true,false) as Node3D
 assert(is_instance_valid(fallback_arm))
 Avatar.animate(fallback,false)
 Avatar.raise_hand(fallback,true,1.0)
 assert(fallback_arm.rotation.z>1.0)
 Avatar.raise_hand(fallback,false,1.0)
 fallback.queue_free()
 assert(service.perform(2,"room","class-1",id,"hand",true,103.0)=="accepted")
 game.lecture_classes.present[2]=false;service.sync_roster("room",104.0)
 assert(service.view(1,"room",104.0).raised_peers.is_empty())
 game.lecture_classes.classes.room.phase="assignment";service.tick(105.0)
 assert(service.rooms.is_empty())
 model.queue_free();service.queue_free();game.queue_free()
 print("CLASSROOM_HAND_GESTURE PASS")
 quit(0)
