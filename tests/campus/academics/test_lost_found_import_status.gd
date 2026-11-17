extends SceneTree
const Claims=preload("res://scripts/campus/lost_found/claim_authority.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await physics_frame
	var world=game.discarded_items
	var parcel: Dictionary={"wire":true,"dc":false,"station":0,"color":1}
	var stale: String=Crypto.new().generate_random_bytes(16).hex_encode()
	var fresh: String=Crypto.new().generate_random_bytes(16).hex_encode()
	world.cache_ground(stale,parcel,"Blue cable")
	assert(world._local_entries().has(stale))
	assert((await Claims.claim(world,stale)).get("ok",false))
	game.session.online=true
	await world._import_entry(1,stale,{"label":"Blue cable","parcel":parcel})
	assert(not world._local_entries().has(stale))
	assert(not world.drops.values().any(func(drop):return str(drop.get("token",""))==stale))
	await world._import_entry(1,fresh,{"label":"Blue cable","parcel":parcel})
	assert(world.drops.values().any(func(drop):return str(drop.get("token",""))==fresh))
	print("LOST_FOUND_IMPORT_STATUS_PASS")
	quit(0)
