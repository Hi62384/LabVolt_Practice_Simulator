extends Node3D

const CATALOG := "res://assets/campus/lighting/baked/campus_lightmaps.scn"
const BAKED_CASTER_LAYER := 1 << 19

var _campus: Node3D
var _lightmap: LightmapGI
var _entries := {}
var _bound := {}
var _fixture_shadows := {}
var _enabled := true
var _architecture_batches: Array[Dictionary] = []

func has_active_sun_mask() -> bool:
	return _enabled and _lightmap != null and _lightmap.shadowmask_mode != LightmapGIData.SHADOWMASK_MODE_NONE

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
	var rig := get_parent().get_node_or_null("CampusLightingRig") as CampusLightingRig
	if not runtime_data.get_shadowmask_textures().is_empty() and (rig == null or not rig.animate_day_cycle):
		_lightmap.shadowmask_mode = LightmapGIData.SHADOWMASK_MODE_OVERLAY
	add_child(_lightmap)
	refresh_visual_settings(graphics.options)
	graphics.changed.connect(_settings_changed)
	for node in campus.find_children("*", "MeshInstance3D", true, false):
		_bind(node)
	_batch_architecture(graphics)
	for light in campus.find_children("*", "Light3D", true, false):
		_register_fixture(light)
	get_tree().node_added.connect(_node_added)

func _batch_architecture(graphics: Node) -> void:
	var groups := {}
	for binding in _bound.values():
		var node := (binding[0] as WeakRef).get_ref() as MeshInstance3D
		if not is_instance_valid(node) or not node.visible or not node.has_meta("campus_architecture"):
			continue
		if node.mesh.get_surface_count() != 1 or node.material_overlay != null or node.visibility_parent != NodePath():
			continue
		if binding[2] != 1:
			continue
		var material := node.get_active_material(0) as StandardMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var origin := node.global_position
		var cell := Vector3i(floori(origin.x / 12.0), floori(origin.y / 5.0), floori(origin.z / 12.0))
		var original: Dictionary = graphics.originals.get(node.get_instance_id(), {})
		var fine: bool = original.get("fine", false)
		var entry: Array = binding[1]
		var key := [node.get_parent().get_instance_id(), cell, material.get_instance_id(), entry[2],
			node.gi_mode, original.get("cast", node.cast_shadow), fine,
			node.visibility_range_begin, original.get("end", node.visibility_range_end),
			node.visibility_range_begin_margin, node.visibility_range_end_margin,
			node.visibility_range_fade_mode, node.ignore_occlusion_culling]
		if not groups.has(key):
			groups[key] = []
		groups[key].append([node, entry[1]])
	for key in groups:
		var group: Array = groups[key]
		if group.size() >= 2:
			_merge_architecture(group, key)

func _merge_architecture(group: Array, key: Array) -> void:
	var first: MeshInstance3D = group[0][0]
	var parent := first.get_parent() as Node3D
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for source in group:
		var node: MeshInstance3D = source[0]
		var rect: Rect2 = source[1]
		var arrays := node.mesh.surface_get_arrays(0)
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		if uv2.is_empty():
			return
		for index in uv2.size():
			uv2[index] = rect.position + uv2[index] * rect.size
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		var surface := ArrayMesh.new()
		surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		tool.append_from(surface, 0, node.transform)
	var batch := MeshInstance3D.new()
	batch.name = "BakedArchitectureChunk"
	batch.mesh = tool.commit()
	batch.material_override = first.get_active_material(0)
	batch.gi_mode = key[4]
	batch.cast_shadow = key[5]
	batch.set_meta("batch_fine_detail", key[6])
	batch.visibility_range_begin = key[7]
	batch.visibility_range_end = key[8]
	batch.visibility_range_begin_margin = key[9]
	batch.visibility_range_end_margin = key[10]
	batch.visibility_range_fade_mode = key[11]
	batch.ignore_occlusion_culling = key[12]
	parent.add_child(batch)
	var entry := [null, Rect2(0, 0, 1, 1), key[3]]
	_architecture_batches.append({"batch": batch, "entry": entry})
	_apply(batch, entry, 1)
	for source in group:
		source[0].set_meta("baked_architecture_source", true)
		source[0].hide()

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
	for record in _architecture_batches:
		_apply(record.batch, record.entry, 1)
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
