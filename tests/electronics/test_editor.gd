extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for f in 4:await process_frame
	game.electronics.open("board")
	for f in 3:await process_frame
	var canvas=game.electronics.canvas
	canvas.board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
	canvas.selected=["r"];canvas.copy_selected();assert(canvas.paste_selected())
	assert(canvas.board.parts.size()==2)
	assert(canvas.board.parts[1].a=="A2" and canvas.board.parts[1].b=="F2")
	canvas.undo();assert(canvas.board.parts.size()==1)
	canvas.zoom=1.4;canvas.pan=Vector2(20,30)
	game.electronics.close();game.electronics.board_view={};game.electronics.load_view()
	assert(game.electronics.board_view.starter.zoom==1.4)
	assert(game.electronics.board_view.starter.pan==Vector2(20,30))
	# Equip requests require a live player, a carried kit and host authority.
	# This menu-only fixture tests the downstream paper occupancy contract,
	# rather than forging an impossible equip request during startup.
	game.kit_world.kits[1]={"id":"starter","owner":1,"held":true}
	assert(game.school._holding_kit(1),"Held kit must block paper-hand occupancy")
	print("PASS: copy uses free holes, undo restores design, editor zoom/pan persists, held kits recognized by paper system")
	quit()
