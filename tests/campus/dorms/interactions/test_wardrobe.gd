extends SceneTree

const Toon = preload("res://scripts/toon_character.gd")
const FIXTURE_ID := "d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists("user://character_selection.cfg"):
		var folder := "user://characters/" + FIXTURE_ID
		DirAccess.make_dir_recursive_absolute(folder)
		var settings := FileAccess.open(folder.path_join("character.json"), FileAccess.WRITE)
		settings.store_string(JSON.stringify(Toon.preset(0)))
		settings.close()
		DirAccess.copy_absolute("res://assets/default_avatar.glb", folder.path_join("avatar.glb"))
		var selection := ConfigFile.new()
		selection.set_value("character", "selected", FIXTURE_ID)
		selection.save("user://character_selection.cfg")

	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_button(game.front.body, "Singleplayer").pressed.emit()
	await process_frame
	_button(game.front.body, "Play").pressed.emit()
	await process_frame

	var dorm: Node = game.dorm_interactions
	var room: String = dorm.room_for_peer(1)
	dorm._reconcile()
	for contract in dorm.hall.room_contracts:
		if contract.dorm_id == dorm._bay_for(room):
			game.player.global_position = contract.center
			break
	dorm.occupants[1] = room
	dorm._publish()
	if not dorm.interiors.has(room):
		_fail("The player's dorm did not load.")
		return
	var wardrobe: Node = dorm.interiors[room].room.targets.wardrobe
	var interact := InputEventKey.new()
	interact.pressed = true
	interact.keycode = KEY_E
	interact.physical_keycode = KEY_E
	var prior_world_rendering := root.disable_3d
	for attempt in range(3):
		print("WARDROBE OPEN ", attempt + 1)
		game.current_target = wardrobe
		game._input(interact)
		for frame in range(5):
			await process_frame
		if not game.characters.is_editing():
			_fail("The wardrobe did not open the character editor.")
			return
		var studio: Control = game.characters.editor_studio.panel
		if not root.disable_3d or not is_instance_valid(studio.preview.avatar):
			_fail("The studio did not switch to its own avatar preview.")
			return
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var frame: Image = studio.preview.viewport.get_texture().get_image()
			if frame == null or frame.get_width() < 16 or frame.get_height() < 16 or frame.get_pixel(0, 0).a == 0.0:
				_fail("The wardrobe preview did not render with the campus covered.")
				return
		studio.select_category("tops")
		await process_frame
		_button(studio, "Cancel").pressed.emit()
		await process_frame
		if game.characters.is_editing() or not game.player.enabled or root.disable_3d != prior_world_rendering:
			_fail("Closing the wardrobe did not return movement control.")
			return
	var expired_target := StaticBody3D.new()
	game.current_target = expired_target
	expired_target.free()
	game.campus_services._process(0.0)
	game.current_target = null
	print("WARDROBE PASS")
	game.front.leave_game()
	game.queue_free()
	await process_frame
	quit()

func _button(parent: Node, label: String) -> Button:
	for child in parent.find_children("*", "Button", true, false):
		if child.text == label and child.is_visible_in_tree():
			return child
	return null

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
