extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 6:await process_frame
	var camera:=Camera3D.new();game.add_child(camera);camera.current=true;camera.fov=70
	camera.global_position=Vector3(13,1.7,14);camera.look_at(Vector3(10.8,1.0,11))
	for i in 10:await process_frame
	await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/scattered-computer.png"))
	print("SCATTERED_VISUAL ","PASS" if error==OK else "FAIL")
	game.queue_free();await process_frame;quit(0 if error==OK else 1)
