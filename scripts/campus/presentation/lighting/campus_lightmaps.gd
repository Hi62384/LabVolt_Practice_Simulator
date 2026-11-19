extends Node3D

const CATALOG := "res://assets/campus/lighting/baked/campus_lightmaps.scn"
const BAKED_CASTER_LAYER := 1 << 19

var _campus: Node3D
var _lightmap: LightmapGI
var _entries := {}
var _bound := {}
var _fixture_shadows := {}
var _enabled := true

func install(campus: Node3D, graphics: Node) -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus" or not ResourceLoader.exists(CATALOG):
		return
	var catalog := load(CATALOG) as PackedScene
	if catalog == null:
		return
	var stage := catalog.instantiate()
	var baked := stage.get_node("CampusLightmap") as LightmapGI
	var data := baked.light_data
	var users: Array = data.get("user_data")
	var bounds := AABB()
	for index in range(0, users.size(), 4):
		var mesh_node := baked.get_node_or_null(users[index]) as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var key := _key(mesh_node.transform, mesh_node.mesh)
		if not _entries.has(key):
			var mesh_bounds := mesh_node.transform * mesh_node.mesh.get_aabb()
			bounds = mesh_bounds if _entries.is_empty() else bounds.merge(mesh_bounds)
			_entries[key] = [mesh_node.mesh, users[index + 1], users[index + 2]]
	stage.free()
	if _entries.is_empty():
		return

	_campus = campus
	_lightmap = LightmapGI.new()
	var runtime_data := data.duplicate() as LightmapGIData
	runtime_data.clear_users()
	# A probe-free bake otherwise has empty renderer bounds and can disappear off origin.
	RenderingServer.lightmap_set_probe_bounds(runtime_data.get_rid(), bounds.grow(1.0))
	_lightmap.light_data = runtime_data
	add_child(_lightmap)
	refresh_visual_settings(graphics.options)
	graphics.changed.connect(_settings_changed)
	for node in campus.find_children("*", "MeshInstance3D", true, false):
		_bind(node)
	for light in campus.find_children("*", "Light3D", true, false):
		_register_fixture(light)
	get_tree().node_added.connect(_node_added)

func _node_added(node: Node) -> void:
	if node is MeshInstance3D and _campus.is_ancestor_of(node):
		_bind_later.call_deferred(weakref(node))
	elif node is Light3D and _campus.is_ancestor_of(node):
		_fixture_later.call_deferred(weakref(node))

func _bind_later(reference: WeakRef) -> void:
	var node := reference.get_ref() as MeshInstance3D
	if is_instance_valid(node) and node.is_inside_tree():
		_bind(node)

func _bind(node: MeshInstance3D) -> void:
	var id := node.get_instance_id()
	if _bound.has(id) or node.mesh == null or _moving(node):
		return
	var entry: Array = _entries.get(_key(node.global_transform, node.mesh), [])
	if entry.is_empty():
		return
	var materials: Array[Material] = []
	for surface in node.mesh.get_surface_count():
		materials.append(node.get_active_material(surface))
	node.mesh = entry[0]
	if node.material_override == null:
		for surface in materials.size():
			node.set_surface_override_material(surface, materials[surface])
	_bound[id] = [weakref(node), entry, node.layers]
	node.tree_exiting.connect(func(): _bound.erase(id), CONNECT_ONE_SHOT)
	_apply(node, entry, node.layers)

func _fixture_later(reference: WeakRef) -> void:
	var light := reference.get_ref() as Light3D
	if is_instance_valid(light) and light.is_inside_tree():
		_register_fixture(light)

func _register_fixture(light: Light3D) -> void:
	if light is DirectionalLight3D or not light.get_meta("room_fixture", false):
		return
	var id := light.get_instance_id()
	var mask := light.shadow_caster_mask
	_fixture_shadows[id] = [weakref(light), mask]
	light.tree_exiting.connect(func(): _fixture_shadows.erase(id), CONNECT_ONE_SHOT)
	if _enabled:
		light.shadow_caster_mask = mask & ~BAKED_CASTER_LAYER

func refresh_visual_settings(options: Dictionary) -> void:
	if _lightmap == null:
		return
	var visuals := get_parent().get_node_or_null("CampusVisualSettings")
	var strength: float = visuals.baked_light_strength if visuals != null else 1.0
	var world := get_parent().get_node("WorldEnvironment") as WorldEnvironment
	if not is_equal_approx(strength, 1.0) and world.camera_attributes == null:
		world.camera_attributes = CameraAttributesPractical.new()
	var data := _lightmap.light_data
	var probe_data: Dictionary = data.get("probe_data")
	var exposure := maxf(float(probe_data.get("baked_exposure", 1.0)), 0.001)
	RenderingServer.lightmap_set_baked_exposure_normalization(data.get_rid(), exposure / maxf(strength, 0.1))
	_settings_changed(options)

func _settings_changed(options: Dictionary) -> void:
	var visuals := get_parent().get_node_or_null("CampusVisualSettings")
	var enabled := bool(options.shadows) and (visuals == null or bool(visuals.use_baked_lighting))
	if _enabled == enabled:
		return
	_enabled = enabled
	for binding in _bound.values():
		var node := (binding[0] as WeakRef).get_ref() as MeshInstance3D
		if is_instance_valid(node):
			_apply(node, binding[1], binding[2])
	for binding in _fixture_shadows.values():
		var light := (binding[0] as WeakRef).get_ref() as Light3D
		if is_instance_valid(light):
			var mask: int = binding[1]
			light.shadow_caster_mask = mask & ~BAKED_CASTER_LAYER if _enabled else mask

func _apply(node: MeshInstance3D, entry: Array, layers: int) -> void:
	# Move only ordinary world meshes. Explicit layer masks may belong to other cameras or lights.
	if layers == 1:
		node.layers = BAKED_CASTER_LAYER if _enabled else layers
	var lightmap_rid := _lightmap.get_instance() if _enabled else RID()
	RenderingServer.instance_geometry_set_lightmap(node.get_instance(), lightmap_rid, entry[1], entry[2])

func _moving(node: Node) -> bool:
	var ancestor := node
	while ancestor != _campus:
		if ancestor is AnimatableBody3D or ancestor is CharacterBody3D or ancestor is RigidBody3D:
			return true
		if ancestor.name.begins_with("Door_") or ancestor.name == "ElevatorGeometry":
			return true
		ancestor = ancestor.get_parent()
	return false

func _key(transform: Transform3D, mesh: Mesh) -> Array:
	const STEP := Vector3(0.001, 0.001, 0.001)
	var bounds := mesh.get_aabb()
	return [
		transform.origin.snapped(STEP), transform.basis.x.snapped(STEP),
		transform.basis.y.snapped(STEP), transform.basis.z.snapped(STEP),
		bounds.position.snapped(STEP), bounds.size.snapped(STEP), mesh.get_surface_count(),
	]
