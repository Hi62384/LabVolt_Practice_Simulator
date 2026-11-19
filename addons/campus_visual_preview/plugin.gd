@tool
extends EditorPlugin

const MAIN := "res://scenes/Main.tscn"
const PREVIEW := "res://.godot/campus-visual-preview.tscn"
const STAGING := "res://.godot/campus-visual-preview-staging.tscn"

var _clock := 0.0
var _last_values: Array = []

func _process(delta: float) -> void:
	if not EditorInterface.is_playing_scene():
		_last_values.clear()
		return
	_clock += delta
	if _clock < 0.2:
		return
	_clock = 0.0
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != MAIN:
		return
	var settings := root.get_node_or_null("CampusVisualSettings")
	var world := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if settings == null or world == null:
		return

	var values := _stored_values(settings, {}, true)
	var visited := {}
	values.append(_signature(world.environment, visited))
	values.append(_signature(world.camera_attributes, visited))
	values.append(_signature(world.compositor, visited))
	if values == _last_values:
		return

	var preview := Node.new()
	var settings_copy := settings.duplicate()
	var world_copy := world.duplicate()
	preview.add_child(settings_copy)
	preview.add_child(world_copy)
	settings_copy.owner = preview
	world_copy.owner = preview
	var scene := PackedScene.new()
	var result := scene.pack(preview)
	if result == OK:
		result = ResourceSaver.save(scene, STAGING)
	if result == OK:
		result = DirAccess.rename_absolute(STAGING, PREVIEW)
	preview.free()
	if result == OK:
		_last_values = values

func _stored_values(object: Object, visited: Dictionary, script_only := false) -> Array:
	var values := []
	for property in object.get_property_list():
		var usage: int = property.usage
		if not usage & PROPERTY_USAGE_STORAGE:
			continue
		if script_only and not usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		if property.name != "script":
			values.append(_signature(object.get(property.name), visited))
	return values

func _signature(value: Variant, visited: Dictionary) -> Variant:
	if value is Resource:
		var id: int = value.get_instance_id()
		if visited.has(id) or value is Texture or value is Script:
			return id
		visited[id] = true
		return [id, _stored_values(value, visited)]
	if value is Array:
		var values := []
		for item in value:
			values.append(_signature(item, visited))
		return values
	return value
