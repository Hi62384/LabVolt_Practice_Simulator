extends Node
## Camera and transition state for a collection of world-space Curve3D shots.
signal preparing(current: Dictionary, upcoming: Dictionary)

const PREPARE_SECONDS := 2.5
const FADE_SECONDS := 0.95
const MAX_WAIT_SECONDS := 12.0

var camera: Camera3D
var _outgoing: SubViewport
var _overlay: TextureRect
var _routes: Array[Dictionary] = []
var _remaining: Array[Dictionary] = []
var _route: Dictionary
var _next: Dictionary
var _elapsed := 0.0
var _wait := 0.0
var _fade := FADE_SECONDS
var _running := false
var _capture_pending := false
var _status: Callable
var _rejected := {}
var _random := RandomNumberGenerator.new()

func start(catalog: Array[Dictionary], route_status: Callable, far_distance: float) -> bool:
	_status = route_status
	_random.randomize()
	var ids := {}
	for candidate in catalog:
		var id := str(candidate.get("id", ""))
		var path := candidate.get("path") as Curve3D
		var look: Variant = candidate.get("look")
		var speed := float(candidate.get("speed", 0.0))
		var weight := float(candidate.get("weight", 1.0))
		if id.is_empty() or ids.has(id) or path == null or path.point_count < 2:
			continue
		if not (look is PackedVector3Array) or look.size() < 2:
			continue
		if not is_finite(speed) or not is_finite(weight) or speed <= 0.0 or weight <= 0.0:
			continue
		var length := path.get_baked_length()
		if not is_finite(length) or length < 0.05:
			continue
		var shot := candidate.duplicate()
		shot.length = length
		shot.duration = length / speed
		shot.weight = weight
		_routes.append(shot)
		ids[id] = true
	if _routes.is_empty():
		push_error("Menu flythrough has no valid campus routes.")
		return false

	camera = Camera3D.new()
	camera.name = "MenuCampusCamera"
	camera.fov = 63.0
	camera.near = 0.07
	camera.far = far_distance
	add_child(camera)
	_route = _pick(true)
	_apply_pose(0.0)
	preparing.emit(_route, {})
	camera.make_current()
	_running = true
	return true

func set_held(held: bool) -> void:
	_running = not held
	if held and _capture_pending:
		_cancel_capture()
	set_process(_running or _fade < FADE_SECONDS)

func _pick(prefer_exterior := false) -> Dictionary:
	if _remaining.is_empty():
		for shot in _routes:
			if not _rejected.has(shot.id):
				_remaining.append(shot)
	var choices: Array[Dictionary] = []
	for shot in _remaining:
		if shot.get("id") != _route.get("id"):
			choices.append(shot)
	if choices.is_empty():
		choices.assign(_remaining)
	if choices.is_empty():
		return {}
	if prefer_exterior:
		for shot in choices:
			if shot.get("location") == "exterior":
				_remaining.erase(shot)
				return shot
	var total := 0.0
	for shot in choices:
		total += float(shot.weight)
	var draw := _random.randf() * total
	var selected: Dictionary = choices.back()
	for shot in choices:
		draw -= float(shot.weight)
		if draw <= 0.0:
			selected = shot
			break
	_remaining.erase(selected)
	return selected

func _process(delta: float) -> void:
	if _capture_pending:
		return
	var dt := minf(delta, 0.10)
	if _fade < FADE_SECONDS:
		_fade = minf(_fade + dt, FADE_SECONDS)
		_overlay.modulate.a = 1.0 - smoothstep(0.0, FADE_SECONDS, _fade)
		if _fade >= FADE_SECONDS:
			_release_overlay()
	if not _running:
		if _fade >= FADE_SECONDS:
			set_process(false)
		return
	var state := -1 if _rejected.has(_route.id) else int(_status.call(_route))
	if state == 0:
		_wait += dt
		if _wait < MAX_WAIT_SECONDS:
			return
		push_warning("Menu flythrough timed out preparing %s" % _route.id)
		state = -1
		_wait = 0.0
	var duration: float = _route.duration
	if state > 0:
		_elapsed = minf(_elapsed + dt, duration)
		_apply_pose(_travel_fraction(_elapsed, duration))
	else:
		_rejected[_route.id] = true
		_elapsed = duration
	if not _next.is_empty() and int(_status.call(_next)) < 0:
		_rejected[_next.id] = true
		_next = {}
		_wait = 0.0
	if _next.is_empty() and duration - _elapsed <= PREPARE_SECONDS:
		_next = _pick()
		if _next.is_empty():
			set_process(false)
			return
		preparing.emit(_route, _next)
	if _elapsed < duration or _fade < FADE_SECONDS:
		return
	if int(_status.call(_next)) > 0:
		_transition()
	else:
		_wait += dt
		if _wait >= MAX_WAIT_SECONDS:
			push_warning("Menu flythrough timed out preparing %s" % _next.id)
			_rejected[_next.id] = true
			_next = {}
			_wait = 0.0

