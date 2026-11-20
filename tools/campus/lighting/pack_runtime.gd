extends SceneTree
## Run in the bake project after importing the production atlas textures there.
## Arguments are the baked scene, destination catalog, light atlas and shadow atlas.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4 or args.size() > 5:
		push_error("Expected a baked scene, runtime catalog path, light atlas, and sun-shadow atlas.")
		quit(1)
		return
	var baked := load(args[0]) as PackedScene
	var light_atlas := load(args[2]) as TextureLayered
	var shadow_atlas := load(args[3]) as TextureLayered
	if baked == null or light_atlas == null or shadow_atlas == null:
		push_error("The baked scene and both imported atlas textures are required.")
		quit(1)
		return
	var stage := baked.instantiate()
	var gi := stage.get_node_or_null("CampusLightmap") as LightmapGI
	if gi == null or gi.light_data == null or gi.light_data.get_shadowmask_textures().is_empty():
		stage.free()
		push_error("The scene does not have a completed directional shadowmask bake.")
		quit(1)
		return
	var data := gi.light_data.duplicate() as LightmapGIData
	var original_shadows := data.get_shadowmask_textures()
	var original_lights := data.get_lightmap_textures()
	if original_shadows.size() != 1 or original_lights.size() != 1:
		stage.free()
		push_error("The packer needs one native light sheet and one native shadow sheet.")
		quit(1)
		return
	var pages := original_shadows[0].get_layers()
	var layers := original_lights[0].get_layers()
	var tiled := args.size() == 5 and args[4] == "tiled"
	var target_pages := ceili(float(pages) / 4.0) if tiled else pages
	if shadow_atlas.get_layers() != target_pages or light_atlas.get_layers() != target_pages * (layers / pages):
		stage.free()
		push_error("Imported texture layer counts do not match the lightmap catalog.")
		quit(1)
		return
	if tiled:
		var users: Array = data.get("user_data")
		data.clear_users()
		for index in range(0, users.size(), 4):
			var page: int = users[index + 2]
			var tile := page % 4
			var rect: Rect2 = users[index + 1]
			rect.position = (rect.position + Vector2(tile % 2, tile / 2)) * 0.5
			rect.size *= 0.5
			data.add_user(users[index], rect, page / 4, users[index + 3])
	data.set_lightmap_textures([light_atlas])
	data.set_shadowmask_textures([shadow_atlas])
	gi.light_data = data
	for child in stage.get_children():
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				child.mesh.surface_set_material(surface, null)
		elif child != gi:
			child.free()
	var catalog := PackedScene.new()
	var result := catalog.pack(stage)
	if result == OK:
		result = ResourceSaver.save(catalog, args[1], ResourceSaver.FLAG_COMPRESS)
	stage.free()
	print("CAMPUS_BAKE_CATALOG ", error_string(result))
	quit(int(result))
