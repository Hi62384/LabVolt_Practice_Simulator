extends Node3D
## Client-side visual population. No RPC, physics, navigation server or gameplay state.
const MESH_PATHS := ["res://assets/campus/npcs/student_full.tres", "res://assets/campus/npcs/student_reduced.tres"]
const DENSITIES := {"Off": 0, "Low": 4, "Medium": 10, "High": 18}
const HARD_CAP := 24
const VARIANT_SHADER = preload("res://scripts/campus/npcs/crowd_variant.gdshader")
var density := "Medium"
var auto_density := true
var allow_headless := false
var spawn_radius := 40.0
var near_distance := 12.0
var medium_distance := 28.0
var _zone := ""
var _viewer := Vector3.ZERO
var _routes: Dictionary = {}
var _pool: Array[Dictionary] = []
var _meshes: Array[ArrayMesh] = []
var _adaptive_cap := 10
var _slow_seconds := 0.0
var _fast_seconds := 0.0
var _spawn_clock := 0.0
var _disabled_reason := ""
var _updates := 0
var _loading_index := -1
var _update_calls := 0
var _update_total_usec := 0
var _update_max_usec := 0
var _behavior = load("res://scripts/campus/npcs/student_behavior.gd").new()
var _visibility: Array[Dictionary] = []
var visibility_enter_distance := 38.0
var visibility_exit_distance := 44.0
var fade_seconds := 0.35
var _appearance = load("res://scripts/campus/social/student_appearance/student_appearance_provider.gd").new(24)
var _avatar_renderer = load("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
var _detailed_count := 0
const DETAILED_LIMIT := 4

func _ready() -> void:
	# Registry routes and viewer positions are in world coordinates.
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	_behavior.configure(load("res://scripts/campus/world/room_registry.gd").new())
	if DisplayServer.get_name() == "headless" and not allow_headless:
		set_process(false)

func set_density(value: String) -> void:
	if not DENSITIES.has(value) or value == density:
		return
	density = value
	_adaptive_cap = DENSITIES[value]
	_slow_seconds = 0.0
	_fast_seconds = 0.0
	_apply_visibility()

func set_context(zone_id: String, viewer_position: Vector3) -> void:
	if not viewer_position.is_finite():
		return
	_viewer = viewer_position
	_zone = zone_id
	_apply_visibility()

func set_routes(zone_id: String, routes: Array) -> void:
	if not _routes.has(zone_id) and _routes.size() >= 32:
		return
	var safe: Array[PackedVector3Array] = []
	for candidate in routes.slice(0, HARD_CAP):
		if not (candidate is Array or candidate is PackedVector3Array):
			continue
		var points := PackedVector3Array()
		for point in candidate:
			if point is Vector3 and point.is_finite():
				points.append(point)
			if points.size() >= 64:
				break
		if points.size() >= 2:
			safe.append(points)
	_routes[zone_id] = safe
	if zone_id == _zone:
		for item in _pool:
			item.route = PackedVector3Array()
		_apply_visibility()

func disable(reason: String) -> void:
	_disabled_reason = reason
	set_density("Off")
	# Retain pooled shared meshes for a later explicit density choice.

func prewarm() -> bool:
	# Optional synchronous loading-screen hook; runtime spawning uses background loads.
	for i in range(_meshes.size(), MESH_PATHS.size()):
		var mesh := load(MESH_PATHS[i]) as ArrayMesh
		if mesh == null:
			disable("Student mesh unavailable")
			return false
		_meshes.append(mesh)
	return true

func _load_next_template() -> void:
	var index := _meshes.size()
	if _loading_index != index:
		if ResourceLoader.load_threaded_request(MESH_PATHS[index], "ArrayMesh") != OK:
			disable("Student mesh unavailable")
			return
		_loading_index = index
	var status := ResourceLoader.load_threaded_get_status(MESH_PATHS[index])
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		var mesh := ResourceLoader.load_threaded_get(MESH_PATHS[index]) as ArrayMesh
		if mesh == null:
			disable("Student mesh invalid")
		else:
			_meshes.append(mesh)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		disable("Student mesh load failed")

func observe_frame_time(delta: float) -> void:
	if not auto_density or delta <= 0.0 or not is_finite(delta):
		return
	if delta > 0.028:
		_slow_seconds += minf(delta, 0.1)
		_fast_seconds = 0.0
		if _slow_seconds >= 5.0:
			_adaptive_cap = maxi(0, _adaptive_cap - 2)
			_slow_seconds = 0.0
	elif delta < 0.020:
		_fast_seconds += delta
		_slow_seconds = maxf(0.0, _slow_seconds - delta)
		if _fast_seconds >= 30.0:
			_adaptive_cap = mini(int(DENSITIES[density]), _adaptive_cap + 1)
			_fast_seconds = 0.0
	else:
		_slow_seconds = maxf(0.0, _slow_seconds - delta)
		_fast_seconds = 0.0

func _process(delta: float) -> void:
	observe_frame_time(delta)
	advance(delta)

func advance(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	var started := Time.get_ticks_usec()
	var desired := _desired()
	_behavior.set_population(desired)
	_behavior.advance(delta)
	_spawn_clock += minf(delta, 0.1)
	if desired > 0 and _spawn_clock >= 0.2:
		_spawn_clock = 0.0
		# At most one template or pooled visual initialized in a frame.
		if _meshes.size() < 2:
			_load_next_template()
		elif _pool.size() < desired:
			_create_visual()
	_apply_visibility()
	for i in _pool.size():
		var item: Dictionary = _pool[i]
		if i >= desired:
			continue
		if i < _behavior.students.size():
			var simulated: Dictionary = _behavior.students[i]
			var previous: Vector3 = item.node.position
			item.node.position = simulated.position
			if bool(simulated.moving) and previous.distance_squared_to(item.node.position) > 0.0001:
				var travel: Vector3 = item.node.position - previous
				item.node.rotation.y = atan2(travel.x, travel.z)
		var distance: float = item.node.position.distance_to(_viewer)
		_update_visual_visibility(item, i, distance, delta)
		_update_appearance(item, i, distance)
		if not item.node.visible:
			continue
		var lod := 0 if distance < near_distance else (1 if distance < medium_distance else 2)
		if item.lod != lod:
			if not is_instance_valid(item.avatar) or not item.avatar.visible:
				item.node.mesh = _meshes[mini(lod, 1)]
			item.lod = lod
		item.clock += delta
		var interval: float = 1.0 / (30.0 if lod == 0 else (8.0 if lod == 1 else 1.0))
		if item.clock < interval:
			continue
		var elapsed: float = minf(item.clock, 0.5)
		item.clock = 0.0
		_updates += 1
		if lod == 2:
			continue # Freeze distant animation and movement.
		if i < _behavior.students.size() and bool(_behavior.students[i].moving):
			item.phase += elapsed * 5.0
		# Nearby shared mesh also animates the original limbs in a vertex shader.
		item.node.rotation.z = sin(item.phase) * 0.025 if lod == 0 else 0.0
	var cost := Time.get_ticks_usec() - started
	_update_calls += 1
	_update_total_usec += cost
	_update_max_usec = maxi(_update_max_usec, cost)

func _desired() -> int:
	if _zone.is_empty():
		return 0
	return mini(HARD_CAP, mini(int(DENSITIES[density]), _adaptive_cap))

func _create_visual() -> void:
	var visual := MeshInstance3D.new()
	visual.name = "DecorativeStudent%d" % _pool.size()
	visual.mesh = _meshes[0]
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	visual.visibility_range_end = spawn_radius
	var identity := _pool.size()
	var appearance: Dictionary = _appearance.appearance_for_student(identity)
	var legacy: Dictionary = appearance.get("legacy_character", {})
	var variant := ShaderMaterial.new()
	variant.shader = VARIANT_SHADER
	variant.set_shader_parameter("identity_tint", Color(str(legacy.get("top", "ffffff"))).lerp(Color.WHITE, 0.55))
	visual.material_override = variant
	visual.scale = Vector3(1.0, float(appearance.get("body", {}).get("height", 1.0)), 1.0)
	# Geometry stays shared; one cheap tint material is cached per pooled identity.
	add_child(visual)
	_pool.append({"node": visual, "route": PackedVector3Array(), "target": 1, "clock": 0.0, "phase": float(identity), "lod": -1, "appearance_id": appearance.appearance_id, "avatar": null})
	_visibility.append({"inside": false, "alpha": 0.0})

func _update_appearance(item: Dictionary, index: int, distance: float) -> void:
	var avatar: Node3D = item.avatar
	if is_instance_valid(avatar):
		avatar.visible = item.node.visible and distance < near_distance + 2.0
		item.node.mesh = null if avatar.visible else _meshes[mini(int(item.lod) if int(item.lod) >= 0 else 1, 1)]
		_set_avatar_fade(avatar, item.node.transparency)
		return
	if distance >= near_distance or not item.node.visible or _detailed_count >= DETAILED_LIMIT:
		return
	var state: Dictionary = _appearance.appearance_for_id(int(item.appearance_id))
	var rendered: Node3D = _avatar_renderer.render_avatar(state, _appearance.catalog())
	if not is_instance_valid(rendered):
		return
	item.node.add_child(rendered)
	rendered.scale.y = 1.0 / item.node.scale.y
	item.avatar = rendered
	_detailed_count += 1
	item.node.mesh = null

func _set_avatar_fade(root: Node, amount: float) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			child.transparency = amount
		_set_avatar_fade(child, amount)

func _update_visual_visibility(item: Dictionary, index: int, distance: float, delta: float) -> void:
	var visibility: Dictionary = _visibility[index]
	if bool(visibility.inside):
		if distance > visibility_exit_distance:
			visibility.inside = false
	elif distance < visibility_enter_distance:
		visibility.inside = true
	var target := 1.0 if bool(visibility.inside) else 0.0
	visibility.alpha = move_toward(float(visibility.alpha), target, delta / maxf(fade_seconds, 0.01))
	item.node.transparency = 1.0 - float(visibility.alpha)
	item.node.visible = float(visibility.alpha) > 0.01

func _assign_route(item: Dictionary, index: int) -> void:
	var routes: Array = _routes.get(_zone, [])
	for offset in routes.size():
		var route: PackedVector3Array = routes[(index + offset) % routes.size()]
		var route_fraction := float(index) * route.size() / maxi(1, _desired())
		var point_index := int(route_fraction) % route.size()
		var next_index := (point_index + 1) % route.size()
		var spawn := route[point_index].lerp(route[next_index], fposmod(route_fraction, 1.0))
		if spawn.distance_to(_viewer) > spawn_radius:
			continue
		item.route = route
		item.node.position = spawn
		item.target = next_index
		# A reused visual starts this route without time or pose from its old zone.
		item.clock = 0.0
		item.node.rotation = Vector3.ZERO
		return

func _apply_visibility() -> void:
	var desired := _desired()
	for i in _pool.size():
		if i >= desired:
			_pool[i].node.visible = false

func get_stats() -> Dictionary:
	var active := 0
	for item in _pool:
		if item.node.visible:
			active += 1
	return {"density": density, "active": active, "pooled": _pool.size(), "adaptive_cap": _adaptive_cap, "hard_cap": HARD_CAP, "zone_id": _zone, "updates": _updates, "disabled_reason": _disabled_reason, "templates": _meshes.size(), "network_messages": 0, "update_calls": _update_calls, "update_mean_usec": float(_update_total_usec) / maxi(1, _update_calls), "update_max_usec": _update_max_usec}
