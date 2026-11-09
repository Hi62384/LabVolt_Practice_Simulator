extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 6:await process_frame
	var kit: Dictionary=game.electronics.profile.data.kits.starter
	kit.items.lv_mcu=1;game.electronics.profile.data.inventory.lv_mcu=1
	kit.board.parts=[{"id":"mcu","type":"lv_mcu","a":"A1","b":"F1","pins":["A1","A2","A3","F1","F2","F3"]}]
	game.electronics.open("code")
	for i in 4:await process_frame
	var ide=game.electronics.body.get_child(0)
	assert(ide.validate());ide.upload()
	assert(kit.board.parts[0].firmware.contains("wait 500"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://ide_review.png")
	game.electronics.open("board")
	for i in 2:await process_frame
	print("PASS: embedded IDE opens, validates and saves program, closes back to board")
	quit()
