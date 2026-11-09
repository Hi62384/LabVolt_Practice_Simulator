class_name CosmeticLivePreview
extends SubViewportContainer
const CameraState = preload("res://scripts/avatar_cosmetics/ui/preview_camera_state.gd")

var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var avatar: Node3D
var camera_state := CameraState.new()
var _drag_button := 0
var pose := ""
var _rest_rotations: Dictionary = {}
const POSE_JOINTS := ["Body/ArmL", "Body/ArmR", "Body/Head", "LegL", "LegR"]

func _ready() -> void:
	stretch = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(720, 720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1b293b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d9e4f4")
	environment.environment.ambient_light_energy = 0.48
	stage.add_child(environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35, -30, 0)
	key_light.light_energy = 0.82
	key_light.shadow_enabled = true
	stage.add_child(key_light)
	camera = Camera3D.new()
	camera.fov = 37
	stage.add_child(camera)
	gui_input.connect(_preview_input)
	_apply_camera()

func set_avatar(next_avatar: Node3D) -> void:
	var walk_time := 0.0
	if is_instance_valid(avatar):
		var previous_player := avatar.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if pose == "Walk" and previous_player != null and previous_player.is_playing():
			walk_time = previous_player.current_animation_position
		stage.remove_child(avatar)
		avatar.queue_free()
	avatar = next_avatar
	_rest_rotations.clear()
	if avatar != null:
		stage.add_child(avatar)
		if not pose.is_empty():
			for path in POSE_JOINTS:
				var joint := avatar.get_node_or_null(path) as Node3D
				if joint != null:
					_rest_rotations[joint] = joint.quaternion
			_apply_pose()
			if walk_time > 0.0:
				var player := avatar.get_node_or_null("AnimationPlayer") as AnimationPlayer
				if player != null and player.is_playing():
					player.seek(walk_time, true)

func set_pose(value: String) -> void:
	pose = value
	_apply_pose()

func _apply_pose() -> void:
	if not is_instance_valid(avatar):
		return
	var player := avatar.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null:
		player.stop()
	for joint in _rest_rotations:
		joint.quaternion = _rest_rotations[joint]
	if pose == "Walk":
		if player != null and player.has_animation("Walk"):
			player.play("Walk")
		return
	var arm_angle := deg_to_rad(90.0 if pose == "T-pose" else 36.0 if pose == "Fit check" else 9.0)
	for path in ["Body/ArmL", "Body/ArmR"]:
		var arm := avatar.get_node_or_null(path) as Node3D
		if arm != null:
			arm.rotation = Vector3(0.0, 0.0, -arm_angle if path.ends_with("L") else arm_angle)

func use_native_resolution() -> void:
	# Draw the texture ourselves so canvas scaling does not upscale the 3D render.
	var display := TextureRect.new()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	display.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var render_root := Node.new()
	add_child(render_root)
	viewport.reparent(render_root)
	display.texture = viewport.get_texture()
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	resized.connect(_resize_native_viewport)
	get_viewport().size_changed.connect(_resize_native_viewport)
	_resize_native_viewport()

func _resize_native_viewport() -> void:
	var pixels := size * get_screen_transform().get_scale().abs()
	viewport.size = Vector2i(pixels.ceil()).max(Vector2i(2, 2))

func focus_category(category: String, force := false) -> void:
	if camera_state.focus_category(category, Time.get_ticks_msec(), force):
		_apply_camera()

func reset_camera() -> void:
	camera_state.reset()
	_apply_camera()

func _apply_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(0, 0, camera_state.distance)
	offset = offset.rotated(Vector3.RIGHT, camera_state.pitch).rotated(Vector3.UP, camera_state.yaw)
	camera.position = camera_state.target + offset
	camera.look_at(camera_state.target)

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_drag_button = event.button_index if event.pressed else 0
			accept_event()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera_state.zoom(-0.16 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.16, Time.get_ticks_msec())
			_apply_camera()
			accept_event()
	if event is InputEventMouseMotion:
		if _drag_button == MOUSE_BUTTON_LEFT:
			camera_state.orbit(event.relative, Time.get_ticks_msec())
			_apply_camera()
			accept_event()
		elif _drag_button == MOUSE_BUTTON_MIDDLE:
			camera_state.pan(event.relative, Time.get_ticks_msec())
			_apply_camera()
			accept_event()
