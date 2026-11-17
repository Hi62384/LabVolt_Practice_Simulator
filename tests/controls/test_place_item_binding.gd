extends SceneTree

const Player = preload("res://scripts/first_person.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "user://settings.cfg"
	var existing := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var had_settings := FileAccess.file_exists(path)
	var old := ConfigFile.new()
	old.set_value("keys","drop_lead",KEY_G)
	assert(old.save(path)==OK)
	var player := Player.new()
	assert(player.keys.place_item==KEY_F)
	assert(player.keys.inspect==KEY_I)
	player.load_settings()
	assert(player.keys.place_item==KEY_F)
	assert(player.keys.inspect==KEY_I)
	old.set_value("keys","drop_lead",KEY_J)
	assert(old.save(path)==OK)
	var remapped := Player.new()
	remapped.load_settings()
	assert(remapped.keys.place_item==KEY_J)
	old.set_value("keys","drop_lead",KEY_I)
	assert(old.save(path)==OK)
	var collision := Player.new()
	collision.load_settings()
	assert(collision.keys.place_item==KEY_F and collision.keys.inspect==KEY_I)
	old.set_value("keys","place_item",KEY_F)
	old.set_value("keys","interact",KEY_F)
	assert(old.save(path)==OK)
	var saved_collision := Player.new()
	saved_collision.load_settings()
	assert(saved_collision.keys.place_item==KEY_F and saved_collision.keys.interact==KEY_E)
	if had_settings:
		var restore := FileAccess.open(path,FileAccess.WRITE)
		assert(restore!=null)
		restore.store_buffer(existing)
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PLACE_ITEM_BINDING PASS")
	quit(0)
