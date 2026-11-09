extends SceneTree
var game: Node3D
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in range(5):await process_frame
	game.front.screen.hide();game.front.in_game=true;game.front.preview_camera.current=false;game.player.inspecting=true
	game.player.global_position=Vector3(0,0,1.4)
	game.camera.current=true;game.camera.global_position=Vector3(0,2.1,2.0);game.camera.look_at(Vector3(0,2,-3))
	game.campus.set_viewer_position(game.player.global_position)
	for frame in range(30):await process_frame
	root.get_texture().get_image().save_png("C:/Users/User1/Documents/Codex/2026-11-03/bas/work/dc_expansion/main_campus_equipment.png")
	game.camera.global_position=Vector3(-1.5,2.8,-1.4);game.camera.look_at(Vector3(-1.5,2.75,-2.8))
	for frame in range(10):await process_frame
	root.get_texture().get_image().save_png("C:/Users/User1/Documents/Codex/2026-11-03/bas/work/dc_expansion/main_campus_closeup.png")
	print("MAIN_RENDER draws=%d primitives=%d"%[Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	game.queue_free();await process_frame;quit()

