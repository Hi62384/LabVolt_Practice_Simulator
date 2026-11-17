extends SceneTree
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
class Session:
 var roster:={1:{},2:{}}
 var online:=false
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice",2:"bob"}
 var random:=RandomNumberGenerator.new()
class Classes:
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":300.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}}
 var present:={1:true,2:true,3:true}
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
 assert(service.perform(1,"room","class-1",id,"hand",true,101.0)=="accepted")
 assert(service.perform(1,"room","class-1",id,"decline",true,101.1)=="invalid")
 assert(service.perform(1,"room","class-1",id,"decline",null,101.2)=="accepted")
 assert(service.rooms.room.hands.hands.is_empty())
 assert(service.view(1,"room",102.0).declined and not service.view(1,"room",102.0).can_submit)
 assert(not service.view(1,"room",102.0).get("can_hint",false))
 assert(not service.view(2,"room",102.0).declined and service.view(2,"room",102.0).can_submit)
 assert(service.perform(1,"room","class-1",id,"decline",null,103.0)=="already_declined")
 assert(service.perform(1,"room","class-1",id,"hint",null,104.0)=="declined")
 assert(service.perform(1,"room","class-1",id,"submit","0",105.0)=="declined")
 assert(service.rooms.room.round.submissions.is_empty())
 game.session.roster.erase(1);game.school.identities.erase(1);service.sync_roster("room",106.0)
 game.session.roster[3]={};game.school.identities[3]="alice"
 service.sync_roster("room",107.0)
 assert(service.view(3,"room",107.0).declined)
 assert(service.perform(3,"room","class-1",id,"submit","0",108.0)=="declined")
 game.lecture_classes.classes.room.phase="assignment"
 assert(service.perform(2,"room","class-1",id,"submit","0",108.5)=="denied")
 service.tick(109.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.id="class-2";game.lecture_classes.classes.room.phase="lesson"
 game.lecture_classes.classes.room.students.alice.peer=3
 assert(service.start("room",120.0,[],"practice"))
 assert(not service.view(3,"room",121.0).declined and service.view(3,"room",121.0).can_submit)
 service.queue_free();game.queue_free()
 print("CLASSROOM_OPT_OUT PASS")
 quit()
