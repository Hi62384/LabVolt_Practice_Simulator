extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1440,1000)
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	var ui=game.electronics;var profile=ui.profile
	var board=load("res://scripts/breadboard_model.gd").empty()
	board.parts=[{"id":"battery","type":"battery","a":"B1","b":"G1"},{"id":"m","type":"lv_mcu","a":"A1","b":"F1","pins":["A1","F1","A2","A3","F2","F3"],"firmware":"mode PWM out\npwm PWM 0.25\nwait 1000\ngoto 3"},{"id":"load","type":"r1000","a":"A4","b":"H1"}];board.wires=[["A4","G3"]]
	profile.data.kits[profile.data.equipped].board=board
	ui.open("design")
	ui.canvas.selected=["load"];ui.canvas.timing_visible=true;ui.canvas.capture.probes("board/R3","board/R1")
	for i in 12:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://editor-analyzer.png")
	ui.page_scroll.scroll_vertical=320
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://editor-trace.png")
	ui.open("ics")
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://editor-package.png")
	ui.page_scroll.scroll_vertical=450
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://editor-package-pins.png")
	var bp=load("res://scripts/breadboard_model.gd").blueprint(board,"Header inspection")
	bp.package="PCB";bp.footprint={"width":8,"height":6,"color":"24775b","thickness_mm":1.6};bp.layout={"rows":board.rows,"parts":board.parts,"wires":[]};bp.marking="LAB / prototype";bp.orientation_marker="triangle"
	for i in bp.pins.size():bp.pins[i].position={"x":0 if i<2 else 7,"y":0 if i%2==0 else 5};bp.pins[i].connector=["male_header","female_header","terminal_block","test_point"][i]
	var key := "preview"
	profile.data.blueprints={"ic:preview":bp}
	profile.data.kits[key]={"name":"Preview","items":{},"board":load("res://scripts/breadboard_model.gd").standalone("ic:preview",profile.data.blueprints)};profile.data.equipped=key
	ui.open("board")
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://editor-standalone.png")
	print("PASS: analyzer/package/standalone previews rendered to isolated user directory")
	quit()
