extends SceneTree
func _initialize():call_deferred("run")
func run():
	var B=load("res://scripts/breadboard_model.gd")
	var board=B.empty();board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
	var bp=B.blueprint(board,"Original");bp.layout={"rows":30,"parts":board.parts.duplicate(true),"wires":[]};bp.programs={"m":{"firmware":"halt"}}
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 5:await process_frame
	var profile=game.electronics.profile;profile.data.blueprints={"ic:copytest":bp.duplicate(true)}
	var money=profile.data.dollars
	game.electronics.edit_package("ic:copytest")
	var copy=profile.data.kits[profile.data.equipped].board
	assert(copy.parts==board.parts and copy.programs["board/m"].firmware=="halt")
	game.electronics.open("ics",1)
	for i in 3:await process_frame
	assert(profile.data.kits[profile.data.equipped].package_draft==bp)
	copy.parts[0].a="A2"
	assert(profile.data.blueprints["ic:copytest"]==bp and profile.data.dollars==money)
	print("PASS: editable package copy preserves circuit and firmware, original immutable, no purchase")
	quit()
