extends SceneTree
const Builder = preload("res://scripts/equipment_builder.gd")
const Optimizer = preload("res://scripts/campus/performance/equipment_render_optimizer.gd")
const Adapter = preload("res://scripts/campus/performance/equipment_builder_adapter.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)

func inventory(root_node: Node) -> Dictionary:
	var output := {"instances":0,"renderable_instances":0,"triangles":0,"renderable_triangles":0,"unique_meshes":{}}
	for node in root_node.find_children("*","MeshInstance3D",true,false):
		if node.mesh == null:
			continue
		output.instances += 1
		output.unique_meshes[node.mesh.get_instance_id()] = true
		var triangle_count := 0
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			triangle_count += int((indices.size() if indices != null and indices.size()>0 else arrays[Mesh.ARRAY_VERTEX].size())/3)
		output.triangles += triangle_count
		if node.layers != 0:
			output.renderable_instances += 1
			output.renderable_triangles += triangle_count
	output.unique_mesh_count = output.unique_meshes.size()
	output.erase("unique_meshes")
	return output

func run() -> void:
	var equipment := Builder.new()
	root.add_child(equipment)
	var started := Time.get_ticks_usec()
	equipment._reset_switches()
	equipment._build_station()
	var build_usec := Time.get_ticks_usec()-started
	var before := inventory(equipment)
	await physics_frame
	await process_frame
	var picked_body: StaticBody3D = equipment.terminal_bodies.DAQ_E0_N
	var query := PhysicsRayQueryParameters3D.create(picked_body.global_position+Vector3(0,0,0.2),picked_body.global_position-Vector3(0,0,0.1),picked_body.collision_layer)
	var original_hit: Dictionary = equipment.get_world_3d().direct_space_state.intersect_ray(query)
	check(original_hit.get("collider") == picked_body,"actual terminal raycast hits before optimization")
	var sockets := {}
	for id in equipment.terminal_bodies:
		var body: StaticBody3D = equipment.terminal_bodies[id]
		sockets[id] = {"object":body.get_instance_id(),"position":body.global_position,"layer":body.collision_layer,"mask":body.collision_mask,"shape":body.get_child(0).shape.get_instance_id()}
	var protected_nodes: Array = equipment.needle_bodies.values()
	for entry in equipment.switch_meshes.values():
		protected_nodes.append(entry.handle)
		protected_nodes.append(entry.indicator)
	var needle: Node3D = equipment.needle_bodies.AMP0
	var needle_id := needle.get_instance_id()
	var needle_child: MeshInstance3D = needle.get_child(0)
	var needle_layers := needle_child.layers
	var indicator: MeshInstance3D = equipment.switch_meshes.R_0.indicator
	var indicator_id := indicator.get_instance_id()
	var optimizer := Optimizer.new()
	var result := optimizer.optimize_equipment(equipment,protected_nodes,true)
	var after := inventory(equipment)
	var optimized_hit: Dictionary = equipment.get_world_3d().direct_space_state.intersect_ray(query)
	check(optimized_hit.get("collider") == picked_body,"actual terminal raycast still hits same body after optimization")
	check(after.renderable_triangles < before.renderable_triangles * 0.3, "curved geometry reduced by at least70% in source inventory")
	check(after.renderable_instances < before.renderable_instances * 0.65, "static panel batches reduce active geometry instances by at least35%")
	check(optimizer.cache.stats().cache_hits > 0, "identical primitive dimensions share resources")
	check(after.unique_mesh_count < before.unique_mesh_count, "resource count decreases despite panel batches")
	check(result.sockets_batched > 100,"socket batching applies only authored socket visuals")
	check(picked_body.get_node("SocketVisualBatch") != null,"socket replacement stays under original collider parent")
	var socket_arrays: Array = picked_body.get_node("SocketVisualBatch").mesh.surface_get_arrays(0)
	var packed_surface: Vector2 = socket_arrays[Mesh.ARRAY_TEX_UV2][0]
	var mount_material: StandardMaterial3D = picked_body.get_child(1).material_override
	check(absf(packed_surface.x-mount_material.metallic)<0.001 and absf(packed_surface.y-mount_material.roughness)<0.001,"socket material metalness/roughness encoded within vertex precision")
	picked_body.scale = Vector3.ONE*1.08
	check(picked_body.get_node("SocketVisualBatch").global_basis.get_scale().is_equal_approx(picked_body.global_basis.get_scale()),"selection highlight scales replacement with original socket")
	picked_body.scale = Vector3.ONE
	for id in sockets:
		var body: StaticBody3D = equipment.terminal_bodies[id]
		var expected: Dictionary = sockets[id]
		check(body.get_instance_id()==expected.object and body.global_position==expected.position and body.collision_layer==expected.layer and body.collision_mask==expected.mask and body.get_child(0).shape.get_instance_id()==expected.shape,"terminal identity/position/shape/layers preserved " + id)
	check(needle.get_instance_id()==needle_id and needle_child.layers==needle_layers,"meter needle remains independent and renderable")
	needle.rotation.z = 0.4
	check(is_equal_approx(needle.rotation.z,0.4),"existing meter rotation API remains usable")
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.GREEN
	indicator.material_override = material
	check(indicator.get_instance_id()==indicator_id and indicator.layers != 0 and indicator.material_override==material,"indicator material/state remains independent")
	var handle: Node3D = equipment.switch_meshes.R_0.handle
	handle.rotation.z = -0.38
	check(is_equal_approx(handle.rotation.z,-0.38),"switch handle animation remains usable")
	check(optimizer.optimize_equipment(equipment,protected_nodes).get("already_optimized",false),"repeated application is idempotent")
	# Shared primitive resources must retain exact silhouettes and original dimensions.
	var sphere := SphereMesh.new()
	sphere.radius = 0.011
	sphere.height = 0.022
	var replacement := optimizer.cache.replacement(sphere) as SphereMesh
	check(replacement.radius==sphere.radius and replacement.height==sphere.height and sphere.radial_segments==64,"sphere dimensions retained and original resource unmodified")
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.02
	cylinder.bottom_radius = 0.02
	cylinder.height = 0.08
	var reduced := optimizer.cache.replacement(cylinder) as CylinderMesh
	check(reduced.radial_segments==cylinder.radial_segments and reduced.rings==0 and reduced.cap_top==cylinder.cap_top and reduced.cap_bottom==cylinder.cap_bottom,"straight cylinder circumference/caps retained; redundant axial rings removed")
	optimizer.restore()
	var restored := inventory(equipment)
	check(restored==before,"restore recovers original geometry inventory exactly")
	var unsupported: StaticBody3D = picked_body.duplicate()
	root.add_child(unsupported)
	var special: StandardMaterial3D = unsupported.get_child(1).material_override.duplicate()
	special.emission_enabled = true
	unsupported.get_child(1).material_override = special
	check(not optimizer.sockets.apply(unsupported),"unsupported material features leave socket geometry independent")
	unsupported.free()
	var adapted := Adapter.new()
	root.add_child(adapted)
	started = Time.get_ticks_usec()
	adapted._reset_switches()
	adapted._build_station()
	var adapter_build_usec := Time.get_ticks_usec()-started
	var adapter_inventory := inventory(adapted)
	check(adapted.terminal_ids==equipment.terminal_ids,"drop-in builder preserves all terminal IDs")
	check(adapter_inventory.instances==before.instances,"drop-in builder preserves primitive node counts before batching")
	check(adapter_inventory.renderable_triangles==166020,"drop-in builder creates reduced geometry directly")
	for id in sockets:
		check(adapted.terminal_bodies[id].global_position==sockets[id].position,"drop-in builder preserves socket position " + id)
	var bounded_cache := preload("res://scripts/campus/performance/equipment_mesh_cache.gd").new()
	bounded_cache.max_resources = 2
	for i in 5:
		var moving := CylinderMesh.new()
		moving.height = 0.01+i*0.003
		bounded_cache.replacement(moving)
	check(bounded_cache.stats().resources==2 and bounded_cache.stats().uncached==3,"dynamic geometry lengths cannot grow cache past configured cap")
	adapted.free()
	var report := {"baseline":before,"optimized":after,"restored":restored,"optimizer":result,"baseline_build_usec":build_usec,"adapter_build_usec":adapter_build_usec,"adapter_inventory":adapter_inventory,"checks":checks,"failures":failures,"scope":"actual equipment rack; headless geometry/correctness inventory, not FPS or rendered speedup"}
	var file := FileAccess.open("user://equipment-optimizer-test.json",FileAccess.WRITE)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			file = FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	equipment.free()
	print("EQUIPMENT OPTIMIZER %d checks, %d failures | instances %d -> %d | triangles %d -> %d" % [checks,failures,before.renderable_instances,after.renderable_instances,before.renderable_triangles,after.renderable_triangles])
	quit(1 if failures else 0)
