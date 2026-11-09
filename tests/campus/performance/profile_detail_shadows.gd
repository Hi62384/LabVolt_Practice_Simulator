extends SceneTree
## Opt-in NEW lease only. Measures the project in which it is installed; never
## applies/reapplies optimization. No screenshot/disk writes inside timing windows.
const Trace = preload("res://scripts/campus/performance/hitch_trace.gd")
var detail_shadows := false
var output := "user://hitch-trace.json"
var seconds := 30.0
var warmup := 5.0
var scenario := "normal-startup"
var enter_game := false
var freeze_player := false
var position_override: Variant = null

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--detail-shadows": detail_shadows=true
		elif arg == "--enter-game": enter_game = true
		elif arg == "--freeze-player": freeze_player = true
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--seconds="): seconds = clampf(float(arg.trim_prefix("--seconds=")),1.0,60.0)
		elif arg.begins_with("--warmup="): warmup = clampf(float(arg.trim_prefix("--warmup=")),0.5,30.0)
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=").left(96)
		elif arg.begins_with("--position="):
			var xyz := arg.trim_prefix("--position=").split(",")
			if xyz.size() == 3:
				position_override = Vector3(float(xyz[0]),float(xyz[1]),float(xyz[2]))
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Diagnostic rendered runner requires a newly granted lease")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1920,1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var trace := Trace.new()
	root.add_child(trace)
	var startup := trace.begin_span("scene_instantiation_and_ready")
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	var game_script_path: String = game.get_script().resource_path
	var game_script_hash_at_start := FileAccess.get_sha256(game_script_path)
	game.set_meta("campus_hitch_trace",trace)
	root.add_child(game)
	game.ui.graphics_controller.set_option("detail_shadows",detail_shadows)
	trace.end_span(startup)
	if enter_game and game.has_method("capture"):
		game.call("capture")
	var player: Variant = game.get("player")
	if player is Node3D:
		if position_override is Vector3 and position_override.is_finite():
			player.global_position = position_override
		if freeze_player:
			player.set_physics_process(false)
	var camera: Variant = game.get("camera")
	if camera is Camera3D:
		camera.fov = 92
	trace.begin_window("warmup",warmup)
	await trace.window_finished
	trace.begin_window("sample",seconds)
	await trace.window_finished
	trace.stop()
	var report: Dictionary = trace.report()
	var window_size := DisplayServer.window_get_size()
	var game_script_hash_after := FileAccess.get_sha256(game_script_path)
	report.context = {"detail_shadows":detail_shadows,"scenario":scenario,"project_path":ProjectSettings.globalize_path("res://"),"game_script_path":game_script_path,"game_script_sha256_at_instantiation":game_script_hash_at_start,"game_script_sha256_after_measurement":game_script_hash_after,"root_script_file_changed":game_script_hash_at_start!=game_script_hash_after,"fingerprint_scope":"root game script only; not a full source manifest","renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"window_size":[window_size.x,window_size.y],"viewport_size":[root.size.x,root.size.y],"render_scale":root.scaling_3d_scale,"msaa_3d":root.msaa_3d,"vsync":DisplayServer.window_get_vsync_mode(),"requested_sample_seconds":seconds,"requested_warmup_seconds":warmup,"player_frozen":freeze_player,"entered_game":enter_game,"optimization_applied_by_runner":false}
	if player is Node3D:
		report.context.player_position = [player.global_position.x,player.global_position.y,player.global_position.z]
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		printerr("Cannot save stopped diagnostic report")
		quit(3)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("HITCH TRACE saved frames=%d hitches=%d spans=%d" % [report.frames.size(),report.hitches.size(),report.spans.size()])
	quit()
