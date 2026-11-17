extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	var room="ac_lab"
	var point: Vector3=game.school_world.teacher.global_position
	game.player.global_position=point+Vector3(0,0,2)
	game.campus.set_viewer_position(game.player.global_position)
	game.campus.request_room(room)
	game.faculty._show_reaction(room,str(game.faculty.current[room]),"Please inspect the wiring before turning power on.",point,1,4)
	for i in 25:await process_frame
	await RenderingServer.frame_post_draw
	var path=ProjectSettings.globalize_path("res://.godot/teacher-subtitle.png")
	var error:=root.get_texture().get_image().save_png(path)
	if error!=OK:push_error("Subtitle capture failed");quit(1);return
	print("TEACHER_SUBTITLE_CAPTURE PASS ",path)
	game.queue_free();await process_frame;quit(0)
