extends Node3D
## Presentation only. Mount after facility furniture; no authority or save changes.
const CATALOG := "res://assets/campus/decor/service_rooms/profiles.json"
var catalog: Dictionary = {}
var built: Dictionary = {}
var materials: Dictionary = {}

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if parsed is Dictionary: catalog = parsed

func mount_profile(id: String, campus: Node3D, generic_root: Node3D = null) -> bool:
	if built.has(id) and is_instance_valid(built[id]): return true
	if not is_instance_valid(campus): return false
	var profile: Dictionary = catalog.get("profiles", {}).get(id, {})
	if profile.is_empty(): return false
	var root := Node3D.new()
	root.name = "ServiceDecor_" + id
	var origin: Array = profile.get("origin", [0,0,0])
	root.position = Vector3(float(origin[0]), float(origin[1]), float(origin[2]))
	for group in profile.get("groups", []):
		var mesh: Mesh = load(str(group.get("mesh", "")))
		if mesh == null:
			root.free()
			return false
		var name: String = str(group.get("material", ""))
		if not materials.has(name):
			var spec: Array = catalog.get("materials", {}).get(name, [])
			if spec.size() != 3:
				root.free()
				return false
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(str(spec[0]))
			mat.roughness = float(spec[1])
			mat.metallic = float(spec[2])
			materials[name] = mat
		var instance := MeshInstance3D.new()
		instance.name = name.to_pascal_case()
		instance.mesh = mesh
		instance.material_override = materials[name]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	_add_solid_furniture(root, profile)
	campus.add_child(root)
	built[id] = root
	if is_instance_valid(generic_root): generic_root.visible = false
	if campus.has_method("register_content") and id in ["gym", "washroom_1", "washroom_2"]:
		campus.call("register_content", id, root)
	return true

func _add_solid_furniture(root: Node3D, profile: Dictionary) -> void:
	# Generated bounds are local to the profile origin. Keep cubicle openings
	# and wall art out of this set; only self-contained floor props are solid.
	var body := StaticBody3D.new()
	body.name = "ServiceFurnitureCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	for item in profile.get("objects", []):
		if str(item.get("role", "")) != "furniture": continue
		var name := str(item.get("name", ""))
		if not (name.begins_with("ventilated_locker") or name.begins_with("lift_alcove_bench") or name.begins_with("lift_alcove_plant") or name.begins_with("trophy")):
			continue
		var low: Array = item.min
		var high: Array = item.max
		var min_point := Vector3(float(low[0]), float(low[1]), float(low[2]))
		var max_point := Vector3(float(high[0]), float(high[1]), float(high[2]))
		var shape := BoxShape3D.new()
		shape.size = max_point - min_point
		var hit := CollisionShape3D.new()
		hit.shape = shape
		hit.position = (min_point + max_point) * .5
		body.add_child(hit)
	if body.get_child_count() > 0: root.add_child(body)
	else: body.free()

func mount_all(campus: Node3D, generic: Node = null) -> Dictionary:
	var result := {}
	for id in ["gym", "washroom_1", "washroom_2", "circulation_0", "circulation_1"]:
		var old: Node3D = null
		if is_instance_valid(generic) and generic.has_method("get_room_root"):
			old = generic.call("get_room_root", id)
		result[id] = mount_profile(id, campus, old)
	return result
