class_name CircuitStudioInteractionAdapter
extends Node

const Contract=preload("res://scripts/campus/facilities/circuit_studio/studio_contract.gd")
var game: Node
var room_id := Contract.ROOM_ID
var stations: Dictionary = {}
var builder_window: Window

func configure(owner_game: Node, station_room := Contract.ROOM_ID) -> bool:
	game=owner_game
	room_id=station_room
	return _electronics_ready()

func register_station(station: Node,action: String) -> bool:
	if not is_instance_valid(station) or not Contract.ACTION_PAGES.has(action):return false
	station.set_meta("role",Contract.ROLE)
	station.set_meta("room_id",room_id)
	station.set_meta("action",action)
	station.set_meta("page",Contract.ACTION_PAGES[action])
	station.set_meta("label",prompt_for_action(action))
	stations[station.get_instance_id()]=station
	return true

func interact(target: Node) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","")!=Contract.ROLE:return false
	if target.get_meta("room_id","")!=room_id:return false
	if not stations.has(target.get_instance_id()) or stations[target.get_instance_id()]!=target:return true
	if not _electronics_ready():
		_notice("Circuit Studio is still initializing. Custom Circuits remains available in the shop.")
		return true
	var page:=str(target.get_meta("page",""))
	if page not in Contract.ACTION_PAGES.values():return true
	if page in ["studio_ic","studio_pcb"]:
		if is_instance_valid(builder_window):builder_window.queue_free()
		builder_window=preload("res://scripts/campus/facilities/circuit_studio/builder_window.gd").new()
		add_child(builder_window)
		builder_window.open_station(game,"IC" if page=="studio_ic" else "PCB")
		return true
	game.electronics.open(page)
	return true

func prompt_for(target: Node) -> String:
	if not is_instance_valid(target) or target.get_meta("role","")!=Contract.ROLE:return ""
	return prompt_for_action(str(target.get_meta("action","")))

func prompt_for_action(action: String) -> String:
	match action:
		"ic_builder":return "IC Builder · package circuit and configure pins"
		"pcb_builder":return "PCB Builder · design a reusable board"
		"prototype_bench":return "Draft and test a custom circuit"
		"firmware_console":return "Open circuit firmware tools"
		"kit_library":return "Open kit builder"
	return "Use Circuit Studio workstation"

func route_complete() -> bool:
	return _electronics_ready() and stations.size()==Contract.ACTION_PAGES.size()

func _electronics_ready() -> bool:
	if not is_instance_valid(game):return false
	var electronics=game.get("electronics")
	return is_instance_valid(electronics) and electronics.has_method("open")

func _notice(message: String) -> void:
	if not is_instance_valid(game):return
	var ui=game.get("ui")
	if is_instance_valid(ui) and ui.has_method("log_message"):ui.log_message(message)

