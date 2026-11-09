extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await create_timer(.6).timeout
	game.capture()
	game.player.position=Vector3(0,0,8.5)
	game.player.enabled=false
	game.camera.fov=92
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/three_benches.png")
	quit()
