extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in range(4):await process_frame
	game.school.identities[1]="world-test"
	var original: Vector3=game.player.position
	game.shop_room.enter();assert(game.shop_room.active);assert(game.player.position.x==26)
	game.shop_room.leave();assert(game.player.position==original);assert(not game.shop_room.active)
	game.kit_world.request({"op":"equip","id":"starter","name":"Starter kit"})
	await process_frame
	assert(game.kit_world.held());assert(game.kit_world.visuals.has(1))
	game.player.position=Vector3(0,0,7.5)
	game.kit_world.request({"op":"place","position":Vector3(0,.895,8.1)})
	assert(not game.kit_world.held());game.kit_world.request({"op":"open"});assert(game.kit_world.kits[1].open)
	var design=load("res://scripts/breadboard_model.gd").empty()
	game.dc_lab.accept(1,1,{"op":"board","design":design})
	await process_frame
	assert(game.dc_lab.benches[1].board_owner==1);assert(game.dc_lab.physical_boards[1].visible)
	game.kit_world.request({"op":"close"});assert(game.kit_world.kits[1].open)
	game.kit_world.request({"op":"close","recall":true});assert(not game.kit_world.kits[1].open);assert(game.dc_lab.benches[1].board.is_empty())
	print("PASS: shop return preserves position, physical kit carries/places/opens, physical board deploys, closing requires recall confirmation")
	quit()
