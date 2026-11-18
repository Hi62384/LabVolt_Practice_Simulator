extends SceneTree
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
const Bar=preload("res://scripts/campus/facilities/gym_barbells.gd")
class TestBar extends Bar:
	func _publish() -> void:pass
class Session:
	var roster:={1:{},2:{}}
	var poses:={2:{"position":Vector3(-7.4,0,32)}}
	var online:=false
class Player:
	var global_position:=Bar.PLATE_RACK
class School:
	func ground_drop_position(position: Vector3,_peer: int) -> Vector3:return position
class Controller:
	var host=Rules.new()
class Facilities:
	var controller=Controller.new()
class Services:
	var facilities=Facilities.new()
class Game extends Node:
	var session=Session.new();var player=Player.new();var school=School.new();var campus_services=Services.new()
var profile=Rules.empty_profile()
var now:=1000
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var gear=TestBar.new();root.add_child(gear);gear.set_process(false);gear.game=Game.new();gear._reset_plates()
	gear._build_belt_rack()
	var storage: Node3D=gear.get_node_or_null("BeltStorage")
	check(storage!=null and storage.find_children("*","CollisionShape3D",true,false).size()>=3,"belt rack lacks solid supports")
	for i in range(1,gear.belts.size()):check(gear.belts[i].position.distance_to(gear.belts[i-1].position)>=.5,"stored belts overlap")
	var id:=0;var lb: float=gear.plates[id].lb
	gear._accept_plate(1,"pickup",id,"",0)
	gear.game.player.global_position=Bar.BELT_RACK
	gear._accept_plate(1,"belt_attach",id,"belt/0",0)
	var expected: float=Bar.BELT_KG+lb*Bar.LB_TO_KG
	check(gear.plates[id].where=="attached" and is_equal_approx(gear.belt_mass(0),expected),"plate attachment or mass incorrect")
	gear._accept_belt(1,"pickup",0)
	gear._accept_belt(1,"wear",0)
	check(gear.worn_belt(1)==0 and is_equal_approx(gear.worn_belt_mass(1),expected),"worn belt lost load")
	gear._accept_plate(2,"belt_detach",-1,"belt/0",0)
	check(gear.plates[id].station=="belt/0","plate removed from worn belt")
	gear._accept_belt(1,"pickup",1);gear._accept_belt(1,"wear",1)
	check(gear.belts[1].where=="held" and gear.worn_belt(1)==0,"second belt equipped")
	gear._accept_belt(1,"stow",1)
	var host=Rules.new();host.authority=func():return true;host.clock=func():return now
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(_id):return profile.duplicate(true)
	host.commit_profile=func(_id,_d,p):profile=p.duplicate(true);return true
	host.worn_belt_mass=gear.worn_belt_mass
	host.anchors["gym/pullup"]={"kind":"pullup","room_id":"gym","position":Vector3.ZERO}
	var result=host.act(1,{"op":"start","station":"gym/pullup","exercise":"pullup","weight":0,"sequence":1})
	check(result.ok and is_equal_approx(float(host.active.get(1,{}).get("weight",0)),expected),"belt did not affect bodyweight exercise")
	gear._accept_belt(1,"unwear",0);gear._accept_belt(1,"drop",0)
	check(gear.belts[0].where=="floor" and gear.plates[id].station=="belt/0" and is_equal_approx(gear.belt_mass(0),expected),"drop lost attached plate")
	gear.game.player.global_position=gear.belts[0].position
	gear._accept_plate(1,"belt_detach",-1,"belt/0",0)
	check(gear.held_plate(1)==id and is_equal_approx(gear.belt_mass(0),Bar.BELT_KG),"detachment did not restore same plate")
	for failure in failures:push_error(failure)
	print("WEIGHT_BELT ","PASS" if failures.is_empty() else "FAIL")
	host.worn_belt_mass=Callable();host.authority=Callable();host.clock=Callable();host.context=Callable();host.load_profile=Callable();host.commit_profile=Callable();host.active.clear();host.seats.clear()
	gear.game.free();gear.free();quit(0 if failures.is_empty() else 1)
