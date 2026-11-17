extends RefCounted

const PATH := "user://college_preferences.cfg"
const BUS_NAMES := {"master": "Master", "effects": "Effects", "ambience": "Ambience", "interface": "Interface"}
const DEFAULTS := {
	"display_mode": 0, "width": 0, "height": 0, "vsync": true, "fps": 60, "fov": 72.0,
	"master": 1.0, "effects": 1.0, "ambience": 1.0, "interface": 1.0,
	"teacher_mic_sensitivity": 1.0,
	"teacher_mic_detection": true,
	"teacher_speech": true, "teacher_subtitles": true,
	"prompts": true, "notifications": true, "room_names": true, "hud": true, "assists": true,
	"relay_pose_rate": 10, "relay_skip_idle": true,
	"ui_scale": 1.0, "high_contrast": false, "analyzer_shapes": false, "reduced_motion": false,
}
var values := DEFAULTS.duplicate()
var game: Node

func load_settings(owner: Node) -> void:
	game = owner
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for key in DEFAULTS:
			var value: Variant = config.get_value("preferences", key, DEFAULTS[key])
			if typeof(value) == typeof(DEFAULTS[key]):
				values[key] = value
	else:
		var legacy := [Vector2i.ZERO, Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
		var resolution: Vector2i = legacy[game.ui.graphics_controller.options.resolution]
		values.width = resolution.x
		values.height = resolution.y
	values.display_mode = clampi(values.display_mode, 0, 2)
	values.width = clampi(values.width, 0, 3840)
	values.height = clampi(values.height, 0, 2160)
	values.relay_pose_rate = clampi(values.relay_pose_rate, 5, 20)
	values.fps = clampi(values.fps, 0, 360)
	values.fov = clampf(values.fov, 55, 95)
	values.ui_scale = clampf(values.ui_scale, 0.85, 1.25)
	if not is_finite(values.teacher_mic_sensitivity):values.teacher_mic_sensitivity=1.0
	values.teacher_mic_sensitivity=clampf(values.teacher_mic_sensitivity,.5,2.0)
	for key in BUS_NAMES:
		values[key] = clampf(values[key], 0.0, 1.0)

func save() -> Error:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("preferences", key, values[key])
	return config.save(PATH)

func set_option(key: String, value: Variant) -> void:
	values[key] = value
	apply(key)

func apply(key: String) -> void:
	if BUS_NAMES.has(key):
		var index := AudioServer.get_bus_index(BUS_NAMES[key])
		if index >= 0:
			AudioServer.set_bus_mute(index, float(values[key]) <= 0.0)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, values[key])))
		return
	match key:
		"teacher_speech", "teacher_subtitles":
			if is_instance_valid(game.faculty) and is_instance_valid(game.faculty.speech_player):
				game.faculty.speech_player.configure(values.teacher_speech,values.teacher_subtitles)
				if not values.teacher_speech and is_instance_valid(game.faculty.speech_synth):game.faculty.speech_synth.clear_session()
		"vsync":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
		"fps": Engine.max_fps = values.fps
		"fov": game.player.eyes.fov = values.fov
		"ui_scale": game.get_window().content_scale_factor = values.ui_scale
		"assists": game.ui.assists.set_pressed_no_signal(values.assists)
		"high_contrast":
			for label in [game.ui.prompt, game.ui.log_label, game.ui.objective, game.held_hint]:
				if label is Label:
					if values.high_contrast:
						label.add_theme_color_override("font_outline_color", Color.BLACK)
						label.add_theme_constant_override("outline_size", 8)
					else:
						label.remove_theme_constant_override("outline_size")
						label.remove_theme_color_override("font_outline_color")
		"analyzer_shapes":
			preload("res://scripts/breadboard_canvas.gd").use_analyzer_shapes = values.analyzer_shapes
			if is_instance_valid(game.electronics.canvas):
				game.electronics.canvas.queue_redraw()
		"reduced_motion":
			game.player.reduced_motion = values.reduced_motion
			if is_instance_valid(game.menu_campus):
				game.menu_campus.refresh_motion()

func apply_all() -> void:
	await apply_display(values.display_mode, Vector2i(values.width, values.height))
	for key in DEFAULTS:
		apply(key)

func apply_display(mode: int, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := game.get_window()
	window.mode = [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN][mode]
	if mode == 0 and resolution.x > 0 and resolution.y > 0:
		# Wait for the display server to finish leaving fullscreen before sizing
		# the window; an immediate size assignment can be discarded on Windows.
		await game.get_tree().process_frame
		if not is_instance_valid(window): return
		var area := DisplayServer.screen_get_usable_rect(window.current_screen)
		var requested := resolution.min(area.size)
		window.size = requested
		window.position = area.position + (area.size - requested) / 2

