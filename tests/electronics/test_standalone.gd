extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var B=load("res://scripts/breadboard_model.gd")
	var source=B.empty();source.parts=[{"id":"load","type":"r1000","a":"A1","b":"F1"}]
	var bp=B.blueprint(source,"1 kΩ load PCB");bp.pins=[{"name":"Supply +","node":"L1"},{"name":"Return","node":"R1"}];bp.package="PCB";bp.footprint={"width":8,"height":6,"color":"24775b"};bp.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]}
	var defs={"ic:standalone_test":bp};var board=B.standalone("ic:standalone_test",defs)
	assert(B.validate(board,{"ic:standalone_test":1})=="")
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.player.position=Vector3(0,0,7.5)
	game.dc_lab.accept(1,1,{"op":"board","design":board})
	var station=game.dc_lab.benches[1]
	station.master=true;station.channels[0].enabled=true
	assert(station.apply({"op":"wire","a":"CH1+","b":"X1"})=="")
	assert(station.apply({"op":"wire","a":"CH1-","b":"X2"})=="")
	station.step(.0005);assert(abs(float(station.result.i["board/pcb/load"])-.005)<.0001)
	assert(station.apply({"op":"carry_board"})!="")
	game.dc_lab.broadcast()
	for i in 3:await process_frame
	assert(game.dc_lab.physical_boards[1].external_ports.size()==2)
	station.wires=[];assert(station.apply({"op":"carry_board"})=="")
	assert(station.apply({"op":"stow_board"})=="");assert(station.board_stowed)
	var profile=game.electronics.profile;profile.data.blueprints=defs;profile.data.inventory["ic:standalone_test"]=1
	game.electronics.prepare_standalone("ic:standalone_test")
	for i in 4:await process_frame
	assert(game.electronics.canvas.board.standalone)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://standalone_review.png")
	print("PASS: owned standalone PCB, named physical pins, actual external supply current, wired movement lock, stow and inspector")
	quit()
