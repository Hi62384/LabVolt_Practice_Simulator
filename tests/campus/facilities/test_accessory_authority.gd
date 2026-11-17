extends SceneTree

class Belt:
	func worn_belt(_peer: int) -> int:return 0
class Game extends Node:
	var gym_barbells=Belt.new()

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var coordinator=preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not coordinator.load_catalog():
		push_error("Catalog unavailable");quit(1);return
	var ids:=["accessory.head.campus_cap","accessory.ears.orbit_hoops","accessory.neck.prism_pendant","accessory.face.round_study"]
	var profile:={"owned_cosmetics":ids,"avatar_cosmetics":{"version":1,"body":{},"equipped":{}}}
	for i in 3:
		var definition: Dictionary=coordinator.catalog[ids[i]]
		profile.avatar_cosmetics.equipped[definition.slot]={"id":ids[i],"parameters":{}}
	var game:=Game.new();root.add_child(game)
	var network=preload("res://scripts/inventory_authority/network.gd").new();root.add_child(network);network.set_process(false);network.game=game
	network.ledger.bindings[1]="player"
	network.ledger.state.accounts["player"]={"profile":profile}
	var equip:={"op":"avatar_cosmetic","args":[{"op":"equip","id":ids[3],"parameters":{}}]}
	if network._accessory_change_allowed(1,equip):
		push_error("Host accepted a fifth accessory while a belt was worn");quit(1);return
	var unequip:={"op":"avatar_cosmetic","args":[{"op":"unequip","slot":"head"}]}
	if not network._accessory_change_allowed(1,unequip):
		push_error("Host blocked removal of a worn accessory");quit(1);return
	print("ACCESSORY_AUTHORITY PASS")
	quit(0)
