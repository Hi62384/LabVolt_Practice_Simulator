extends Node
## Local Inspector edits preview in the running debug game. Save Main.tscn to keep them.

@export_group("Indoor Fixtures")
## Multiplies the fixtures' authored colors, including the selected in-game lighting tone.
@export var fixture_tint := Color.WHITE
@export_range(0.0, 3.0, 0.01) var fixture_energy := 1.0

@export_group("Sun")
@export var sun_tint := Color.WHITE
@export_range(0.0, 3.0, 0.01) var sun_energy := 1.0

@export_group("Dynamic Shadows")
## Multiplies shadow opacity for the sun and indoor fixtures while in-game shadows are enabled.
@export_range(0.0, 1.0, 0.01) var shadow_opacity := 1.0
@export_range(0.0, 3.0, 0.01) var shadow_softness := 1.0

@export_group("Baked Lighting")
## Turn off the lightmap to preview entirely dynamic shadows.
@export var use_baked_lighting := true
## Scales the existing lightmap. To change the shape of a baked shadow, rebake the lightmap.
@export_range(0.1, 3.0, 0.01) var baked_light_strength := 1.0

@export_group("World Environment")
## Keep the saved WorldEnvironment effects and exposure when the graphics preset is applied.
@export var use_scene_environment_effects := false

var _scene_hash := ""
var _preview_hash := ""
const EDITOR_PREVIEW := "res://.godot/campus-visual-preview.tscn"

func watch_saved_scene() -> void:
	var scene_path := get_parent().scene_file_path
	if not OS.is_debug_build() or not FileAccess.file_exists(scene_path):
		return
	_scene_hash = FileAccess.get_sha256(scene_path)
	if scene_path == "res://scenes/Main.tscn" and FileAccess.file_exists(EDITOR_PREVIEW):
		_preview_hash = FileAccess.get_sha256(EDITOR_PREVIEW)
	var watcher := Timer.new()
	watcher.process_mode = Node.PROCESS_MODE_ALWAYS
	watcher.wait_time = 0.5
	add_child(watcher)
	watcher.timeout.connect(_poll_changes.bind(scene_path))
	watcher.start()

func _poll_changes(scene_path: String) -> void:
	var digest := FileAccess.get_sha256(scene_path)
	if not digest.is_empty() and digest != _scene_hash and _apply_scene(scene_path):
		_scene_hash = digest
	if scene_path == "res://scenes/Main.tscn" and FileAccess.file_exists(EDITOR_PREVIEW):
		var preview_digest := FileAccess.get_sha256(EDITOR_PREVIEW)
		if not preview_digest.is_empty() and preview_digest != _preview_hash and _apply_scene(EDITOR_PREVIEW):
			_preview_hash = preview_digest

func _apply_scene(path: String) -> bool:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return false
	var authored := packed.instantiate()
	var settings := authored.get_node_or_null("CampusVisualSettings")
	var source := authored.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var valid := settings != null and source != null
	if valid:
		for property in settings.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
				set(property.name, settings.get(property.name))
		var game := get_parent()
		var world := game.get_node("WorldEnvironment") as WorldEnvironment
		world.environment = source.environment
		world.camera_attributes = source.camera_attributes
		world.compositor = source.compositor
		var graphics: Node = game.ui.graphics_controller
		graphics.originals.erase(world.get_instance_id())
		var rig := game.find_child("CampusLightingRig", false, false) as CampusLightingRig
		if rig != null:
			rig.set_time_of_day(rig.time_of_day)
		graphics.apply()
		var bake := game.get_node_or_null("CampusBakedLighting")
		if bake != null:
			bake.refresh_visual_settings(graphics.options)
	authored.free()
	return valid
