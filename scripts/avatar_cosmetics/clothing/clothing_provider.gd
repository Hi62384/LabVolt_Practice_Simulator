class_name ClothingProvider
extends RefCounted
const BodyFit = preload("res://scripts/avatar_cosmetics/body_deformation/body_fit.gd")

## Baked segmented garments for the current independently animated toon rig.
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")

static func instantiate(definition: Dictionary, parameters: Dictionary, body: Dictionary, fit_cache := {}) -> Node3D:
	var packed := load(str(definition.get("scene", ""))) as PackedScene
	if packed == null: return null
	var garment := packed.instantiate() as Node3D
	garment.name = "Clothing_" + str(definition.get("id", "item")).replace(".", "_")
	if body.get("__live_preview", false):
		var fit_fields := ["width", "waist", "shoulders", "torso_length", "torso_width", "hips",
			"neck_width", "arm_width", "leg_width", "build", "__legacy_body_depth", "__legacy_outfit"]
		var key := [parameters.get("fit", 1.0)]
		for field in fit_fields:
			key.append(body.get(field))
		var cached: Dictionary = fit_cache.get(definition.id, {})
		if cached.get("key") == key:
			var meshes := _all_meshes(garment)
			for i in garment.get_child_count():
				garment.get_child(i).transform = cached.parts[i]
			for i in meshes.size():
				meshes[i].mesh = cached.meshes[i]
				meshes[i].transform = cached.transforms[i]
		else:
			_apply_fit(garment, definition, body, parameters)
			var meshes := []
			var transforms := []
			for mesh in _all_meshes(garment):
				meshes.append(mesh.mesh)
				transforms.append(mesh.transform)
			if fit_cache.size() >= 8: fit_cache.clear()
			var parts := []
			for part in garment.get_children(): parts.append(part.transform)
			fit_cache[definition.id] = {"key":key, "meshes":meshes, "transforms":transforms, "parts":parts}
	else:
		_apply_fit(garment, definition, body, parameters)
	_apply_instance_materials(garment, definition.get("materials", {}), parameters)
	return garment

static func attach_to_avatar(avatar: Node3D, garment: Node3D) -> bool:
	if avatar == null or garment == null: return false
	var moved := 0
	for child in garment.get_children().duplicate():
		var target: Node3D = null
		match str(child.name):
			"SleeveL": target = avatar.get_node_or_null("Body/ArmL")
			"SleeveR": target = avatar.get_node_or_null("Body/ArmR")
			"LegL": target = avatar.get_node_or_null("LegL")
			"LegR": target = avatar.get_node_or_null("LegR")
			"Torso", "Waist": target = avatar.get_node_or_null("Body")
		if target != null:
			child.owner = null
			garment.remove_child(child); target.add_child(child); moved += 1
	return moved > 0

static func _apply_fit(root: Node, definition: Dictionary, body: Dictionary, parameters: Dictionary) -> void:
	BodyFit.fit_clothing(root as Node3D,definition,body,parameters)

static func _deform_torso(mesh_instance: MeshInstance3D, overall: float, waist: float, shoulders: float, fit: float) -> void:
	if mesh_instance == null or mesh_instance.mesh == null: return
	_deform_mesh(mesh_instance, func(vertex: Vector3) -> Vector3:
		# Mirrors toon_character._torso_width_at exactly at its .87/.1.24 endpoints.
		var row_width := lerpf(waist, shoulders, smoothstep(.87, 1.24, vertex.y))
		return Vector3(vertex.x * overall * row_width * fit, vertex.y, vertex.z * fit)
	)

static func _deform_waist(mesh_instance: MeshInstance3D, overall: float, waist: float, hips: float, fit: float) -> void:
	if mesh_instance == null or mesh_instance.mesh == null: return
	_deform_mesh(mesh_instance, func(vertex: Vector3) -> Vector3:
		var row_width := lerpf(hips, waist, smoothstep(.82, .91, vertex.y))
		return Vector3(vertex.x * overall * row_width * fit, vertex.y, vertex.z * fit)
	)

static func _deform_mesh(mesh_instance: MeshInstance3D, transform_vertex: Callable) -> void:
	var source := mesh_instance.mesh
	var deformed := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for index in vertices.size(): vertices[index] = transform_vertex.call(vertices[index])
		arrays[Mesh.ARRAY_VERTEX] = vertices
		# Generated garments are unindexed triangle streams; recompute normals after
		# the non-uniform row deformation instead of retaining stale source normals.
		var normals := PackedVector3Array(); normals.resize(vertices.size())
		for index in range(0, vertices.size(), 3):
			var normal := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index]).normalized()
			normals[index] = normal; normals[index + 1] = normal; normals[index + 2] = normal
		arrays[Mesh.ARRAY_NORMAL] = normals
		deformed.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays)
		deformed.surface_set_material(surface, source.surface_get_material(surface))
	mesh_instance.mesh = deformed

static func _apply_instance_materials(root: Node, regions: Dictionary, parameters: Dictionary) -> void:
	var colors := {"primary_regions": str(parameters.get("primary_color", "FFFFFF")), "secondary_regions": str(parameters.get("secondary_color", "FFFFFF")), "detail_regions": str(parameters.get("detail_color", "FFFFFF"))}
	var map := {}
	for group in colors:
		for material_name in regions.get(group, []): map[str(material_name)] = Color.from_string(colors[group], Color.WHITE)
	for mesh in _all_meshes(root):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			if source == null: continue
			var local := source.duplicate(true)
			if local is StandardMaterial3D:
				var standard := local as StandardMaterial3D
				if map.has(str(source.resource_name)):
					standard.albedo_color = map[str(source.resource_name)]
					standard.albedo_texture = null
				match str(parameters.get("material", "")):
					"washed": standard.roughness = minf(1.0, standard.roughness + .12)
					"crisp": standard.roughness = maxf(.25, standard.roughness - .12)
			mesh.set_surface_override_material(surface, local)

static func _all_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []; var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D: result.append(node)
		for child in node.get_children(): pending.append(child)
	return result
