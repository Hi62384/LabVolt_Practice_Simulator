extends SceneTree
## Safe isolated fixture; run only when the memory admission guard permits Godot.
const Physical=preload("res://scripts/campus/academics/classroom_events/physical_round.gd")
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
class Lab:
 extends RefCounted
 var powered:=true
 var revision:=7
 var readings:={"fault":"","voltmeters":[12.0,0.0,0.0]}
class Session:
 var roster:={1:{},2:{}}
 var online:=false
 var labs:=[Lab.new()]
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice",2:"bob"}
 var random:=RandomNumberGenerator.new()
class Classes:
 var classes:={"ac_lab":{"id":"lab-1","phase":"lesson","kind":"lab","deadline":300.0,"course":"ELM253","week":1,"difficulty":0,"teacher":"dr_volts","students":{"alice":{"peer":1,"done":false,"bench":0},"bob":{"peer":2,"done":false,"bench":0}}}}
 var inside:={1:true,2:true}
 func _inside(peer: int,_room: String) -> bool:return inside.get(peer,false)
class Game:
 extends Node
 var session:=Session.new()
 var school:=School.new()
 var lecture_classes:=Classes.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=Game.new();root.add_child(game)
 var lab: Lab=game.session.labs[0]
 var round:=Physical.new()
 assert(round.prepare_live(true,"round",lab,0,130.0,["alice","bob"]))
 assert(round.snapshot("alice",101.0).question.options.size()==3)
 assert(not round.snapshot("alice",101.0).has("reveal"))
 assert(round.submit(true,"bob","round","not-a-choice",102.0)=="invalid")
 assert(round.submit(true,"bob","wrong","0",102.0)=="not_participating")
 assert(round.submit(true,"bob","round","0",102.0)=="accepted")
 assert(round.submit(true,"bob","round","0",103.0)=="already_submitted")
 assert(not round.observe_live(true,lab))
 assert(round.reveal().is_empty())
 lab.revision+=1;lab.readings.voltmeters[0]=18.0
 assert(round.observe_live(true,lab))
 assert(not round.observe_live(true,lab))
 assert(round.reveal().is_empty())
 lab.powered=false;lab.revision+=1
 assert(not round.observe_live(true,lab))
 assert(not round.snapshot("alice",103.0).measurement_changed)
 lab.powered=true;lab.revision+=1
 assert(round.observe_live(true,lab))
 assert(round.finish(true))
 assert(round.result("bob").correct and round.reveal().answer=="Increase")
 assert(not str(round.reveal()).contains("bob"))
 var service:=Service.new();root.add_child(service);service.configure(game)
 lab.powered=false
 assert(not service.start("ac_lab",100.0,[],"physical"))
 assert(service.lifecycle.reservations.is_empty())
 lab.powered=true
 assert(service.start("ac_lab",100.0,[],"physical"))
 var id: String=service.rooms.ac_lab.round.event_id
 assert(service.lifecycle.reservations["ac_lab:ac_station_0"]==id)
 assert(not service.note_disruption("ac_lab","wrong teacher",100.0))
 assert(service.note_disruption("ac_lab","dr_volts",100.0))
 assert(service.view(1,"ac_lab",101.0).has("class_notice"))
 assert(not service.note_disruption("ac_lab","dr_volts",101.0))
 assert(not service.view(1,"ac_lab",107.0).has("class_notice"))
 assert(service.perform(2,"ac_lab","lab-1",id,"submit","2",101.0)=="accepted")
 assert(service.perform(2,"ac_lab","lab-1",id,"submit","2",102.0)=="already_submitted")
 assert(not service.view(1,"ac_lab",103.0).has("result"))
 game.lecture_classes.inside[2]=false;service.sync_roster("ac_lab",104.0)
 assert(service.perform(2,"ac_lab","lab-1",id,"submit","1",105.0)=="denied")
 game.lecture_classes.inside[2]=true;service.sync_roster("ac_lab",106.0)
 lab.revision+=1;lab.readings.voltmeters[0]=18.1
 service.tick(107.0)
 assert(service.view(1,"ac_lab",108.0).measurement_changed)
 assert(not service.view(1,"ac_lab",108.0).has("reveal"))
 game.lecture_classes.classes.ac_lab.phase="assignment";service.tick(109.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.ac_lab.phase="lesson"
 assert(service.start("ac_lab",110.0,[],"physical"))
 lab.powered=false;lab.revision+=1;lab.readings.fault="SOURCE SHORT"
 service.tick(111.0)
 service.tick(140.0)
 assert(service.view(1,"ac_lab",140.0).reveal.fault=="SOURCE SHORT")
 assert(service.lifecycle.reservations.is_empty())
 service.tick(150.0)
 assert(service.rooms.is_empty())
 print("CLASSROOM_PHYSICAL PASS")
 service.queue_free();game.queue_free();quit(0)
