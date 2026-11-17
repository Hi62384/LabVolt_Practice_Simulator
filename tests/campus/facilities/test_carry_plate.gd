extends SceneTree
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
const Bar=preload("res://scripts/campus/facilities/gym_barbells.gd")
class TestBar extends Bar:
	func _publish() -> void:pass
class Session:
	var roster:={1:{},2:{}}
	var poses:={2:{"position":Vector3(-8.35,0,33)}}
	var online:=false
class Player:
	var global_position:=Vector3(-8.35,0,33)
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
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var bar=TestBar.new();root.add_child(bar);bar.set_process(false);bar.game=Game.new();bar._reset_plates()
	var id:=0;var station:="gym/benchpress";var lb: float=bar.plates[id].lb
	bar._accept_plate(1,"pickup",id,"",0)
	check(bar.held_plate(1)==id and bar.plates[id].where=="held","rack pickup failed")
	bar._accept_plate(2,"pickup",id,"",0)
	check(bar.held_plate(2)<0 and bar.plates[id].owner==1,"another player took a held plate")
	bar._accept_plate(1,"stow",id,"",0);bar._accept_plate(1,"equip",id,"",0)
	check(bar.held_plate(1)==id,"stow/equip failed")
	bar.game.player.global_position=Bar.POSITIONS[station]
	bar._accept_plate(1,"attach",id,station,-1)
	check(bar.held_plate(1)<0 and bar.plates[id].where=="attached" and bar.plates[id].station==station,"attachment did not transfer plate")
	check(is_equal_approx(bar.mass(station),Bar.BAR_KG+lb*Bar.LB_TO_KG),"attached mass wrong")
	bar._accept_plate(1,"detach",-1,station,-1)
	check(bar.held_plate(1)==id and is_equal_approx(bar.mass(station),Bar.BAR_KG),"detachment did not return the same plate")
	var aimed_floor: Vector3=Bar.POSITIONS[station]+Vector3(.45,0,.35)
	bar._accept_plate(1,"drop",id,"",0,Vector3.INF)
	check(bar.held_plate(1)==id,"non-finite placement was accepted")
	bar._accept_plate(2,"drop",id,"",0,aimed_floor)
	check(bar.held_plate(1)==id,"non-owner placed a held plate")
	bar._accept_plate(1,"drop",id,"",0,aimed_floor)
	check(bar.plates[id].where=="floor" and bar.plates[id].owner==0 and bar.plates[id].position==aimed_floor,"aimed floor placement failed")
	bar.game.session.poses[2].position=bar.plates[id].position
	bar._accept_plate(2,"pickup",id,"",0)
	check(bar.held_plate(2)==id,"another player could not take placed plate")
	bar.game.session.poses[2].position=Bar.PLATE_RACK
	bar._accept_plate(2,"return",id,"",0)
	check(bar.plates[id].where=="rack" and bar.plates[id].owner==0,"return failed")
	for failure in failures:push_error(failure)
	print("CARRY_PLATE ","PASS" if failures.is_empty() else "FAIL")
	bar.game.free();bar.free();quit(0 if failures.is_empty() else 1)
