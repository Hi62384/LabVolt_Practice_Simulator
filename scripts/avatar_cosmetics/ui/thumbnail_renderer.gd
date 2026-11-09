class_name CosmeticThumbnailRenderer
extends Node

# One renderer instance services the cache queue. It owns one reusable viewport,
# never one viewport per card. `builder` returns a posed Node3D for an item draft.
var _builder: Callable
var _viewport: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _subject: Node3D

func configure(builder: Callable) -> void:
	_builder = builder

func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 256)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("1b293b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.7
	_stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32, -35, 0)
	light.light_energy = 1.15
	_stage.add_child(light)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.05, 3.1)
	_camera.fov = 36
	_stage.add_child(_camera)
	_camera.look_at(Vector3(0, 1.0, 0))

func render_item(item_id: String, parameters: Dictionary, body: Dictionary) -> Texture2D:
	if not _builder.is_valid() or DisplayServer.get_name() == "headless":
		return null
	if is_instance_valid(_subject):
		_stage.remove_child(_subject)
		_subject.queue_free()
	var built: Variant = _builder.call(item_id, parameters, body)
	if built is not Node3D:
		return null
	_subject = built
	_stage.add_child(_subject)
	_frame_subject()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return null
	var image := _viewport.get_texture().get_image()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_stage.remove_child(_subject)
	_subject.queue_free()
	_subject = null
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null

func _frame_subject() -> void:
	var category := str(_subject.get_meta("thumbnail_category", ""))
	var bounds := AABB()
	for mesh in _subject.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree() and mesh.mesh != null:
			var part: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = part if bounds.size == Vector3.ZERO else bounds.merge(part)
	var center := bounds.get_center()
	var span := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var angle := Vector3(0.47, 0.26, 1.0).normalized()
	if category in ["faces", "hair", "facial_hair"]:
		var head := _subject.get_node_or_null("Body/Head") as Node3D
		if head != null:
			var head_bounds := AABB()
			for mesh in head.find_children("*", "MeshInstance3D", true, false):
				if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
				var part: AABB = mesh.global_transform * mesh.get_aabb()
				head_bounds = part if head_bounds.size == Vector3.ZERO else head_bounds.merge(part)
			center = head_bounds.get_center()
			span = maxf(.47, head_bounds.get_longest_axis_size())
			angle = Vector3(.95 if category == "hair" else .18, .04, .75).normalized()
	elif category in ["tops", "bottoms"]:
		center.y = bounds.position.y + bounds.size.y * (0.59 if category == "tops" else 0.28)
		span = bounds.size.y * 0.56
	var distance := maxf(span * 1.9, 0.12)
	_camera.near = minf(0.03, distance * 0.14)
	_camera.position = center + angle * distance
	_camera.look_at(center)

