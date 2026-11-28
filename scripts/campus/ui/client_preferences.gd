extends RefCounted

const PATH := "user://college_preferences.cfg"
const BUS_NAMES := {"master": "Master", "effects": "Effects", "ambience": "Ambience", "interface": "Interface", "npc_speech": "NPCSpeech", "human_voice": "HumanVoice", "phone_calls": "PhoneCalls"}
const WINDOW_MODES := [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN, Window.MODE_MAXIMIZED]
const DEFAULTS := {
	"display_mode": 0, "width": 0, "height": 0, "window_screen": -1, "normal_bounds": Rect2i(), "vsync": true, "fps": 60, "fov": 72.0,
	"master": 1.0, "effects": 1.0, "ambience": 1.0, "interface": 1.0,
	"npc_speech": 1.0, "human_voice": 1.0, "phone_calls": 1.0,
	"microphone_mode": "push_to_talk", "microphone_muted": false,
	"microphone_device": "Default", "output_device": "Default",
	"microphone_noise_gate": true, "microphone_echo_mode": "speaker_protection",
	"npc_interruptions": true, "voice_diagnostics": false,
	"teacher_mic_sensitivity": 1.0,
	"teacher_mic_detection": true,
	"teacher_automatic_conversation": false,
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
		var graphics_config := ConfigFile.new()
		graphics_config.load("user://campus_graphics.cfg")
		var legacy_index := clampi(int(graphics_config.get_value("graphics", "resolution", 0)), 0, legacy.size()-1)
		var resolution: Vector2i = legacy[legacy_index]
		values.width = resolution.x
		values.height = resolution.y
	values.display_mode = clampi(values.display_mode, 0, 3)
	values.width = clampi(values.width, 0, 3840)
	values.height = clampi(values.height, 0, 2160)
	values.relay_pose_rate = clampi(values.relay_pose_rate, 5, 20)
	values.fps = clampi(values.fps, 0, 360)
	values.fov = clampf(values.fov, 55, 95)
	values.ui_scale = clampf(values.ui_scale, 0.85, 1.25)
	if not is_finite(values.teacher_mic_sensitivity):values.teacher_mic_sensitivity=1.0
	values.teacher_mic_sensitivity=clampf(values.teacher_mic_sensitivity,.5,2.0)
	if values.microphone_mode not in ["push_to_talk","voice_activation","manual","muted"]:values.microphone_mode="push_to_talk"
	if values.microphone_echo_mode not in ["speaker_protection","headphones"]:values.microphone_echo_mode="speaker_protection"
	for key in BUS_NAMES:
		values[key] = clampf(values[key], 0.0, 1.0) if is_finite(values[key]) else DEFAULTS[key]

func save() -> Error:
	var config := ConfigFile.new()
	for key in values:
		config.set_value("preferences", key, values[key])
	return config.save(PATH)

func set_option(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key) or typeof(value)!=typeof(DEFAULTS[key]):return
	if value is float and not is_finite(value):value=DEFAULTS[key]
	if values.get(key)==value:return
	values[key] = value
	apply(key)

func apply(key: String) -> void:
	if BUS_NAMES.has(key):
		preload("res://scripts/campus/voice/audio_voice_mixer.gd").ensure_buses()
		var index := AudioServer.get_bus_index(BUS_NAMES[key])
		if index >= 0:
			AudioServer.set_bus_mute(index, float(values[key]) <= 0.0)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, values[key])))
		return
	match key:
		"microphone_mode", "microphone_muted", "microphone_device", "microphone_noise_gate", "microphone_echo_mode", "teacher_mic_sensitivity", "teacher_automatic_conversation":
			var service:=game.get_tree().root.get_node_or_null("MicrophoneCapture")
			if is_instance_valid(service):service.configure(values)
			if is_instance_valid(game.get("faculty")):
				# Mode or NPC-consent changes affect automatic recognition only.
				# A separately requested manual recording survives unrelated changes.
				if key=="microphone_device" or values.microphone_muted or values.microphone_mode=="muted":game.faculty._cancel_recording()
				if key in ["microphone_device","microphone_mode","microphone_muted","teacher_automatic_conversation"]:game.faculty._stop_voice_conversation()
			if (values.microphone_muted or values.microphone_mode=="muted") and is_instance_valid(game.get("voice_chat")):game.voice_chat._stop()
		"output_device":
			if values.output_device in AudioServer.get_output_device_list():AudioServer.output_device=values.output_device
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

func remember_window() -> Error:
	if DisplayServer.get_name() == "headless":
		return OK
	var window := game.get_window()
	var mode := WINDOW_MODES.find(window.mode)
	if mode >= 0:
		values.display_mode = mode
	values.window_screen = window.current_screen
	if window.mode == Window.MODE_WINDOWED:
		values.normal_bounds = Rect2i(window.position, window.size)
	return save()

func apply_all() -> void:
	var window := game.get_window()
	var bounds: Rect2i = values.normal_bounds
	if DisplayServer.get_name() != "headless":
		if int(values.window_screen) in range(DisplayServer.get_screen_count()):
			window.current_screen = int(values.window_screen)
		if bounds.has_area() and window.mode == Window.MODE_WINDOWED:
			var area := DisplayServer.screen_get_usable_rect(window.current_screen)
			window.size = bounds.size.min(area.size)
			window.position = bounds.position.clamp(area.position, area.end - window.size)
	var resolution := Vector2i(values.width, values.height)
	if bounds.has_area() and window.size == resolution:
		resolution = Vector2i.ZERO
	await apply_display(values.display_mode, resolution)
	for key in DEFAULTS:
		apply(key)

func apply_display(mode: int, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := game.get_window()
	var target: Window.Mode = WINDOW_MODES[mode]
	if window.mode != target:
		window.mode = target
	if mode == 0 and resolution.x > 0 and resolution.y > 0:
		# Wait for the display server to finish leaving fullscreen before sizing
		# the window; an immediate size assignment can be discarded on Windows.
		await game.get_tree().process_frame
		if not is_instance_valid(window): return
		var area := DisplayServer.screen_get_usable_rect(window.current_screen)
		var requested := resolution.min(area.size)
		window.size = requested
		window.position = area.position + (area.size - requested) / 2

