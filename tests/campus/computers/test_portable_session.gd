extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4: await process_frame
	var profile=game.electronics.profile
	profile.open("portable-session-test")
	game.school.local_identity=profile.data.dorm.owner
	profile.data.dollars=10000
	profile.buy_portable_laptop("basic")
	var laptop_ids: Array=profile.data.dorm.get("portable_laptops",{}).keys()
	if laptop_ids.is_empty(): fail("Laptop purchase failed");return
	profile.buy_usb(8)
	var ids: Array=profile.data.dorm.get("usb_drives",{}).keys()
	if ids.is_empty(): fail("USB purchase failed");return
	var id: String=ids[0]
	if Archive.save(game.school.local_identity,id,"USB drive",8,Drive.new(8*1024*1024))!=OK: fail("Archive setup failed");return
	game.session.online=false
	game.session.roster[1]={}
	var point: Vector3=game.player.global_position
	game.session.poses[1]={"position":point}
	var service=game.computers
	var world=game.portable_laptops
	var laptop_id: String=laptop_ids[0]
	if not world.place(laptop_id,point,0): fail("Physical laptop placement failed");return
	var station: String=world.placed[laptop_id].station
	var model: Node3D=world.placed[laptop_id].model
	var body: StaticBody3D
	var port: StaticBody3D
	var button: StaticBody3D
	for target in model.find_children("*","StaticBody3D",true,false):
		match target.get_meta("role",""):
			"portable_laptop":body=target
			"public_computer_usb":port=target
			"public_computer_power":button=target
	if body==null or port==null or button==null: fail("Laptop interaction targets missing");return
	game.hotbar._sync_dorm_items()
	var laptop_found:=false
	for slot in game.hotbar.slots:
		if slot.get("kind","")=="portable_laptop" and slot.get("id","")==laptop_ids[0]:
			laptop_found=game.hotbar.title(slot)=="Basic laptop" and game.hotbar.portraits.texture(slot,profile)!=null
	if not laptop_found: fail("Purchased laptop missing from hotbar");return
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("id","")==id:game.hotbar.active=i
	world.interact(port,false)
	if service.stations[station].power.usb.is_empty(): fail("USB did not mount");return
	world.interact(button,false)
	world.interact(body,true)
	world.interact(body,true)
	if service.local_snapshot.get("tier","")!="basic": fail("Portable desktop did not open with tier");return
	service.request({"op":"save","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"path":"notes.txt","text":"Laptop test","version":0})
	var loaded: Dictionary=Archive.load(game.school.local_identity,id,8)
	if loaded.has("error") or loaded.drive.entries.get("notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()!="Laptop test": fail("Laptop USB save failed");return
	if world.pickup(laptop_id): fail("Powered laptop was picked up");return
	world.interact(button,false)
	world.interact(port,false)
	world.interact(body,false)
	world.interact(body,false)
	if world.placed.has(laptop_id) or service.stations.has(station): fail("Laptop could not be picked up after power off and USB removal");return
	if profile.data.dorm.portable_laptops[laptop_id].location!="hotbar": fail("Laptop ownership was lost");return
	if not world.place(laptop_id,point,0): fail("Laptop could not be placed again");return
	game.hotbar._sync_dorm_items()
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("id","")==id:game.hotbar.active=i
	service.request({"op":"usb_port","station":station})
	service.request({"op":"power","station":station})
	service._reset();world._reset()
	if profile.data.dorm.usb_drives[id].location!="lost" or profile.data.dorm.portable_laptops[laptop_id].location!="hotbar": fail("Session reset did not recover the connected USB and laptop");return
	loaded=Archive.load(game.school.local_identity,id,8)
	if loaded.has("error") or loaded.drive.entries["notes.txt"].data.get_string_from_utf8()!="Laptop test": fail("Reset lost USB data");return
	print("PORTABLE_SESSION PASS")
	game.queue_free();await process_frame;quit()
func fail(message: String) -> void:
	push_error(message);quit(1)
