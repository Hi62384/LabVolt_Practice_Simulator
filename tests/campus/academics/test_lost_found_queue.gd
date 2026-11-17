extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await physics_frame
	var world=game.discarded_items
	for slot in 96:
		var position: Vector3=world._available_table_position()
		world.drops[slot+1]={"position":position,"expires":0,"label":"Occupied","owner":2,"parcel":{"wire":true,"dc":false,"station":0,"color":0},"token":"f".repeat(31)+str(slot%10)}
	var entries: Dictionary={}
	for color in [1,2]:
		var token: String=Crypto.new().generate_random_bytes(16).hex_encode()
		entries[token]={"label":"Cable","parcel":{"wire":true,"dc":false,"station":0,"color":color}}
	world._import_entries(1,entries)
	assert(world.queued_entries.size()==2 and world.drops.size()==96)
	world.drops.erase(1);world._fill_tables()
	assert(world.queued_entries.size()==1 and world.drops.size()==96)
	var imported:=0
	for drop in world.drops.values():
		if int(drop.get("owner",0))==1:imported+=1
	assert(imported==1)
	game.session.roster.erase(1)
	world._roster_changed()
	assert(world.queued_entries.is_empty())
	for drop in world.drops.values():assert(int(drop.get("owner",0))!=1)
	print("LOST_FOUND_QUEUE_PASS")
	quit(0)
