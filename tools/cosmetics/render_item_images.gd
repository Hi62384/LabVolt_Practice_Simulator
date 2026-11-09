extends SceneTree
## Run with Godot's graphical renderer after importing the cosmetic assets.
const Coordinator = preload("res://scripts/avatar_cosmetics/core/coordinator.gd")
const Renderer = preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
const Thumbnail = preload("res://scripts/avatar_cosmetics/ui/thumbnail_renderer.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")

var catalog: Dictionary

func _initialize() -> void:
	call_deferred("_render_all")

func _render_all() -> void:
	var provider := Coordinator.new()
	if not provider.load_catalog():
		push_error(str(provider.errors))
		quit(1)
		return
	catalog = provider.catalog
	var studio := Thumbnail.new()
	studio.configure(_build_item)
	root.add_child(studio)
	for id in catalog:
		var item: Dictionary = catalog[id]
		if item.category == "faces": continue
		var texture: Texture2D = await studio.render_item(id, Core.sanitize_parameters(item,{}), Core.sanitize_body({}))
		if texture == null or texture.get_image().save_png(ProjectSettings.globalize_path(item.thumbnail)) != OK:
			push_error("Failed to bake " + str(id))
			quit(1)
			return
		print("Baked ", id)
	quit()

func _build_item(id: String, parameters: Dictionary, body: Dictionary) -> Node3D:
	var item: Dictionary = catalog[id]
	match str(item.category):
		"accessories":
			return Renderer.Accessories.instantiate(item, parameters, body)
		"shoes":
			var pair := Renderer.Footwear.instantiate(item, parameters, body)
			pair.get_child(1).free()
			return pair
	var equipped := {}
	equipped[item.slot] = {"id":id,"parameters":parameters}
	var avatar := Renderer.render_avatar({"body":body,"equipped":equipped},catalog)
	avatar.set_meta("thumbnail_category",item.category)
	return avatar

