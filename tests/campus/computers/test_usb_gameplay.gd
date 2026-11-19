extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var profile=game.electronics.profile
	profile.open("usb-gameplay-test")
	game.school.local_identity=profile.data.dorm.owner
	profile.data.dollars=1000
	profile.buy_usb(8)
	var ids: Array=profile.data.dorm.get("usb_drives",{}).keys()
	if ids.is_empty():push_error("USB purchase setup failed");quit(1);return
	var id: String=ids[0]
	if Archive.save(game.school.local_identity,id,"USB drive",8,Drive.new(8*1024*1024))!=OK:push_error("Archive setup failed");quit(1);return
	game.session.online=false
	game.session.roster[1]={}
	var station: String="commons_r0_c0"
	var point: Vector3=game.computers.stations[station].anchor
	game.session.poses[1]={"position":point};game.player.global_position=point
	game.hotbar._sync_dorm_items()
	var slot: int=-1
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("id","")==id:slot=i
	if slot<0:push_error("USB missing from hotbar");quit(1);return
	game.hotbar._rename_usb_dialog(id)
	var dialog: ConfirmationDialog
	for node in game.electronics.screen.find_children("*","ConfirmationDialog",true,false):
		if node.title=="Rename USB drive":dialog=node;break
	if dialog==null:push_error("USB rename dialog missing");quit(1);return
	var fields:=dialog.find_children("*","LineEdit",true,false)
	if fields.is_empty():push_error("USB rename field missing");quit(1);return
	fields[0].text="Lab work";dialog.confirmed.emit()
	if profile.data.dorm.usb_drives[id].name!="Lab work":push_error("USB rename did not persist");quit(1);return
	game.hotbar.active=slot
	var service: Node=game.computers
	service.request({"op":"usb_port","station":station})
	if service.stations[station].power.usb.is_empty():push_error("Port failed to mount");quit(1);return
	service.request({"op":"power","station":station})
	await create_timer(1.8).timeout
	service.request({"op":"enter","station":station})
	if service.local_snapshot.is_empty():push_error("Desktop failed to open");quit(1);return
	service.request({"op":"save","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"path":"notes.txt","text":"USB test","version":0})
	var pdf: PackedByteArray="%PDF-1.7\nfixture".to_ascii_buffer()
	service.last_request.erase(1)
	service.request({"op":"download","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"name":"manual.pdf","bytes":pdf})
	assert("Downloads/manual.pdf" in service.local_snapshot.copyable_downloads)
	assert(not service.stations[station].power.usb.drive.entries.has("Downloads/manual.pdf"))
	service.last_request.erase(1)
	service.request({"op":"copy_download","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"path":"Downloads/manual.pdf"})
	var loaded: Dictionary=Archive.load(game.school.local_identity,id,8)
	if loaded.has("error") or loaded.name!="Lab work" or loaded.drive.entries.get("notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()!="USB test":push_error("Desktop save did not persist");quit(1);return
	assert(loaded.drive.entries["Downloads/manual.pdf"].data==pdf)
	service.request({"op":"usb_port","station":station})
	if service.stations[station].power.usb.is_empty():push_error("Powered USB removed");quit(1);return
	service.request({"op":"power","station":station})
	profile.data.dorm.usb_drives[id].location="lost"
	service.request({"op":"usb_port","station":station})
	if service.stations[station].power.usb.is_empty():push_error("Stale USB location allowed removal");quit(1);return
	profile.data.dorm.usb_drives[id].location="connected"
	service.stations[station].power.usb.owner="c".repeat(48)
	service.request({"op":"usb_port","station":station})
	if service.stations[station].power.usb.is_empty():push_error("Wrong USB owner allowed removal");quit(1);return
	service.stations[station].power.usb.owner=game.school.local_identity
	service.request({"op":"usb_port","station":station})
	if not service.stations[station].power.usb.is_empty() or profile.data.dorm.usb_drives[id].location!="hotbar":push_error("USB removal failed");quit(1);return
	if service.public_workspaces.has(station):push_error("Powered-off workstation retained temporary files");quit(1);return
	station="commons_r0_c1"
	point=service.stations[station].anchor
	game.session.poses[1]={"position":point};game.player.global_position=point
	game.hotbar._sync_dorm_items()
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("id","")==id:game.hotbar.active=i
	service.request({"op":"usb_port","station":station})
	service.request({"op":"power","station":station})
	await create_timer(1.8).timeout
	service.request({"op":"enter","station":station})
	if service.local_snapshot.get("files",{}).get("notes.txt",{}).get("text","")!="USB test":push_error("Another workstation did not reopen the USB file");quit(1);return
	service._reset()
	if profile.data.dorm.usb_drives[id].location!="lost":push_error("Connected USB was not marked lost on leave");quit(1);return
	var lost: Node=game.discarded_items
	# The simulated restart resets the inventory import guard as a real leave does.
	lost._leaving()
	lost._import_local(1)
	var drop_id: int=-1
	for key in lost.drops:
		if lost.drops[key].get("parcel",{}).get("usb",{}).get("id","")==id:drop_id=key
	if drop_id<0:push_error("USB was not added to lost and found");quit(1);return
	game.player.global_position=lost.drops[drop_id].position
	lost._pickup(1,drop_id,0)
	if not lost.drops.has(drop_id):push_error("Full hotbar lost the USB");quit(1);return
	lost._pickup(1,drop_id,1)
	if lost.drops.has(drop_id) or profile.data.dorm.usb_drives[id].location!="hotbar":push_error("USB reclaim failed");quit(1);return
	loaded=Archive.load(game.school.local_identity,id,8)
	if loaded.has("error") or loaded.drive.entries["notes.txt"].data.get_string_from_utf8()!="USB test":push_error("Reclaimed USB lost its data");quit(1);return
	print("USB_GAMEPLAY PASS")
	game.queue_free();await process_frame;quit()
