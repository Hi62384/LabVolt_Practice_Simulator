extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	var kit: Dictionary=game.electronics.profile.data.kits.starter
	kit.board.parts=[{"id":"battery","type":"battery","a":"A1","b":"F1"},{"id":"load","type":"r1000","a":"B1","b":"G1"}]
	game.electronics.open("design")
	for i in 10:await process_frame
	assert(game.electronics.canvas.analyzer_enabled)
	assert(abs(float(game.electronics.canvas.currents.get("board/load",0))-.005)<.0001)
	assert(not game.electronics.profile.data.analyzer)
	for station in game.dc_lab.benches:assert(station.board.is_empty())
	var before=game.electronics.profile.data.dollars
	game.electronics.open("shop")
	for i in 3:await process_frame
	assert(game.electronics.profile.data.dollars==before)
	game.electronics.open("design")
	for i in 3:await process_frame
	print("PASS: designer preview measures battery circuit without a purchase or changing deployed benches")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://designer_review.png")
	quit()


