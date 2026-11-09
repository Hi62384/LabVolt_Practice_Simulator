extends Node
## Optional single graphical-client attachment. Registry remains world-owned.
const Crowd = preload("res://scripts/campus/npcs/local_crowd.gd")
const Budget = preload("res://scripts/campus/performance/equipment_budget.gd")
const Probe = preload("res://scripts/campus/performance/frame_probe.gd")
const Overlay = preload("res://scripts/campus/performance/profiling_overlay.gd")
const HallwayRoutes = preload("res://scripts/campus/npcs/hallway_routes.gd")
var crowd: Node3D
var displays := Budget.new()
var probe: Node
var _viewer: Node3D
var _registry: Object
var _context_clock := 0.0
var _density := "Off"

func attach(viewer: Node3D, registry: Object, routes_by_zone: Dictionary = {}) -> void:
	_viewer = viewer
	_registry = registry
	if DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(crowd):
		crowd = Crowd.new()
		add_child(crowd)
		crowd.set_density("Off")
	var routes := HallwayRoutes.from_registry(registry)
	routes.merge(routes_by_zone, true)
	for zone_id in routes:
		crowd.set_routes(str(zone_id), routes[zone_id])
	_update_context()

func set_density(value: String) -> void:
	if not Crowd.DENSITIES.has(value):
		return
	# Hallway students are disabled for now, including older saved density settings.
	_density = "Off"
	if is_instance_valid(crowd):
		crowd.set_density("Off")

func set_routes(zone_id: String, routes: Array) -> void:
	if is_instance_valid(crowd):
		crowd.set_routes(zone_id, routes)

func enable_profiling(show_overlay := false) -> Node:
	if not is_instance_valid(probe):
		probe = Probe.new()
		add_child(probe)
		if show_overlay and DisplayServer.get_name() != "headless":
			var overlay := Overlay.new()
			overlay.probe = probe
			add_child(overlay)
	return probe

func _process(delta: float) -> void:
	_context_clock += delta
	if _context_clock >= 0.2:
		_context_clock = 0.0
		_update_context()
	if is_instance_valid(probe):
		probe.begin_span("display_refresh")
	displays.tick(delta, 500)
	if is_instance_valid(probe):
		probe.end_span("display_refresh")

func _update_context() -> void:
	if not is_instance_valid(crowd):
		return
	if not is_instance_valid(_viewer) or not is_instance_valid(_registry) or not _registry.has_method("locate"):
		crowd.set_context("", Vector3.ZERO)
		return
	var room_id := str(_registry.call("locate", _viewer.global_position))
	var zone_id := room_id
	if _registry.has_method("get_room"):
		var room: Dictionary = _registry.call("get_room", room_id)
		zone_id = str(room.get("zone", room_id))
	crowd.set_context(zone_id, _viewer.global_position)

func _exit_tree() -> void:
	# Release captured presentation callbacks before their scene owners are freed.
	for id in displays._order.duplicate():
		displays.unregister_display(id)
