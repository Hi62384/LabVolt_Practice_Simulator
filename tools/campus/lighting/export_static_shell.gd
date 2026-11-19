extends SceneTree
## Prepare the static campus geometry for a Godot editor LightmapGI bake.
## Run with an isolated user directory. The generated scene is an offline input.
const MAIN = preload("res://scenes/Main.tscn")
const OUTPUT := "user://campus_static_shell.scn"
const TEXEL_SIZE := 0.22

func _initialize() -> void:
	call_deferred("export_shell")

func export_shell() -> void:
	var game := MAIN.instantiate()
	game.set_meta("exporting_campus_lightmaps", true)
	root.add_child(game)
	game.front.entered()
	var source: Node3D = game.campus
	source.set_process(false)
	source.streamer.set_process(false)
	source.streamer.set_menu_rooms(PackedStringArray(source.room_roots.keys()))
	for frame in range(600):
		if source.streamer.queue.is_empty():
			break
		source.streamer.advance(0)
		await process_frame
	if not source.streamer.queue.is_empty():
		push_error("Some campus rooms did not finish loading: %s" % str(source.streamer.queue))
		quit(1)
		return

	var stage := Node3D.new()
	stage.name = "CampusStaticBake"
	var world := WorldEnvironment.new()
	world.environment = game.get_node("WorldEnvironment").environment.duplicate()
	stage.add_child(world)
	world.owner = stage

	var static_count := 0
	var skipped := 0
	for node in source.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.is_visible_in_tree() or _moving_branch(mesh_instance, source):
			continue
		if not _copy_geometry(mesh_instance, source, stage, static_count):
			skipped += 1
			continue
		static_count += 1

	var light_count := 0
	var light_roots: Array[Node] = [source]
	var rig := game.find_child("CampusLightingRig", true, false)
	if rig != null and not source.is_ancestor_of(rig):
		light_roots.append(rig)
	for parent in light_roots:
		for node in parent.find_children("*", "Light3D", true, false):
			var light := node as Light3D
			if not light.is_visible_in_tree() or _moving_branch(light, parent):
				continue
			var copy := light.duplicate(0) as Light3D
			copy.name = "BakeLight%04d" % light_count
			copy.transform = light.global_transform
			copy.light_bake_mode = Light3D.BAKE_DYNAMIC if light is DirectionalLight3D else Light3D.BAKE_STATIC
			stage.add_child(copy)
			copy.owner = stage
			light_count += 1

	var gi := LightmapGI.new()
	gi.name = "CampusLightmap"
	gi.directional = true
	gi.bounces = 2
	stage.add_child(gi)
	gi.owner = stage
	var scene := PackedScene.new()
	var result := scene.pack(stage)
	if result == OK:
		result = ResourceSaver.save(scene, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	stage.free()
	game.front.leave_game()
	game.queue_free()
	await process_frame
	if result != OK or static_count == 0 or light_count == 0:
		push_error("Could not prepare the campus lightmap input: %s" % error_string(result))
		quit(1)
		return
	print("CAMPUS_LIGHTMAP_INPUT meshes=%d lights=%d skipped=%d file=%s" % [
		static_count, light_count, skipped, ProjectSettings.globalize_path(OUTPUT)])
	quit()

func _moving_branch(node: Node, boundary: Node) -> bool:
	var ancestor := node
	while ancestor != boundary:
		if ancestor is AnimatableBody3D or ancestor is CharacterBody3D or ancestor is RigidBody3D:
			return true
		if ancestor.name.begins_with("Door_") or ancestor.name == "ElevatorGeometry":
			return true
		ancestor = ancestor.get_parent()
	return false

func _copy_geometry(instance: MeshInstance3D, source: Node3D, stage: Node3D, index: int) -> bool:
	if instance.mesh == null or instance.mesh.get_surface_count() == 0:
		return false
	var mesh := ArrayMesh.new()
	for surface_index in instance.mesh.get_surface_count():
		var material := _bake_material(instance, surface_index)
		if material == null:
			return false
		if instance.mesh is ArrayMesh and instance.mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.append_from(instance.mesh, surface_index, Transform3D.IDENTITY)
		surface.set_material(material)
		surface.commit(mesh)
	if mesh.lightmap_unwrap(instance.global_transform, TEXEL_SIZE) != OK:
		return false
	var copy := MeshInstance3D.new()
	copy.name = "StaticGeometry%05d" % index
	copy.mesh = mesh
	copy.transform = instance.global_transform
	copy.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	copy.set_meta("source_path", source.get_path_to(instance))
	stage.add_child(copy)
	copy.owner = stage
	return true

func _bake_material(instance: MeshInstance3D, surface_index: int) -> StandardMaterial3D:
	var material := instance.get_active_material(surface_index)
	if material is StandardMaterial3D and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
		return material
	if material is ShaderMaterial and instance.get_meta("satin_floor", false):
		# The baker reads StandardMaterial3D, so approximate diffuse color in
		# the bake input. The playable floor keeps its authored shader.
		var proxy := StandardMaterial3D.new()
		var tile_color: Variant = material.get_shader_parameter("tile_color")
		proxy.albedo_color = tile_color if tile_color is Color else Color.WHITE
		proxy.vertex_color_use_as_albedo = material.get_shader_parameter("use_tile_vertex_color") == true
		return proxy
	return null
