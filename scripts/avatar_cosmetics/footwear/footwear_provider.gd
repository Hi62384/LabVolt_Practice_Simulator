class_name FootwearProvider
extends RefCounted

## Adapter for baked footwear assets. It deliberately knows the current toon
## attachment seam, while keeping definitions compatible with AvatarCore v1.
const FOOT_CENTER := Vector3(0.0, -0.74, 0.045)
const Toon := preload("res://scripts/toon_character.gd")
const AvatarCore := preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")

static func instantiate(definition: Dictionary, parameters: Dictionary, body: Dictionary) -> Node3D:
	var resource := load(str(definition.get("scene", ""))) as PackedScene
	if resource == null:
		return null
	var pair := Node3D.new()
	pair.name = "FootwearPair"
	var fit_errors := validate_fit(body)
	if not fit_errors.is_empty():
		push_warning("Footwear fit rejected: " + "; ".join(fit_errors))
		pair.free()
		return null
	var feet := float(body.get("feet", 1.0))
	var leg_length := float(body.get("leg_length", 1.0))
	var authored_fit := _authored_fit(definition)
	for side in ["Left", "Right"]:
		var shoe := resource.instantiate() as Node3D
		shoe.name = side + "Footwear"
		# Cancel the parent leg's Y scaling so long/short legs move the shoe but do
		# not squash its construction. Foot size still gives a restrained Y fit.
		shoe.scale = Vector3(feet, lerpf(1.0, feet, 0.32) / leg_length, feet) * authored_fit.scale
		shoe.position = authored_fit.offset
		_apply_instance_materials(shoe, definition.get("materials", {}), parameters)
		if definition.get("id", "") == "shoes.trail_sandal":
			var skin := Toon.material(str(body.get("skin", "deb08c")))
			Toon.ellipsoid(shoe, Vector3(0, .023, .038), Vector3(.080, .041, .137), skin, "SandalFoot")
			Toon.ellipsoid(shoe, Vector3(0, .060, -.077), Vector3(.056, .079, .065), skin, "SandalAnkle")
		pair.add_child(shoe)
	return pair

static func validate_fit(body: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field in ["feet", "leg_length"]:
		var value = body.get(field, 1.0)
		if not (value is int or value is float) or not is_finite(float(value)):
			errors.append(field + " must be finite")
		elif float(value) < AvatarCore.BODY_MIN or float(value) > AvatarCore.BODY_MAX:
			errors.append(field + " is outside core range " + str(AvatarCore.BODY_MIN) + "–" + str(AvatarCore.BODY_MAX))
	return errors

## Moves the two instance-local shoes under LegL/LegR so existing walk, run,
## jump, crouch and seated transforms are inherited without touching the rig.
static func attach_to_avatar(avatar: Node3D, pair: Node3D) -> bool:
	if avatar == null or pair == null:
		return false
	var left_leg := avatar.get_node_or_null("LegL") as Node3D
	var right_leg := avatar.get_node_or_null("LegR") as Node3D
	if left_leg == null or right_leg == null or pair.get_child_count() != 2:
		return false
	var shoes := [pair.get_child(0), pair.get_child(1)]
	for index in 2:
		var shoe := shoes[index] as Node3D
		pair.remove_child(shoe)
		(left_leg if index == 0 else right_leg).add_child(shoe)
		shoe.position += FOOT_CENTER
	# The empty pair can be freed by the caller or retained as an equip handle.
	return true

static func _authored_fit(definition: Dictionary) -> Dictionary:
	var fit = definition.get("fit", {})
	if not fit is Dictionary:
		fit = {}
	var raw_scale = fit.get("scale", [1.0, 1.0, 1.0])
	var raw_offset = fit.get("offset", [0.0, 0.0, 0.0])
	if not raw_scale is Array or raw_scale.size() != 3:
		raw_scale = [1.0, 1.0, 1.0]
	if not raw_offset is Array or raw_offset.size() != 3:
		raw_offset = [0.0, 0.0, 0.0]
	return {
		"scale": Vector3(float(raw_scale[0]), float(raw_scale[1]), float(raw_scale[2])),
		"offset": Vector3(float(raw_offset[0]), float(raw_offset[1]), float(raw_offset[2])),
	}

static func _apply_instance_materials(root: Node, regions: Dictionary, parameters: Dictionary) -> void:
	var colors := {
		"primary_regions": str(parameters.get("base_color", "FFFFFF")),
		"secondary_regions": str(parameters.get("accent_color", "FFFFFF")),
		"sole_regions": str(parameters.get("sole_color", "FFFFFF")),
	}
	var region_colors: Dictionary = {}
	for region_group in colors:
		for material_name in regions.get(region_group, []):
			region_colors[str(material_name)] = Color.from_string(colors[region_group], Color.WHITE)
	for child in _all_meshes(root):
		var mesh_instance := child as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source == null:
				continue
			var local := source.duplicate(true)
			if local is StandardMaterial3D:
				var standard := local as StandardMaterial3D
				if region_colors.has(str(source.resource_name)):
					standard.albedo_color = region_colors[str(source.resource_name)]
					standard.albedo_texture = null
				_apply_finish(standard, str(parameters.get("finish", "")))
				if str(source.resource_name) == "neon":
					standard.emission_energy_multiplier = clampf(float(parameters.get("glow", 1.0)), 0.0, 2.0)
			mesh_instance.set_surface_override_material(surface, local)

static func _apply_finish(material: StandardMaterial3D, finish: String) -> void:
	match finish:
		"weatherproof": material.roughness = 0.48
		"oiled": material.roughness = 0.34
		"matte": material.roughness = 0.72
		"worn": material.roughness = 0.58
		"polished": material.roughness = 0.22
		"satin": material.roughness = 0.42

static func _all_meshes(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D:
			result.append(current)
		for child in current.get_children():
			pending.append(child)
	return result
