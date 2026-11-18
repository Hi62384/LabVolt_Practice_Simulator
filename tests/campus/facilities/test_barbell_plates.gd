extends SceneTree
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
const Bar=preload("res://scripts/campus/facilities/gym_barbells.gd")
class TestBar extends Bar:
	func _publish() -> void:pass
class Session:
	var roster := {1:{}}
	var poses := {}
	var online := false
class Player:
	var global_position := Vector3(4,1.25,30.2)
class Controller:
	var held: int = bar.held_plate(1)
	var correct_rod := Bar.SIZES.find(float(bar.plates[held].lb))
	bar.game.player.global_position = Bar.PLATE_RACK
	bar._accept_plate(1,"return",held,"rod",(correct_rod+1)%Bar.SIZES.size())
	check(bar.held_plate(1)==held, "mismatched rod accepted a plate")
	bar._accept_plate(1,"return",held,"rod",correct_rod)
	check(bar.held_plate(1)<0 and bar._rack_count(correct_rod)==Bar.COUNTS[correct_rod], "matching rod did not return the plate")
	var host=Rules.new()
class Services:
	var facilities=Facilities.new()
class Facilities:
	var controller=Controller.new()
class Game extends Node:
	var session=Session.new()
	var player=Player.new()
	var campus_services=Services.new()
var profile=Rules.empty_profile()
var clock_value:=1000
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func load_plate(bar: Node,station: String,lb: float,side: int) -> void:
	var id:=-1
	for i in bar.plates.size():
		if bar.plates[i].where=="rack" and float(bar.plates[i].lb)==lb:id=i;break
	if id<0:failures.append("No rack plate available");return
	bar.game.player.global_position=Bar.PLATE_RACK
	bar._accept_plate(1,"pickup",id,"",0)
	bar.game.player.global_position=Bar.POSITIONS[station]
	bar._accept_plate(1,"attach",id,station,side)
	check(bar.plates[id].where=="attached","held plate did not attach")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var bar=TestBar.new();root.add_child(bar);bar.set_process(false);bar.game=Game.new();bar._reset_plates()
	var station:="gym/benchpress"
	bar._accept(1,"attach",station,45.0,-1)
	check(is_equal_approx(bar.mass(station),20.0),"legacy direct attach bypassed physical pickup")
	load_plate(bar,station,45.0,-1)
	load_plate(bar,station,10.0,-1)
	load_plate(bar,station,45.0,1)
	check(is_equal_approx(bar.mass(station),20.0+100.0*Bar.LB_TO_KG),"loaded mass was incorrect")
	bar._accept(1,"detach",station,0.0,-1)
	check(is_equal_approx(bar.mass(station),20.0+100.0*Bar.LB_TO_KG),"legacy direct detach bypassed physical handling")
	bar._accept_plate(1,"detach",-1,station,-1)
	check(is_equal_approx(bar.mass(station),20.0+90.0*Bar.LB_TO_KG) and bar.held_plate(1)>=0,"detached plate was not held")
	var remaining:=0
	for plate in bar.plates:
		if plate.station==station:remaining+=1
	check(remaining==2,"wrong number of attached plates")
	bar.game.campus_services.facilities.controller.host.seats[station]=1
	bar._accept_plate(1,"attach",bar.held_plate(1),station,1)
	check(is_equal_approx(bar.mass(station),20.0+90.0*Bar.LB_TO_KG),"occupied station accepted a plate")
	var host=Rules.new();host.authority=func():return true
	host.clock=func():return clock_value
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(_id):return profile.duplicate(true)
	host.commit_profile=func(_id,_d,p):profile=p.duplicate(true);return true
	host.anchors[station]={"kind":"benchpress","room_id":"gym","position":Vector3.ZERO}
	host.barbell_mass=bar.mass
	var result=host.act(1,{"op":"start","station":station,"exercise":"benchpress","weight":1,"sequence":1})
	check(result.ok and is_equal_approx(host.active.get(1,{}).get("weight",0),bar.mass(station)),"exercise did not use actual bar mass")
	for failure in failures:push_error(failure)
	print("BARBELL_PLATES ","PASS" if failures.is_empty() else "FAIL")
	bar.game.free();bar.free()
	quit(0 if failures.is_empty() else 1)
