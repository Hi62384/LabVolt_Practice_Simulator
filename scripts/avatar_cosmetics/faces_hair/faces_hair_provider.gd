class_name FacesHairProvider
extends RefCounted

## Baked head-cosmetic adapter for the current labvolt_toon_v1 seam.
## All scenes attach below Body/Head and inherit its animation transform.
const HEAD_PATH := NodePath("Body/Head")
const LEGACY_STATE_META := &"faces_hair_legacy_state"
const CATEGORY_META := &"faces_hair_category"
const Warp := preload("res://scripts/avatar_cosmetics/body_deformation/mesh_warp.gd")
# Head-local profile shared by the authored face and beard geometry.
const HEAD_ROWS := [Vector3(-.205,0,0), Vector3(-.19,.10,.10), Vector3(-.12,.195,.148), Vector3(.015,.225,.17), Vector3(.14,.205,.155), Vector3(.22,.135,.105), Vector3(.24,0,0)]

static func instantiate(definition: Dictionary, parameters: Dictionary, body: Dictionary) -> Node3D:
	var scene_path := _variant_scene(definition, parameters)
	var resource := load(scene_path) as PackedScene
	if resource == null:
		return null
	var instance := resource.instantiate() as Node3D
	if instance == null:
		return null
	instance.name = "Cosmetic_" + str(definition.get("id", "item")).replace(".", "_")
	# The existing toon already applies head * head_width/head_height on
	# Body/Head. Keep authored coordinates local so face, hair, and beard fit
	# inherit the full sanitized 0.65-1.4 range without double compensation.
	instance.set_meta(CATEGORY_META, str(definition.get("category", "")))
	_shape(instance, str(definition.get("category", "")), parameters, body.get("__live_preview", false))
	_apply_instance_materials(instance, definition, parameters, body)
	return instance

static func attach_to_avatar(avatar: Node3D, instance: Node3D, definition: Dictionary) -> bool:
	if avatar == null or instance == null:
		return false
	var head := avatar.get_node_or_null(HEAD_PATH) as Node3D
	if head == null:
		return false
	if definition.get("category") == "faces":
		var skin := head.get_node_or_null("Face") as MeshInstance3D
		if skin != null:
			instance.scale.x = skin.scale.x
	head.add_child(instance)
	_hide_legacy(head, str(definition.get("category", "")))
	return true

static func detach_from_avatar(avatar: Node3D, instance: Node3D) -> bool:
	if avatar == null or instance == null:
		return false
	var head := avatar.get_node_or_null(HEAD_PATH) as Node3D
	if head == null or instance.get_parent() != head:
		return false
	_restore_legacy(head, str(instance.get_meta(CATEGORY_META, "")))
	head.remove_child(instance)
	return true

static func _variant_scene(definition: Dictionary, parameters: Dictionary) -> String:
	var fallback := str(definition.get("scene", ""))
	var variants = definition.get("variants", {})
	if not variants is Dictionary or variants.is_empty():
		return fallback
	var key := str(parameters.get("length", definition.get("parameters", {}).get("length", {}).get("default", "default")))
	return str(variants.get(key, fallback))

static func _apply_instance_materials(root: Node, definition: Dictionary, parameters: Dictionary, body: Dictionary) -> void:
	var category := str(definition.get("category", ""))
	var colors := {
		"hair": Color.from_string(str(parameters.get("color", "352B31")), Color("352B31")),
		"hair_highlight": Color.from_string(str(parameters.get("highlight", parameters.get("color", "68504A"))), Color("68504A")),
		"hair_tip": Color.from_string(str(parameters.get("tip_color", "DF5C96")), Color("DF5C96")),
		"brow": Color.from_string(str(parameters.get("eyebrow_color", "352B31")), Color("352B31")),
		"iris": Color.from_string(str(parameters.get("eye_color", "397A83")), Color("397A83")),
		"lip": Color.from_string(str(parameters.get("lip_color", "763B44")), Color("763B44")),
		"skin_detail": Color.from_string(str(body.get("skin", "DEB08C")), Color("DEB08C")),
	}
	for node in _all_meshes(root):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source == null:
				continue
			var local := source.duplicate(true)
			if local is StandardMaterial3D:
				var material := local as StandardMaterial3D
				var region := str(source.resource_name)
				if colors.has(region):
					material.albedo_color = colors[region]
					material.albedo_texture = null
				if region in ["hair", "hair_highlight", "hair_tip", "brow"]:
					var shine := clampf(float(parameters.get("shine", 0.35)), 0.0, 1.0)
					material.roughness = lerpf(0.86, 0.36, shine)
			mesh_instance.set_surface_override_material(surface, local)
	if category == "hair":
		var volume := clampf(float(parameters.get("volume", 1.0)), 0.9, 1.12)
		root.scale *= Vector3.ONE * (1.0 + (volume - 1.0) * 0.22)

static func _skin_front(x: float, y: float) -> float:
	for i in range(1, HEAD_ROWS.size()):
		var low: Vector3 = HEAD_ROWS[i - 1]
		var high: Vector3 = HEAD_ROWS[i]
		if y <= high.x:
			var point := low.lerp(high, clampf(inverse_lerp(low.x, high.x, y), 0.0, 1.0))
			if point.y <= .0001:return 0.0
			return point.z * sqrt(maxf(0.0, 1.0 - (x / point.y) ** 2.0))
	return 0.0

