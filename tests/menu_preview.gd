extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/title_screen.png")
	game.front.characters_page()
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/characters_screen.png")
	game.capture()
	game._receive_pose(42,{"position":Vector3(0,0,-.4),"yaw":PI,"pitch":0,"crouch":false})
	game.player.enabled=false
	await create_timer(1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/avatar_preview.png")
	game.front.pause_menu()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/pause_screen.png")
	quit()
