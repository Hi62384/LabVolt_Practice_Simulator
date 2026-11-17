extends SceneTree
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
const Bar=preload("res://scripts/campus/facilities/gym_barbells.gd")
class TestBar extends Bar:
	func _publish() -> void:pass
class Session:
	var roster:={1:{},2:{}}
	var poses:={2:{"position":Vector3(4,1.25,30.2)}}
	var online:=false
class Player:
	var global_position:=Vector3(4,1.25,30.2)
class School:
	func ground_drop_position(position: Vector3,_peer: int) -> Vector3:return position
class Controller:
	var host=Rules.new()
class Facilities:
	var controller=Controller.new()
class Services:
	var facilities=Facilities.new()
class Game extends Node:
	var session=Session.new()
	var player=Player.new()
	var school=School.new()
	var campus_services=Services.new()
var failures: Array[String]=[]
var profile=Rules.empty_profile()
var now:=1000
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func load_plate(bar: Node,station: String,side: int) -> void:
	var id:=-1
	for i in bar.plates.size():
		if bar.plates[i].where=="rack" and float(bar.plates[i].lb)==45.0:id=i;break
	if id<0:failures.append("No plate available");return
	bar.game.player.global_position=Bar.PLATE_RACK
	bar._accept_plate(1,"pickup",id,"",0)
	bar.game.player.global_position=Bar.POSITIONS[station]
	bar._accept_plate(1,"attach",id,station,side)
	check(bar.plates[id].where=="attached","could not attach carried plate")
func run() -> void:
	var bar=TestBar.new();root.add_child(bar);bar.set_process(false);bar.game=Game.new();bar._reset_plates()
	var station:="gym/benchpress"
	load_plate(bar,station,-1);load_plate(bar,station,1)
	var weight: float=bar.loaded_mass(station)
	bar._accept(1,"pickup_bar",station,0,0)
	check(bar.held_bar(1)==station and is_equal_approx(bar.held_mass(1),weight) and bar.mass(station)==0,"pickup did not preserve load")
	bar._accept(2,"pickup_bar",station,0,0)
	check(bar.held_bar(2).is_empty(),"another player stole carried bar")
	bar._accept(1,"stow_bar",station,0,0)
	check(bar.bars[station].where=="stowed" and bar.held_bar(1).is_empty(),"stow failed")
	bar._accept(1,"equip_bar",station,0,0)
	check(bar.held_bar(1)==station,"equip failed")
	var host=Rules.new();host.authority=func():return true;host.clock=func():return now
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(_id):return profile.duplicate(true)
	host.commit_profile=func(_id,_d,p):profile=p.duplicate(true);return true
	host.held_barbell_mass=bar.held_mass
	var result=host.act(1,{"op":"start","station":"gym/barbell","exercise":"deadlift","weight":1,"sequence":1})
	check(result.ok and is_equal_approx(float(host.active.get(1,{}).get("weight",0)),weight),"portable exercise trusted client weight")
	bar._accept(1,"drop_bar",station,0,0)
	check(bar.bars[station].where=="floor" and bar.bars[station].owner==0 and is_equal_approx(bar.loaded_mass(station),weight),"floor placement lost bar or plates")
	bar._accept(2,"pickup_bar",station,0,0)
	check(bar.held_bar(2)==station,"other player could not pick up placed bar")
	bar._accept(2,"return_bar",station,0,0)
	check(bar.bars[station].where=="rack" and is_equal_approx(bar.mass(station),weight),"return did not restore loaded bar")
	for failure in failures:push_error(failure)
	print("CARRY_BARBELL ","PASS" if failures.is_empty() else "FAIL")
	host.held_barbell_mass=Callable();host.authority=Callable();host.clock=Callable();host.context=Callable();host.load_profile=Callable();host.commit_profile=Callable();host.active.clear();host.seats.clear()
	bar.game.free();bar.free();quit(0 if failures.is_empty() else 1)
