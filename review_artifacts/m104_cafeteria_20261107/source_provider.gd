extends Node3D
## Room-local presentation. Integrator mounts this only after the functional rooms exist.
const PATH := "res://assets/campus/decor/social_rooms/"
const IDS := ["cafeteria", "tim_hortons", "subway", "library", "study"]
var catalog: Dictionary = {}
var roots: Dictionary = {}
var materials: Dictionary = {}
var replaced_visuals: Dictionary = {}

func _init() -> void:
	var file := FileAccess.open(PATH + "profiles.json", FileAccess.READ)
	if file:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary: catalog = parsed

func has_room(id: String) -> bool:
	return id in IDS and catalog.get("rooms", {}).has(id)

func build_room(id: String, registry: Object, campus: Node3D) -> bool:
	if roots.has(id) and is_instance_valid(roots[id]): return true
	if not has_room(id) or not is_instance_valid(registry) or not is_instance_valid(campus): return false
	var room: Dictionary = registry.get_room(id)
	if room.is_empty() or room.get("center", []) != catalog.rooms[id].center: return false
	var profile: Dictionary = catalog.rooms[id]
	var stage := Node3D.new()
	stage.name = "SocialDecor_" + id
	for group in profile.groups:
		var path: String = PATH + "meshes/" + str(group.mesh) + ".obj"
		var mesh: Mesh = load(path)
		if mesh == null:
			stage.free()
			return false
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = group.items.size()
		for i in group.items.size():
			var t: Array = group.items[i]
			var basis := Basis(Vector3.UP, deg_to_rad(float(t[3]))).scaled(Vector3(float(t[4]), float(t[5]), float(t[6])))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(float(t[0]), float(t[1]), float(t[2]))))
		var node := MultiMeshInstance3D.new()
		node.name = str(group.mesh).to_pascal_case()
		node.multimesh = mm
		node.material_override = _material(str(group.material))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 37
		stage.add_child(node)
	# Signs are wall-fixed labels. No free-standing floating explanatory billboards.
	for item in profile.signs:
		var label := Label3D.new()
		label.text = str(item.text)
		label.font_size = 40
		label.pixel_size = .003
		label.outline_size = 5
		label.modulate = Color(str(catalog.palette.get(str(item.color), {}).get("color", "eee2c7")))
		label.position = Vector3(float(item.position[0]), float(item.position[1]), float(item.position[2]))
		label.rotation.y = deg_to_rad(float(item.yaw))
		label.visibility_range_end = 19
		stage.add_child(label)
	var c: Array = profile.center
	stage.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
	stage.visible = false
	campus.add_child(stage)
	if not campus.register_content(id, stage):
		stage.queue_free()
		return false
	roots[id] = stage
	return true

func adopt_restaurant_visuals(id: String, furniture: Node3D) -> bool:
	# FacilityRoom._restaurant creates direct BoxMesh children for its fixed
	# counter, four tables and chairs. Its collision bodies are their children.
	# Keep labels, stations, food state and every dynamically placed food prop.
	if not id in ["tim_hortons", "subway"] or not roots.has(id) or not is_instance_valid(furniture): return false
	if replaced_visuals.has(id): return true
	var expected := [
		Vector3(0,.55,-2.5), Vector3(0,1.13,-2.5), Vector3(0,1.65,-2.8)
	]
	for i in 4:
		var at := Vector3(-4.5+(i%2)*4.2,0,1+(i/2)*2.7)
		expected.append_array([at+Vector3(0,.75,0),at+Vector3(0,.36,0),at+Vector3(0,.42,.95),at+Vector3(0,.85,1.22)])
	var matches: Array = []
	for child in furniture.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			for point in expected:
				if child.position.distance_to(point)<.001:
					matches.append(child)
					break
	if matches.size()!=expected.size(): return false
	for visual in matches: visual.visible = false
	replaced_visuals[id] = matches
	return true

func restore_restaurant_visuals(id: String) -> void:
	for visual in replaced_visuals.get(id, []):
		if is_instance_valid(visual): visual.visible = true
	replaced_visuals.erase(id)

func seating_points(id: String) -> Array:
	# Presentation coordinates for a future existing seat API; no authority
	# or interaction is installed by this module.
	if not has_room(id): return []
	var result: Array = []
	var c: Array = catalog.rooms[id].center
	for point in catalog.rooms[id].seat_visuals:
		result.append(Vector3(float(c[0])+float(point[0]),float(c[1])+float(point[1]),float(c[2])+float(point[2])))
	return result

func cafeteria_seat_anchors() -> Dictionary:
	# FacilityHost's existing sit/stand state keeps the player's original standing
	# position and locks movement. Anchors are approach points behind chair backs.
	var result: Dictionary = {}
	var points := seating_points("cafeteria")
	for i in points.size():
		var center: Vector3 = points[i]
		var local: Array = catalog.rooms.cafeteria.seat_visuals[i]
		var direction := Basis(Vector3.UP, deg_to_rad(float(local[3]))) * Vector3(0,0,.65)
		result["cafeteria/seat_%02d" % i] = {"room_id":"cafeteria", "kind":"seat", "position":center+direction}
	return result

func nearest_cafeteria_seat(point: Vector3, max_distance: float=2.5) -> Dictionary:
	var best := {}
	var distance := max_distance
	for id in cafeteria_seat_anchors():
		var anchor: Dictionary = cafeteria_seat_anchors()[id]
		var delta: float = point.distance_to(anchor.position)
		if delta<=distance:
			best = {"id":id,"kind":"seat"}
			distance = delta
	return best

func _material(id: String) -> StandardMaterial3D:
	if materials.has(id): return materials[id]
	var info: Dictionary = catalog.palette.get(id, {})
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(str(info.get("color", "eeeeee")))
	mat.roughness = float(info.get("roughness", .75))
	mat.metallic = float(info.get("metallic", 0))
	if info.has("emission"):
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = float(info.emission)
	materials[id] = mat
	return mat
