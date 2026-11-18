extends SceneTree
var graphics: Node
var panel: PanelContainer
var failures := 0
func artifact_path(name: String) -> String:
	var directory := OS.get_environment("LABVOLT_UI_ARTIFACTS")
	if directory.is_empty(): directory=OS.get_user_data_dir().path_join("ui-test-artifacts")
	DirAccess.make_dir_recursive_absolute(directory)
	return directory.path_join(name)
func _initialize() -> void: call_deferred("run")
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new(); move.position=point; root.push_input(move,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true)
	await process_frame
func image_after_frames() -> Image:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Rendered graphics test needs graphical renderer"); quit(1); return
	root.size=Vector2i(1280,720)
	var world := Node3D.new(); root.add_child(world)
	var environment := WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("101b2b"); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.3; world.add_child(environment)
	var camera := Camera3D.new(); camera.position=Vector3(5,4,7); world.add_child(camera); camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-25,0); light.shadow_enabled=true; world.add_child(light)
	var local := OmniLight3D.new(); local.position=Vector3(1,2,2); local.light_color=Color("56cfc0"); local.omni_range=8; world.add_child(local)
	for i in range(7):
		var mesh := MeshInstance3D.new(); mesh.mesh=BoxMesh.new(); mesh.position=Vector3((i%3)*1.8-1.8,.5,-float(i/3)*2); mesh.rotation.y=.3*i; mesh.material_override=StandardMaterial3D.new(); mesh.material_override.albedo_color=Color("dce9ed"); world.add_child(mesh)
	var floor_mesh := MeshInstance3D.new(); floor_mesh.mesh=BoxMesh.new(); floor_mesh.scale=Vector3(20,.1,20); floor_mesh.position.y=-.1; floor_mesh.material_override=StandardMaterial3D.new(); floor_mesh.material_override.albedo_color=Color("45616b"); world.add_child(floor_mesh)
	graphics=load("res://scripts/campus/ui/graphics_settings.gd").new(); root.add_child(graphics); graphics.attach(root,world)
	panel=PanelContainer.new(); panel.position=Vector2(20,20); panel.size=Vector2(410,680); panel.theme=load("res://scripts/campus/ui/campus_theme.gd").create(); root.add_child(panel)
	var box := VBoxContainer.new(); panel.add_child(box); graphics.build_controls(box)
	graphics.preset("High")
	var high: Image=await image_after_frames(); high.save_png(artifact_path("graphics-high.png"))
	for button in panel.find_children("*","Button",true,false):
		if button.text=="Low": await click(button); break
	if graphics.options.render_scale!=.65 or light.shadow_enabled or root.msaa_3d!=0: failures+=1; push_error("Low preset rendered click failed")
	var low: Image=await image_after_frames(); low.save_png(artifact_path("graphics-low.png"))
	var changed := 0
	for y in range(0,mini(high.get_height(),low.get_height()),3):
		for x in range(500,mini(high.get_width(),low.get_width()),3):
			var a := high.get_pixel(x,y); var b := low.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.03: changed+=1
	if changed<100: failures+=1; push_error("No measurable 3D image change outside controls")
	print("UI_GRAPHICS_RENDERED_RESULT failures=",failures," changed_3d_samples=",changed," renderer=",RenderingServer.get_current_rendering_method())
	graphics.preset("Medium")
	for distance in [30.0, 60.0, 100.0, 120.0, 180.0, 240.0]:
		graphics.set_option("view_distance", distance)
		if not is_equal_approx(camera.far, distance):
			failures += 1
			push_error("Camera view distance did not change to %d m" % distance)
	var streamed := Camera3D.new()
	world.add_child(streamed)
	await process_frame
	if streamed.far != 240.0:
		failures += 1
		push_error("A newly loaded camera missed the active view distance")
	panel.queue_free()
	world.queue_free()
	graphics.queue_free()
	await process_frame
	await verify_display()
	quit(1 if failures else 0)


func verify_display() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	root.mode = Window.MODE_MAXIMIZED
	await process_frame
	await process_frame
	var size := root.size
	var screen := root.current_screen
	var settings: Control = load("res://scripts/campus/ui/settings_page.gd").new()
	game.add_child(settings)
	settings.build(game)
	var graphics_settings: Node = game.ui.graphics_controller
	for preset in ["Low","Medium","High","Ultra"]:
		graphics_settings.preset(preset)
		settings._select("Graphics & Display")
		var prefs_copy: Node = graphics_settings.get_script().new()
		prefs_copy.load_settings()
		if prefs_copy.quality_preset != preset or prefs_copy.options != graphics_settings.options or settings.choices.preset.get_item_text(settings.choices.preset.selected) != preset:
			failures += 1
			push_error("Quality preset did not survive reopening or reloading: " + preset)
		prefs_copy.free()
	game.ui.graphics_controller.set_option("render_scale", .75)
	await settings._apply_display()
	if root.mode != Window.MODE_MAXIMIZED or root.size != size or settings.previewing:
		failures += 1
		push_error("Quality-only apply disturbed a maximized window")
	settings.display_edited = true
	settings.pending_mode = 0
	settings.pending_resolution = Vector2i(1280,720)
	await settings._apply_display()
	if not settings.previewing or root.mode != Window.MODE_WINDOWED:
		failures += 1
		push_error("Windowed preview was not applied")
	else:
		settings.confirmation.close_requested.emit()
		await process_frame
		await process_frame
		if root.mode != Window.MODE_MAXIMIZED or root.current_screen != screen or root.size != size:
			failures += 1
			push_error("Closing the preview did not restore maximized state")
	settings.display_edited = true
	settings.pending_mode = 0
	settings.pending_resolution = Vector2i(1280,720)
	await settings._apply_display()
	if is_instance_valid(settings.confirmation):
		settings.confirmation.confirmed.emit()
		var config := ConfigFile.new()
		if config.load("user://college_preferences.cfg") != OK or config.get_value("preferences", "width", 0) != 1280:
			failures += 1
			push_error("Keep Changes did not save the new resolution")
	else:
		failures += 1
	var previous_size := root.size
	var previous_position := root.position
	for mode in [1, 2]:
		settings.display_edited = true
		settings.pending_mode = mode
		await settings._apply_display()
		await process_frame
		var expected: Window.Mode = Window.MODE_FULLSCREEN if mode == 1 else Window.MODE_EXCLUSIVE_FULLSCREEN
		if not settings.previewing or root.mode != expected:
			failures += 1
			push_error("Could not preview fullscreen mode %d" % mode)
			continue
		if mode == 1:
			settings.confirmation.canceled.emit()
		else:
			settings.countdown = 1
			for child in settings.confirmation.get_children():
				if child is Timer:
					child.timeout.emit()
					break
		await process_frame
		await process_frame
		if root.mode != Window.MODE_WINDOWED or root.size != previous_size or root.position != previous_position or root.current_screen != screen:
			failures += 1
			push_error("Revert did not restore the normal window after fullscreen mode %d" % mode)
	var reloaded: Node = load("res://scripts/campus/ui/graphics_settings.gd").new()
	reloaded.load_settings()
	if reloaded.options.render_scale != .75 or reloaded.quality_preset != "Custom":
		failures += 1
		push_error("Render scale was not persisted")
	reloaded.free()
	print("DISPLAY_RENDERED_RESULT failures=", failures)
	game.queue_free()
	await process_frame
