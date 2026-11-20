extends SceneTree
## Tile four baked pages into each production atlas layer without resampling.
## Arguments are baked scene, source light and shadow sheets, and output sheets.

const PAGES_PER_LAYER := 4

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		quit(1)
		return
	var scene := (load(args[0]) as PackedScene).instantiate()
	var data: LightmapGIData = scene.get_node("CampusLightmap").light_data
	var shadow_textures := data.get_shadowmask_textures()
	var light_textures := data.get_lightmap_textures()
	if shadow_textures.size() != 1 or light_textures.size() != 1:
		scene.free()
		push_error("Expected a single source sheet for each atlas.")
		quit(1)
		return
	var pages: int = shadow_textures[0].get_layers()
	var layers: int = light_textures[0].get_layers()
	var light := _tile(Image.load_from_file(args[1]), pages, layers)
	var shadow := _tile(Image.load_from_file(args[2]), pages, pages)
	scene.free()
	if light == null or shadow == null:
		push_error("Atlas dimensions did not match the baked layer data.")
		quit(1)
		return
	if light.save_exr(args[3]) != OK or shadow.save_png(args[4]) != OK:
		push_error("Could not save the tiled atlases.")
		quit(1)
		return
	var packed_pages := ceili(float(pages) / PAGES_PER_LAYER)
	print("CAMPUS_ATLAS_TILED pages=", pages, " packed_pages=", packed_pages,
		" light_layers=", packed_pages * (layers / pages), " shadow_layers=", packed_pages)
	quit()

func _tile(source: Image, pages: int, layers: int) -> Image:
	if source == null or source.is_empty() or pages <= 0 or layers % pages != 0 or source.get_height() % layers != 0:
		return null
	var width := source.get_width()
	var height := source.get_height() / layers
	var channels := layers / pages
	var packed_pages := ceili(float(pages) / PAGES_PER_LAYER)
	var image := Image.create_empty(width * 2, height * 2 * packed_pages * channels, false, source.get_format())
	for page in pages:
		var tile := page % PAGES_PER_LAYER
		var target_page := page / PAGES_PER_LAYER
		for band in channels:
			var source_layer := page * channels + band
			var target_layer := target_page * channels + band
			var origin := Vector2i(width * (tile % 2), height * (target_layer * 2 + tile / 2))
			image.blit_rect(source, Rect2i(0, source_layer * height, width, height), origin)
	return image
