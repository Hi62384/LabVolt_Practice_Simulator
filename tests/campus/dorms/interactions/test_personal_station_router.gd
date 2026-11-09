extends SceneTree

class Provider extends RefCounted:
	var rooms := {1:"dorm_01"}
	var identities := {1:"profile:alice"}
	var owners := {"dorm_01":"profile:alice","dorm_02":"profile:bob"}
	var revision := 1
	func room_for_peer(peer: int) -> String:return str(rooms.get(peer,""))
	func authenticated_identity(peer: int) -> String:return str(identities.get(peer,""))
	func owner_identity(room_id: String) -> String:return str(owners.get(room_id,""))
	func assignment_revision() -> int:return revision

class Electronics extends Node:
	var active := false
	var current_page := ""
	var opened: Array[String]=[]
	var closes := 0
	func open(page: String) -> void:active=true;current_page=page;opened.append(page)
	func close() -> void:active=false;closes+=1

class UI extends Node:
	var messages: Array[String]=[]
	func log_message(message: String) -> void:messages.append(message)

class Game extends Node:
	var electronics := Electronics.new()
	var ui := UI.new()
	func _ready() -> void:add_child(electronics);add_child(ui)

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)

func station() -> StaticBody3D:return StaticBody3D.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var provider := Provider.new()
	var game := Game.new();root.add_child(game)
	var router := preload("res://scripts/campus/dorms/interactions/personal_station_router.gd").new();root.add_child(router);router.configure(game,provider)
	var kit:=station();var loadout:=station();var notes:=station()
	root.add_child(kit);root.add_child(loadout);root.add_child(notes)
	check(router.register_station(kit,"dorm_01","kit_workshop"),"mount kit prop")
	check(router.register_station(loadout,"dorm_01","loadout"),"mount backpack prop")
	check(router.register_station(notes,"dorm_01","notes"),"mount paper prop")
	check(router.replacements_ready_for_local_owner(),"all personal replacements ready")
	check(router.interact(kit) and game.electronics.opened==["kits"],"owner reaches existing kit UI")
	check(router.interact(loadout) and game.electronics.opened==["kits","inventory"],"owner reaches existing loadout UI")
	check(router.interact(notes) and game.electronics.opened==["kits","inventory","notes"],"owner reaches existing notes UI")
	check(not preload("res://scripts/campus/dorms/interactions/shop_fallback_policy.gd").legacy_station_enabled(router,"kits"),"legacy personal station suppressed after complete mount")
	check(preload("res://scripts/campus/dorms/interactions/shop_fallback_policy.gd").legacy_station_enabled(router,"shop"),"purchasing is never suppressed")
	var visitor:=station();root.add_child(visitor);router.register_station(visitor,"dorm_02","notes")
	check(router.interact(visitor),"visitor target is consumed")
	check(game.electronics.opened.size()==3 and not game.ui.messages.is_empty(),"visitor cannot see resident private notes")
	provider.identities[1]="profile:forged"
	check(router.interact(kit) and game.electronics.opened.size()==3,"assignment alone cannot bypass authenticated identity")
	provider.identities[1]="profile:alice";provider.rooms.erase(1);provider.revision+=1;router.assignment_changed()
	check(game.electronics.closes==1 and not game.electronics.active,"assignment loss closes controller-opened UI")
	check(preload("res://scripts/campus/dorms/interactions/shop_fallback_policy.gd").legacy_station_enabled(router,"kits"),"shop fallback returns when room is unavailable")
	print("DORM_INTERACTION_TESTS checks=14 failures=",failures)
	game.queue_free();router.queue_free();kit.queue_free();loadout.queue_free();notes.queue_free();visitor.queue_free();await process_frame
	quit(failures)
