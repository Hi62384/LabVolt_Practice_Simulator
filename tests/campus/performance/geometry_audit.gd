extends SceneTree
## Bounded headless scene inventory; counts geometry, not rendered cost attribution.
var groups := {}
var primitives := {}
var materials := {}
var meshes := {}
var total := {"mesh_instances":0,"labels":0,"triangles":0,"collision_objects":0,"layer_enabled_instances":0,"layer_enabled_triangles":0}
var game: Node

func _initialize() -> void:
	call_deferred("run")

func visit(node: Node, group: String, interaction := false) -> void:
	if node is CollisionObject3D:
		total.collision_objects += 1
		interaction = true
	if node is Label3D:
		total.labels += 1
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		var triangles := 0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			triangles += int((indices.size() if indices != null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3)
			var material: Material = node.get_active_material(surface)
			if material != null:
				materials[material.get_instance_id()] = true
		meshes[mesh.get_instance_id()] = true
		total.mesh_instances += 1
		total.triangles += triangles
		if node.layers != 0:
			total.layer_enabled_instances += 1
			total.layer_enabled_triangles += triangles
		var kind := mesh.get_class()
		var entry: Dictionary = primitives.get(kind,{"instances":0,"triangles":0,"interactive_descendants":0})
		entry.instances += 1
		entry.triangles += triangles
		entry.interactive_descendants += 1 if interaction else 0
		primitives[kind] = entry
		var aggregate: Dictionary = groups.get(group,{"instances":0,"triangles":0,"interactive_instances":0})
		aggregate.instances += 1
		aggregate.triangles += triangles
		aggregate.interactive_instances += 1 if interaction else 0
		groups[group] = aggregate
	for child in node.get_children():
		visit(child,group,interaction)

func run() -> void:
	var started := Time.get_ticks_usec()
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	var optimization: Array = []
	var original_state := var_to_bytes({"ac":game.session.world_snapshot(),"dc":game.dc_lab.states})
	if OS.get_cmdline_user_args().has("--optimize=on"):
		var optimizer := preload("res://scripts/campus/performance/equipment_render_optimizer.gd").new()
		optimization = optimizer.optimize_legacy_game(game)
		optimizer.release_original_meshes()
	var state_preserved := original_state == var_to_bytes({"ac":game.session.world_snapshot(),"dc":game.dc_lab.states})
	# Inventory immediately: no sustained solver/rendered workload.
	for child in game.get_children():
		var group := str(child.name)
		if child.get_script() != null:
			group += " [" + str(child.get_script().resource_path).get_file() + "]"
		visit(child,group)
	var output := {"scope":"headless topology inventory; all nodes including hidden branches; no render-pass multiplier", "total":total,"primitives":primitives,"groups":groups,"unique_material_resources":materials.size(),"unique_mesh_resources":meshes.size(),"inventory_and_scene_load_ms":(Time.get_ticks_usec()-started)/1000.0}
	output.optimization = optimization
	output.authoritative_state_preserved = state_preserved
	var path := "user://geometry-audit.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			path = arg.trim_prefix("--output=")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	file.close()
	print("GEOMETRY AUDIT " + JSON.stringify(total) + " materials=" + str(materials.size()))
	game.free()
	quit(0 if state_preserved else 1)
