extends Node
## Switches presentation on the already composed gameplay world.
const Controller = preload("res://scripts/campus/presentation/menu_flythrough/controller.gd")
const Routes = preload("res://scripts/campus/presentation/menu_flythrough/routes.gd")
const Ambience = preload("res://scripts/campus/presentation/menu_flythrough/ambience.gd")

var _game: Node
var _controller: Node
var _ambience: AudioStreamPlayer
var _streamer: Node
var _process_states := {}
var _physics_states := {}
var _visibility_states := {}
var _menu_active := false
var _route_results := {}
var _validation: Array[Dictionary] = []
var _probe := PhysicsShapeQueryParameters3D.new()

func install(game: Node) -> void:
	_game = game
	_streamer = _game.campus.streamer
	var sphere := SphereShape3D.new()
	sphere.radius = 0.24
	_probe.shape = sphere
	_probe.collision_mask = 5 # Campus solids and interaction bodies. The player is layer 2.
	set_physics_process(false)
	_game.ui.graphics_controller.changed.connect(_graphics_changed)

func show_menu() -> void:
	if _menu_active:
		hold(false)
		return
	_menu_active = true
	for node in [_game, _game.dc_lab, _game.school, _game.school_world, _game.campus_performance,
			_game.campus_performance.crowd, _game.campus_services, _game.campus_services.social,
			_game.campus_services.gym_motion, _game.campus_services.facilities.controller,
			_game.dorm_interactions, _game.electronics_trade, _game.kit_world]:
		if is_instance_valid(node):
			_process_states[node] = node.is_processing()
			node.set_process(false)
	for node in [_game, _game.player]:
		_physics_states[node] = node.is_physics_processing()
		node.set_physics_process(false)
	for node in [_game.school_world.teacher, _game.campus_performance.crowd]:
		if is_instance_valid(node):
			_visibility_states[node] = node.visible
			node.hide()
	for control in [_game.ui.hud, _game.ui.objective, _game.ui.log_label, _game.ui.crosshair,
			_game.ui.prompt, _game.held_hint, _game.campus_services.prompt, _game.school_world.timer_label]:
		control.hide()

	_controller = Controller.new()
	add_child(_controller)
	_controller.preparing.connect(_prepare)
	var far_distance := float(_game.ui.graphics_controller.options.view_distance)
	if not _controller.start(Routes.catalog(), _route_status, far_distance):
		_controller.queue_free()
		_controller = null
		return
	_game.campus.set_viewer(_controller.camera)
	if DisplayServer.get_name() != "headless":
		_ambience = Ambience.new()
		add_child(_ambience)
		_ambience.set_outdoors(_location_is_outdoors(_streamer.viewer))

func hold(held: bool) -> void:
	if is_instance_valid(_controller):
		_controller.set_held(held)

func enter_game() -> void:
	if not _menu_active:
		return
	_menu_active = false
	_validation.clear()
	_route_results.clear()
	set_physics_process(false)
	_game.camera.make_current()
	if is_instance_valid(_controller):
		_controller.set_held(true)
		remove_child(_controller)
		_controller.queue_free()
		_controller = null
	if is_instance_valid(_ambience):
		_ambience.queue_free()
		_ambience = null
	_game.campus.set_viewer(_game.player)
	_streamer.clear_menu_rooms()
	for node in _process_states:
		if is_instance_valid(node):
			node.set_process(_process_states[node])
	for node in _physics_states:
		if is_instance_valid(node):
			node.set_physics_process(_physics_states[node])
	for node in _visibility_states:
		if is_instance_valid(node):
			node.visible = _visibility_states[node]
	_process_states.clear()
	_physics_states.clear()
	_visibility_states.clear()

func _prepare(current: Dictionary, upcoming: Dictionary) -> void:
	var rooms := _rooms_for(current)
	for id in _rooms_for(upcoming):
		if not rooms.has(id):
			rooms.append(id)
	_streamer.set_menu_rooms(rooms)
	for job in _validation.duplicate():
		if job.shot != current and job.shot != upcoming:
			_validation.erase(job)
	for shot in [current, upcoming]:
		if not shot.is_empty() and not _route_results.has(shot.id):
			_route_results[shot.id] = 0
			_validation.append({"shot": shot, "distance": 0.0})
	set_physics_process(not _validation.is_empty())
	if upcoming.is_empty() and is_instance_valid(_ambience):
		_ambience.set_outdoors(current.get("location") == "exterior")

func _route_status(shot: Dictionary) -> int:
	var result := int(_route_results.get(shot.get("id"), 0))
	if result <= 0:
		return result
	return 1 if _rooms_ready(shot) else 0

func _rooms_ready(shot: Dictionary) -> bool:
	for id in _rooms_for(shot):
		if not _streamer.active.get(id, false):
			return false
	return true

func _physics_process(_delta: float) -> void:
	if _validation.is_empty():
		set_physics_process(false)
		return
	var job := {}
	for candidate in _validation:
		if _rooms_ready(candidate.shot):
			job = candidate
			break
	if job.is_empty():
		return
	var shot: Dictionary = job.shot
	var path: Curve3D = shot.path
	var length: float = shot.length
	var space: PhysicsDirectSpaceState3D = _game.get_world_3d().direct_space_state
	for _sample in 12:
		var distance: float = job.distance
		var point := path.sample_baked(distance)
		_probe.transform = Transform3D(Basis.IDENTITY, point)
		if not space.intersect_shape(_probe, 1).is_empty():
			_route_results[shot.id] = -1
			_validation.erase(job)
			push_warning("Menu flythrough skipped obstructed route %s near %s" % [shot.id, point])
			return
		if distance >= length:
			_route_results[shot.id] = 1
			_validation.erase(job)
			return
		job.distance = minf(length, distance + 0.18)

func _rooms_for(shot: Dictionary) -> PackedStringArray:
	var rooms := PackedStringArray()
	for id in shot.get("rooms", PackedStringArray()):
		if _streamer.registry.rooms.has(id) and not rooms.has(id):
			rooms.append(id)
	var location := str(shot.get("location", ""))
	if _streamer.registry.rooms.has(location) and not rooms.has(location):
		rooms.append(location)
	return rooms

func _location_is_outdoors(point: Vector3) -> bool:
	return _game.campus.registry.locate(point) == "exterior"

func _graphics_changed(options: Dictionary) -> void:
	if is_instance_valid(_controller):
		_controller.camera.far = float(options.view_distance)

