extends SceneTree
## Render-only production campus fixture; runtime owner executes with a real renderer.
var camera: Camera3D
var world: Node3D
func _initialize() -> void: call_deferred("run")
func capture(file_name: String, eye: Vector3, target: Vector3) -> void:
	camera.position = eye; camera.look_at(target)
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://review_artifacts/elevator_20261107/" + file_name + ".png")
	print("ELEVATOR_SCREENSHOT ", file_name, " result=", result)
func run() -> void:
	root.size = Vector2i(1280, 720)
	world = preload("res://scripts/campus/world/campus_world.gd").new(); root.add_child(world)
	var environment := WorldEnvironment.new(); var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR; settings.background_color = Color("b5c3c9")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE; settings.ambient_light_energy = 0.55
	environment.environment = settings; root.add_child(environment)
	camera = Camera3D.new(); camera.fov = 72; root.add_child(camera); camera.current = true
	var state = preload("res://scripts/campus/elevator/elevator_state.gd").new()
	world.elevator_geometry.apply_snapshot(state.snapshot(), false)
	await capture("entrance_open", Vector3(12.7, 1.65, 57.1), Vector3(16.2, 1.8, 59))
	await capture("cabin_interior", Vector3(22.5, 1.65, 59.8), Vector3(16.3, 1.6, 59.4))
	state.request(1, true); state.advance(1.3, false, {}, true)
	world.elevator_geometry.apply_snapshot(state.snapshot(), true)
	await create_timer(0.4).timeout
	await capture("doors_closing", Vector3(12.7, 1.65, 57.1), Vector3(16.2, 1.8, 59))
	state.advance(0.9, false, {}, true)
	world.elevator_geometry.apply_snapshot(state.snapshot(), false)
	await capture("doors_closed_travel", Vector3(12.7, 1.65, 57.1), Vector3(16.2, 1.8, 59))
	await capture("waiting_area", Vector3(14.5, 1.65, 61.8), Vector3(10.8, 1.1, 64.8))
	quit()
