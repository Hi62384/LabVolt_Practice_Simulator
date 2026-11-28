extends SceneTree
## Production inspector rendered with actual repository character data and an
## empty interaction history. This fixture verifies layout, not model quality.
const Inspector = preload("res://scripts/campus/ui/character_inspector.gd")
const Snapshot = preload("res://scripts/campus/ui/character_inspector_snapshot.gd")
const Fixtures = preload("res://tests/campus/academics/test_character_inspector.gd")
const Memory = preload("res://scripts/campus/academics/character_memory.gd")

func _initialize() -> void:
	_render.call_deferred()

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use an actual rendering display; a dummy headless viewport is not visual evidence.")
		quit(2)
		return
	var output := "res://docs/verification/character-dossiers"
	if not OS.get_cmdline_user_args().is_empty():
		output = str(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.title = "LabVolt character inspector — production controls"
	var background := ColorRect.new()
	background.color = Color("09151e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var game := Fixtures.GameFixture.new()
	game.school = Fixtures.SchoolFixture.new()
	game.add_child(game.school)
	game.add_child(game.lecture_classes)
	root.add_child(game)
	var faculty := Fixtures.FacultyFixture.new()
	faculty.game = game
	faculty.brain = Memory.new()
	faculty.brain._host_profile = "inspector_test_host"
	root.add_child(faculty)
	var panel := Inspector.new()
	root.add_child(panel)
	panel.position = Vector2(90, 18)
	panel.size = Vector2(1100, 684)
	panel.configure(func(): return Snapshot.capture(faculty))
	for action in ["ready", "clarify", "evaluate_led"]:
		panel.action_buttons[action].hide()
	panel.dialogue.text = "Type a message or use the microphone to begin a conversation."
	panel.open_character()
	for page in ["Overview", "Personality", "Diagnostics"]:
		panel._select_page(page)
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var rendered := root.get_texture().get_image()
		if rendered == null or rendered.is_empty():
			push_error("Renderer did not return an inspector image")
			quit(3)
			return
		var error := rendered.save_png(output.path_join("inspector_" + page.to_lower() + ".png"))
		if error != OK:
			quit(4)
			return
		print("INSPECTOR_RENDER ", page, " size=", panel.size, " minimum=", panel.get_combined_minimum_size())
	root.size = Vector2i(800, 600)
	panel.position = Vector2(18, 18)
	panel.size = Vector2(764, 564)
	panel._select_page("Overview")
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("inspector_compact.png"))
	print("INSPECTOR_RENDER compact size=", panel.size, " minimum=", panel.get_combined_minimum_size(), " adapter=", RenderingServer.get_video_adapter_name())
	panel.queue_free()
	faculty.queue_free()
	game.queue_free()
	await process_frame
	quit(0)
