extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await physics_frame
	var world=game.discarded_items
	var parcel: Dictionary={"paper":{"lesson":true}}
	for slot in 96:
		var position: Vector3=world._available_table_position()
		world.drops[slot+1]={"position":position,"expires":0,"label":"Occupied","owner":2,"parcel":parcel,"token":"f".repeat(31)+str(slot%10)}
	var entries: Dictionary={}
	for index in world.PERSONAL_LIMIT+1:
		var token: String=Crypto.new().generate_random_bytes(16).hex_encode()
		entries[token]={"label":"Worksheet","parcel":parcel,"ground":false}
	assert(world._save_entries(entries))
	assert(world._import_local(1))
	assert(world.queued_entries.size()==world.PERSONAL_LIMIT and world.drops.size()==96)
	assert(not world.can_track_personal(1) and world._personal_count(3)==0)
	assert(world.host_pending_import.size()==1 and world._local_entries().size()==world.PERSONAL_LIMIT+1)
	world.next_id=97
	world.drops.erase(1);world._fill_tables()
	assert(world.queued_entries.size()==world.PERSONAL_LIMIT-1 and world.drops.size()==96)
	var imported:=0
	for drop in world.drops.values():
		if int(drop.get("owner",0))==1:imported+=1
	assert(imported==1)
	world.drops.erase(97)
	world._process(2.1)
	assert(world.host_pending_import.is_empty() and world._personal_count(1)==world.PERSONAL_LIMIT)
	game.session.roster.erase(1)
	world._roster_changed()
	assert(world.queued_entries.is_empty())
	for drop in world.drops.values():assert(int(drop.get("owner",0))!=1)
	print("LOST_FOUND_QUEUE_PASS")
	quit(0)