func _travel_fraction(seconds: float, duration: float) -> float:
	# Integrate a short speed ramp at each end, with a steady middle section.
	var ramp := minf(2.0, duration * 0.25)
	var divisor := duration - ramp
	if seconds < ramp:
		return 0.5 * seconds * seconds / (ramp * divisor)
	var left := duration - seconds
	if left < ramp:
		return 1.0 - 0.5 * left * left / (ramp * divisor)
	return (seconds - 0.5 * ramp) / divisor

func _pose(shot: Dictionary, fraction: float) -> Transform3D:
	var path: Curve3D = shot.path
	var point := path.sample_baked(float(shot.length) * fraction)
	var looks: PackedVector3Array = shot.look
	var key := fraction * (looks.size() - 1)
	var index := mini(int(key), looks.size() - 2)
	var target := looks[index].lerp(looks[index + 1], smoothstep(0.0, 1.0, key - index))
	var forward := target - point
	if forward.length_squared() < 0.001:
		var length: float = shot.length
		forward = path.sample_baked(minf(length * fraction + 0.25, length)) - path.sample_baked(maxf(length * fraction - 0.25, 0.0))
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var horizontal := Vector3(forward.x, 0.0, forward.z)
	if horizontal.length_squared() < 0.001:
		horizontal = Vector3.FORWARD
	forward = horizontal + Vector3.UP * clampf(forward.y, -horizontal.length() * 0.85, horizontal.length() * 0.85)
	return Transform3D(Basis.looking_at(forward), point)

func _apply_pose(fraction: float) -> void:
	camera.global_transform = _pose(_route, fraction)

func _transition() -> void:
	var start_pose := _pose(_next, 0.0)
	var end_pose := camera.global_transform
	var continuous: bool = _route.get("transition") == "continuous"
	continuous = continuous and end_pose.origin.is_equal_approx(start_pose.origin)
	continuous = continuous and end_pose.basis.is_equal_approx(start_pose.basis)
	if continuous or DisplayServer.get_name() == "headless":
		_enter_next()
		return
	var main := get_viewport()
	var visible_size := Vector2i(main.get_visible_rect().size)
	if visible_size.x < 2 or visible_size.y < 2:
		return

	# Render the outgoing pose once, in the same World3D, while the main camera
	# still renders it. Subsequent fade frames reuse the frozen viewport texture.
	_outgoing = SubViewport.new()
	_outgoing.world_3d = camera.get_world_3d()
	_outgoing.use_occlusion_culling = main.use_occlusion_culling
	_outgoing.size = Vector2i(Vector2(visible_size) * minf(1.0, 960.0 / visible_size.x)).max(Vector2i(2, 2))
	_outgoing.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_outgoing)
	var outgoing_camera := Camera3D.new()
	outgoing_camera.fov = camera.fov
	outgoing_camera.near = camera.near
	outgoing_camera.far = camera.far
	outgoing_camera.cull_mask = camera.cull_mask
	_outgoing.add_child(outgoing_camera)
	outgoing_camera.global_transform = end_pose
	outgoing_camera.make_current()
	_capture_pending = true
	RenderingServer.frame_post_draw.connect(_finish_capture, CONNECT_ONE_SHOT)
	_outgoing.render_target_update_mode = SubViewport.UPDATE_ONCE

func _finish_capture() -> void:
	_capture_pending = false
	var layer := CanvasLayer.new()
	layer.layer = 19
	add_child(layer)
	_overlay = TextureRect.new()
	_overlay.texture = _outgoing.get_texture()
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade = 0.0
	_enter_next()

func _enter_next() -> void:
	_route = _next
	_next = {}
	_elapsed = 0.0
	_wait = 0.0
	_apply_pose(0.0)
	preparing.emit(_route, {})

func _cancel_capture() -> void:
	_capture_pending = false
	if RenderingServer.frame_post_draw.is_connected(_finish_capture):
		RenderingServer.frame_post_draw.disconnect(_finish_capture)
	if is_instance_valid(_outgoing):
		_outgoing.queue_free()
		_outgoing = null

func _release_overlay() -> void:
	if is_instance_valid(_overlay):
		_overlay.hide()
		_overlay.get_parent().queue_free()
		_overlay = null
	_cancel_capture()

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_finish_capture):
		RenderingServer.frame_post_draw.disconnect(_finish_capture)