static func _shape(root: Node3D, category: String, parameters: Dictionary, live: bool) -> void:
	match category:
		"faces":
			var eye := float(parameters.get("eye_size", 1.0))
			var brow := float(parameters.get("brow_height", 0.0))
			var mouth := float(parameters.get("mouth_width", 1.0))
			if is_equal_approx(eye, 1.0) and is_zero_approx(brow) and is_equal_approx(mouth, 1.0):return
			Warp.deform_tree(root, func(v: Vector3) -> Vector3:
				var x := v.x * lerpf(mouth, 1.0, smoothstep(-.088, -.061, v.y))
				var y := v.y + brow * smoothstep(.068, .101, v.y)
				var eye_weight := smoothstep(.035, .065, absf(v.x)) * (1.0 - smoothstep(.060, .102, v.y)) * smoothstep(-.055, -.021, v.y)
				x += (v.x - signf(v.x) * .091) * (eye - 1.0) * eye_weight
				y += (v.y - .028) * (eye - 1.0) * eye_weight
				return _reseat(v, x, y, 1.0), live)
		"facial_hair":
			var density := clampf(float(parameters.get("density", 1.0)), .6, 1.0)
			var width := float(parameters.get("width", 1.0))
			var depth := float(parameters.get("depth", 1.0))
			if is_equal_approx(density, 1.0) and is_equal_approx(width, 1.0) and is_equal_approx(depth, 1.0):return
			var bulk := lerpf(.25, 1.0, inverse_lerp(.6, 1.0, density)) * depth
			Warp.deform_tree(root, func(v: Vector3) -> Vector3: return _reseat(v, v.x * width, v.y, bulk), live)
		"hair":
			var lift := float(parameters.get("crown_lift", 1.0))
			var side_volume := float(parameters.get("side_volume", 1.0))
			if not is_equal_approx(lift, 1.0) or not is_equal_approx(side_volume, 1.0):
				Warp.deform_tree(root, func(v: Vector3) -> Vector3:
					return Vector3(v.x * lerpf(1.0, side_volume, smoothstep(.11, .24, absf(v.x))), v.y + maxf(0.0, v.y - .14) * (lift - 1.0), v.z), live)

static func _reseat(v: Vector3, x: float, y: float, bulk: float) -> Vector3:
	var thickness := v.z - _skin_front(v.x, v.y)
	return Vector3(x, y, _skin_front(x, y) + thickness * bulk if thickness > 0.0 else _skin_front(x, y) + thickness)

static func _hide_legacy(head: Node3D, category: String) -> void:
	var state: Dictionary = head.get_meta(LEGACY_STATE_META, {})
	if state.has(category):
		var active: Dictionary = state[category]
		active["count"] = int(active.get("count", 0)) + 1
		state[category] = active
		head.set_meta(LEGACY_STATE_META, state)
		return
	var names := []
	if category == "hair":
		names = ["Hair"]
	elif category == "facial_hair":
		names = ["Beard", "Mustache"]
	elif category == "faces":
		names = ["Eye", "Iris", "Pupil", "EyeSpark", "Nose", "Freckle", "Teeth"]
	var hidden: Array = []
	for node in _descendants(head):
		var should_hide := false
		# Legacy brows and mouth are unnamed CylinderMesh links. Their vertical
		# bands are disjoint from glasses (near eye center), so suppress only
		# direct head links in the brow/mouth bands when a face preset is active.
		if category == "faces" and node is MeshInstance3D and node.get_parent() == head:
			var legacy_mesh := (node as MeshInstance3D).mesh
			if legacy_mesh is CylinderMesh and (node.position.y > 0.075 or node.position.y < -0.075):
				should_hide = true
		for prefix in names:
			if str(node.get_meta("toon_part", node.name)).begins_with(prefix):
				should_hide = true
		if should_hide and node is Node3D:
			hidden.append({"node": node, "visible": (node as Node3D).visible})
			(node as Node3D).hide()
	state[category] = {"count": 1, "hidden": hidden}
	head.set_meta(LEGACY_STATE_META, state)

static func _restore_legacy(head: Node3D, category: String) -> void:
	var state: Dictionary = head.get_meta(LEGACY_STATE_META, {})
	if not state.has(category):
		return
	var entry: Dictionary = state[category]
	entry["count"] = maxi(0, int(entry.get("count", 1)) - 1)
	if int(entry.count) > 0:
		state[category] = entry
		head.set_meta(LEGACY_STATE_META, state)
		return
	for record in entry.get("hidden", []):
		if record is Dictionary and is_instance_valid(record.get("node")):
			(record.get("node") as Node3D).visible = bool(record.get("visible", true))
	state.erase(category)
	if state.is_empty():
		head.remove_meta(LEGACY_STATE_META)
	else:
		head.set_meta(LEGACY_STATE_META, state)

static func _all_meshes(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for node in _descendants(root):
		if node is MeshInstance3D:
			result.append(node)
	return result

static func _descendants(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current != root:
			result.append(current)
		for child in current.get_children():
			pending.append(child)
	return result
