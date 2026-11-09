extends SceneTree
const Crowd = preload("res://scripts/campus/npcs/local_crowd.gd")
const Runtime = preload("res://scripts/campus/performance/runtime.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	var crowd := Crowd.new()
	crowd.allow_headless = true
	root.add_child(crowd)
	crowd.set_process(false)
	crowd.auto_density = false
	crowd.set_density("Low")
	crowd.set_routes("async_test", [PackedVector3Array([Vector3.ZERO, Vector3(2,0,0)])])
	crowd.set_context("async_test", Vector3.ZERO)
	var start := Time.get_ticks_msec()
	while crowd.get_stats().active < 4 and Time.get_ticks_msec() - start < 5000:
		crowd.advance(0.1)
		await create_timer(0.01).timeout
	check(crowd.get_stats().active == 4, "threaded source loading reaches configured population")
	check(crowd.get_stats().templates == 2, "two threaded assets loaded")
	crowd.set_context("async_test", Vector3(1000,0,0))
	crowd.advance(0.1)
	check(crowd.get_stats().active == 0, "distance culls all local students")
	crowd.free()
	var runtime := Runtime.new()
	root.add_child(runtime)
	runtime.set_density("High")
	runtime.attach(null, null)
	check(not is_instance_valid(runtime.crowd), "headless runtime has no decorative crowd allocation")
	var probe: Node = runtime.enable_profiling(false)
	await process_frame
	check(is_instance_valid(probe), "optional profiling attaches independently of crowd")
	runtime.free()
	await process_frame
	print("PERFORMANCE THREADED: 5 checks, %d failures" % failures)
	quit(1 if failures else 0)
