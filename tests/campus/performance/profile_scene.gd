extends SceneTree
## Exclusive rendered lease only. Run each case in a fresh process.
## -- --density=Off --seconds=15 --warmup=5 --output=<absolute-json> --width=1920 --height=1080
const Probe = preload("res://scripts/campus/performance/frame_probe.gd")
const Crowd = preload("res://scripts/campus/npcs/local_crowd.gd")
var game: Node
var probe: Node
var crowd: Node3D
var seconds := 15.0
var warmup := 5.0
var density := "Off"
var output := "user://campus-profile.json"
var width := 1920
var height := 1080

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"--density": density = pair[1]
			"--seconds": seconds = clampf(float(pair[1]), 1.0, 120.0)
			"--warmup": warmup = clampf(float(pair[1]), 0.0, 30.0)
			"--output": output = pair[1]
			"--width": width = int(pair[1])
			"--height": height = int(pair[1])
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Rendered profile requires a graphical display and exclusive profiling lease.")
		quit(2)
		return
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	probe = Probe.new()
	root.add_child(probe)
	var start := Time.get_ticks_usec()
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	var load_ms := (Time.get_ticks_usec() - start) / 1000.0
	game.capture()
	game.player.position = Vector3(0, 0, 8.5)
	game.player.enabled = false
	game.camera.fov = 92
	crowd = Crowd.new()
	root.add_child(crowd)
	crowd.auto_density = false # Fixed presets must be comparable across runs.
	crowd.set_density(density)
	# Test-only opaque zone, not a production room ID; stationary repeated camera.
	crowd.set_routes("benchmark", [PackedVector3Array([Vector3(-4, 0, 3), Vector3(4, 0, 3), Vector3(4, 0, -4), Vector3(-4, 0, -4)])])
	crowd.set_context("benchmark", game.camera.global_position)
	await create_timer(warmup).timeout
	probe.enabled = false
	var warmup_report: Dictionary = probe.report()
	probe.free()
	probe = Probe.new()
	root.add_child(probe)
	await create_timer(seconds).timeout
	probe.enabled = false
	var report: Dictionary = probe.report()
	report.scenario = "snapshot02 static lab view; three existing DC benches idle; no remote peers"
	report.density = density
	report.crowd = crowd.get_stats()
	report.width = width
	report.height = height
	report.vsync = "disabled"
	report.sample_seconds_requested = seconds
	report.warmup_seconds = warmup
	report.warmup_observed = warmup_report
	report.scene_load_ms = load_ms
	report.live_project = false
	report.network_payload_instrumented = false
	report.solver_instrumented = false
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write profile " + output)
		quit(3)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PROFILE %s: %.1f FPS, 1%% low %.1f FPS, p99 %.2f ms, load %.1f ms, active students %d" % [density, report.average_fps, report.one_percent_low_fps, report.p99_ms, load_ms, report.crowd.active])
	quit()
