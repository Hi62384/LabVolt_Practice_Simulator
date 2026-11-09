extends SceneTree
## Requires a newly granted exclusive rendered window. No import or stress loops.
const Probe = preload("res://scripts/campus/performance/wall_frame_probe.gd")
const Optimizer = preload("res://scripts/campus/performance/equipment_render_optimizer.gd")
var optimized := false
var output := "user://equipment-render-profile.json"
var game: Node3D
var probe: Node
var optimizer: RefCounted

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--optimize=on":
			optimized = true
		elif arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Candidate profile requires graphical renderer and exclusive lease")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(1920,1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var start := Time.get_ticks_usec()
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	var load_ms := (Time.get_ticks_usec()-start)/1000.0
	var optimization: Array = []
	var setup_ms := 0.0
	if optimized:
		start = Time.get_ticks_usec()
		optimizer = Optimizer.new()
		optimization = optimizer.optimize_legacy_game(game)
		optimizer.release_original_meshes()
		setup_ms = (Time.get_ticks_usec()-start)/1000.0
	game.capture()
	game.player.position = Vector3(0,0,8.5)
	game.player.enabled = false
	game.camera.fov = 92
	probe = Probe.new()
	root.add_child(probe)
	await create_timer(5.0).timeout
	probe.enabled = false
	var warmup: Dictionary = probe.report()
	probe.free()
	probe = Probe.new()
	root.add_child(probe)
	await create_timer(15.0).timeout
	probe.enabled = false
	var report: Dictionary = probe.report()
	report.warmup = warmup
	report.scene_load_ms = load_ms
	report.optimization_setup_ms = setup_ms
	report.optimizer = optimization
	report.optimized = optimized
	report.scenario = "snapshot02 static three-rack view, default idle benches, no crowds, no peers"
	var window_size := DisplayServer.window_get_size()
	report.window_size = [window_size.x,window_size.y]
	report.viewport_size = [root.size.x,root.size.y]
	report.render_scale = root.scaling_3d_scale
	report.msaa_3d = root.msaa_3d
	report.vsync_mode = DisplayServer.window_get_vsync_mode()
	report.sample_seconds = 15
	report.warmup_seconds = 5
	# Evidence captures run after timing, avoiding readback stalls in frame metrics.
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+".scene.png")
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.fov = 50
	camera.global_position = Vector3(-1.6,2.9,-1.4)
	camera.look_at(Vector3(-1.45,2.9,-3.0),Vector3.UP)
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+".closeup.png")
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		printerr("Cannot write candidate profile")
		quit(3)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("EQUIPMENT RENDER optimized=%s FPS=%.3f low1=%.3f p99=%.3f load=%.1f setup=%.1f" % [optimized,report.average_fps,report.one_percent_low_fps,report.p99_ms,load_ms,setup_ms])
	quit()
