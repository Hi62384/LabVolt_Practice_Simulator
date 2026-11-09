class_name AccessoryProvider
extends RefCounted
const BodyFit = preload("res://scripts/avatar_cosmetics/body_deformation/body_fit.gd")

const FIT_MIN := 0.65
const FIT_MAX := 1.4
const SLOT_PATHS := {"head":"Body/Head", "eyewear":"Body/Head", "ears":"Body/Head", "neck":"Body", "wrist_left":"Body/ArmL", "wrist_right":"Body/ArmR", "back":"Body"}

static func instantiate(definition: Dictionary, parameters: Dictionary, body: Dictionary) -> Node3D:
	var resource := load(str(definition.get("scene", ""))) as PackedScene
	if resource == null: return null
	var item := resource.instantiate() as Node3D
	if item == null: return null
	item.name = "Accessory_" + str(definition.get("id", "unknown")).replace(".", "_")
	_apply_fit(item, str(definition.get("slot", "")), parameters, body)
	_apply_instance_materials(item, definition.get("materials", {}), parameters)
	item.set_meta("cosmetic_id", str(definition.get("id", "")))
	return item

static func attach_to_avatar(avatar: Node3D, item: Node3D, definition: Dictionary) -> bool:
	if avatar == null or item == null: return false
	var path: String = SLOT_PATHS.get(str(definition.get("slot", "")), "")
	var anchor := avatar.get_node_or_null(path) as Node3D
	if anchor == null: return false
	anchor.add_child(item)
	return true

## Idempotent per-avatar legacy hair visibility. Call once after all head slots are
## attached and again after an unequip rebuild. Geometry/resources are untouched.
static func sync_legacy_hair(avatar: Node3D, equipped_head: Dictionary) -> void:
	if avatar == null: return
	var legacy_hair := avatar.get_node_or_null("Body/Head/Hair") as Node3D
	if legacy_hair == null: return
	var tags = equipped_head.get("tags", [])
	legacy_hair.visible = not (tags is Array and "hair_covering" in tags)

static func _apply_fit(item: Node3D, slot: String, parameters: Dictionary, body: Dictionary) -> void:
	BodyFit.fit_accessory(item,slot,body,parameters)

static func _apply_instance_materials(root: Node, regions: Dictionary, parameters: Dictionary) -> void:
	var color_keys := {"primary_regions":"primary_color", "accent_regions":"accent_color", "metal_regions":"metal_color"}
	var overrides := {}
	for group in color_keys:
		var color := str(parameters.get(color_keys[group], ""))
		if not Color.html_is_valid(color): continue
		for material_name in regions.get(group, []): overrides[str(material_name)] = Color(color)
	for mesh_instance in _all_meshes(root):
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source == null: continue
			var local := source.duplicate(true)
			if local is StandardMaterial3D:
				var standard := local as StandardMaterial3D
				if overrides.has(str(source.resource_name)):
					standard.albedo_color = overrides[str(source.resource_name)]
					standard.albedo_texture = null
				match str(parameters.get("finish", "")):
					"matte": standard.roughness = 0.78
					"polished": standard.roughness = 0.2
					"satin": standard.roughness = 0.42
			mesh_instance.set_surface_override_material(surface, local)

static func _all_meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current is MeshInstance3D: result.append(current)
		for child in current.get_children(): pending.append(child)
	return result
