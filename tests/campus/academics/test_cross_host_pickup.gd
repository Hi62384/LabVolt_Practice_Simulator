extends SceneTree
const Claims=preload("res://scripts/campus/lost_found/claim_authority.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await physics_frame
	var world=game.discarded_items
	var token: String=Crypto.new().generate_random_bytes(16).hex_encode()
	var point: Vector3=game.player.global_position
	game.session.online=true
	world.drops[901]={"position":point,"expires":0,"label":"Yellow cable","parcel":{"wire":true,"dc":false,"station":0,"color":2},"owner":1,"token":token}
	await world._pickup(1,901,0)
	await create_timer(.2).timeout
	var available: Dictionary=await Claims.status(world,token)
	assert(available.get("ok",false) and not available.get("claimed",true))
	assert(world.drops.has(901))
	await world._pickup(1,901,6)
	assert(not world.drops.has(901))
	assert(2 in game.session.labs[0].stored_cables.get(1,[]))
	world.drops[902]={"position":point,"expires":0,"label":"Yellow cable","parcel":{"wire":true,"dc":false,"station":0,"color":2},"owner":1,"token":token}
	await world._pickup(1,902,6)
	assert(not world.drops.has(902))
	assert(game.session.labs[0].stored_cables.get(1,[]).count(2)==1)
	print("CROSS_HOST_PICKUP_PASS")
	quit(0)
