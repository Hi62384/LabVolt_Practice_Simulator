extends SceneTree

const Avatar = preload("res://scripts/avatar_model.gd")
const Muscles = preload("res://scripts/campus/facilities/muscle_visual.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var model: Node3D = Avatar.build(FileAccess.get_file_as_bytes("res://assets/default_avatar.glb"))
	if model == null:
		push_error("Default avatar could not be loaded")
		quit(1);return
	root.add_child(model)
	var meshes: Array[MeshInstance3D] = []
	for path in ["Body/TailoredTop", "Body/ArmL/Sleeve", "Body/ArmR/Sleeve2", "LegL/Trouser", "LegR/Trouser2"]:
		var mesh := model.get_node_or_null(path) as MeshInstance3D
		if mesh == null:
			push_error("Missing exported avatar mesh: " + path)
			quit(1);return
		meshes.append(mesh)
	var originals: Array[Mesh] = []
	for mesh in meshes: originals.append(mesh.mesh)
	var sizes := {"chest":1.0,"biceps":1.0,"triceps":1.0,"quadriceps":1.0,"hamstrings":1.0}
	Muscles.apply(model, sizes)
	var grown: Array[AABB] = []
	for i in meshes.size():
		if meshes[i].mesh == originals[i] or meshes[i].mesh.get_aabb().size.length() <= originals[i].get_aabb().size.length():
			push_error("Exported avatar mesh did not grow: " + str(meshes[i].get_path()))
			quit(1);return
		grown.append(meshes[i].mesh.get_aabb())
	Muscles.apply(model, sizes)
	for i in meshes.size():
		if not meshes[i].mesh.get_aabb().is_equal_approx(grown[i]):
			push_error("Growth accumulated across updates")
			quit(1);return
	Muscles.apply(model, {})
	for i in meshes.size():
		if meshes[i].mesh != originals[i]:
			push_error("Original avatar mesh was not restored")
			quit(1);return
	var coordinator = preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not coordinator.load_catalog():
		push_error("Cosmetics catalog did not load")
		quit(1);return
	var customized := {"body":{"width":1.2}, "equipped":{"top_inner":{"id":"tops.harbor_fitted_tee", "parameters":{}}}}
	var path := "user://gym_test_avatar.glb"
	if preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd").save_glb(customized, coordinator.catalog, path) != OK:
		push_error("Could not export customized avatar")
		quit(1);return
	var dressed: Node3D = Avatar.build(FileAccess.get_file_as_bytes(path))
	if dressed == null:
		push_error("Could not load customized avatar")
		quit(1);return
	root.add_child(dressed)
	for arm_name in ["ArmL", "ArmR"]:
		var arm := dressed.get_node_or_null("Body/" + arm_name)
		if arm == null:
			push_error("Missing customized avatar arm")
			quit(1);return
		var sleeve: Node3D
		var forearm: MeshInstance3D
		for child in arm.get_children():
			if str(child.name).begins_with("Sleeve"):sleeve=child
			if str(child.name).begins_with("VisibleForearm"):forearm=child
		if sleeve == null or forearm == null:
			push_error("Missing exported sleeve or exposed forearm: " + arm_name)
			quit(1);return
		var candidates := sleeve.find_children("*", "MeshInstance3D", true, false)
		var sleeve_mesh := sleeve as MeshInstance3D if sleeve is MeshInstance3D else (candidates[0] as MeshInstance3D if not candidates.is_empty() else null)
		if sleeve_mesh == null:
			push_error("Missing exported sleeve geometry")
			quit(1);return
		var original_sleeve := sleeve_mesh.mesh
		var original_forearm := forearm.mesh
		Muscles.apply(dressed,{"biceps":1.0,"triceps":1.0,"forearms":1.0})
		if sleeve_mesh.mesh == original_sleeve or forearm.mesh == original_forearm:
			push_error("Customized clothing or exposed skin was not deformed")
			quit(1);return
		Muscles.apply(dressed,{})
	print("GYM_EXPORTED_AVATAR PASS")
	quit(0)
