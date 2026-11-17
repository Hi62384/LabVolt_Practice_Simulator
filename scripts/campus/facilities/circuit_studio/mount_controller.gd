class_name CircuitStudioMountController
extends Node

const Contract=preload("res://scripts/campus/facilities/circuit_studio/studio_contract.gd")
const Room=preload("res://scripts/campus/facilities/circuit_studio/studio_room.gd")
var game: Node
var campus: Node
var room: CircuitStudioRoom
var mount_succeeded:=false

func install(owner_game: Node,owner_campus: Node) -> bool:
	game=owner_game;campus=owner_campus
	if not is_instance_valid(game) or not is_instance_valid(campus):return false
	var expected:=Contract.room_record()
	if not Contract.valid_room_record(expected):return false
	var registered: Dictionary=campus.registry.get_room(Contract.ROOM_ID)
	if registered.is_empty() or registered.get("center")!=expected.center or registered.get("bounds_min")!=expected.bounds_min or registered.get("bounds_max")!=expected.bounds_max:return false
	room=Room.new();add_child(room)
	if not room.build(game):
		room.queue_free()
		return false
	if not campus.has_method("register_content") or not bool(campus.call("register_content",Contract.ROOM_ID,room)):
		room.queue_free()
		return false
	mount_succeeded=room.is_ready()
	return mount_succeeded

func interact(target: Node) -> bool:
	return mount_succeeded and is_instance_valid(room) and room.interact(target)

func legacy_custom_circuits_enabled() -> bool:
	# The shop target remains live on every partial/failed initialization path.
	return not mount_succeeded or not is_instance_valid(room) or not room.is_ready()

