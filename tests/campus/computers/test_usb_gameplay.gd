extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const Apps=preload("res://scripts/campus/computers/application_registry.gd")
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
	assert(service.local_snapshot.download_path=="Downloads/manual.pdf")
	assert(service.stations[station].power.usb.drive.entries["Downloads/manual.pdf"].data==pdf)
	var desktop: Control=game.computer_room_adapter.desktop
	desktop._switch_app("Files")
	var usage: Dictionary=service.local_snapshot.get("usb_storage",{})
	assert(usage.get("used")==pdf.size()+"USB test".length() and usage.get("capacity")==8*1024*1024)
	var storage: HBoxContainer=desktop.file_list.get_meta("usb_storage")
	assert(storage.visible and "/ 8" in storage.get_child(0).text and storage.get_child(1).max_value==8*1024*1024)
	var loaded: Dictionary=Archive.load(game.school.local_identity,id,8)
	if loaded.has("error") or loaded.name!="Lab work" or loaded.drive.entries.get("notes.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()!="USB test":push_error("Desktop save did not persist");quit(1);return
	assert(loaded.drive.entries["Downloads/manual.pdf"].data==pdf)
	var manifest:={"schema":1,"id":"example.usb","name":"USB App","version":"1.0.0","publisher":"Campus",
		"description":"USB application fixture","entry":"index.html","runtime":"web"}
	var app_bytes: PackedByteArray=Apps.Packages.Zip.new().Pack({"manifest.json":JSON.stringify(manifest).to_utf8_buffer(),
		"index.html":"<!doctype html><title>USB App</title>".to_utf8_buffer()})
	service.last_request.erase(1)
	desktop._browser_save_download("fixture.campusapp",app_bytes)
	service.last_request.erase(1)
	desktop._preview_path("Downloads/fixture.campusapp")
	var install_button: Button
	for button: Button in desktop.file_viewer.find_children("*","Button",true,false):
		if button.text=="Install…":install_button=button;break
	assert(install_button!=null)
	install_button.pressed.emit()
	for setup: Node in desktop.get_children():
		if setup is ConfirmationDialog and setup.title=="Install USB App":
			service.last_request.erase(1)
			setup.confirmed.emit()
			break
	var installed: Dictionary=service.local_snapshot.get("installed_apps",{}).get("example.usb",{})
	assert(not installed.is_empty())
	if DisplayServer.get_name()!="headless":
		service.last_request.erase(1)
		desktop._preview_path(str(installed.archive))
		assert(desktop.windows.has("app:example.usb"))
		var app_view: Control=desktop.windows["app:example.usb"].viewer
		for frame in 60:
			if app_view.browser.get_title()=="USB App":break
			await create_timer(.1).timeout
		assert(app_view.browser.get_title()=="USB App")
		desktop._close_window("app:example.usb")
		service.last_request.erase(1)
		desktop._browser_save_download("draft.html","<!doctype html><title>Saved document</title>".to_utf8_buffer())
		service.last_request.erase(1)
		desktop._run_source("Downloads/draft.html","<!doctype html><title>Unsaved draft</title>",func(result: String):assert(result=="Web preview opened."))
		assert(desktop.windows.has("web:Downloads/draft.html"))
		var project_view: Control=desktop.windows["web:Downloads/draft.html"].viewer
		for frame in 60:
			if project_view.browser.get_title()=="Unsaved draft":break
			await create_timer(.1).timeout
		assert(project_view.browser.get_title()=="Unsaved draft")
		desktop._close_window("web:Downloads/draft.html")
	service.last_request.erase(1)
	desktop._send({"op":"save_app_state","app_id":"example.usb","sha256":installed.sha256,"state":'{"count":1}'})
	loaded=Archive.load(game.school.local_identity,id,8)
	assert(Apps.installed(loaded.drive)["example.usb"].state=='{"count":1}')
	desktop.style_choice=1
	desktop.wallpaper_choice=2
	desktop.pinned_apps=["Calculator"]
	desktop.set_workstation_volume(station,62)
	await create_timer(.35).timeout
	assert(service.local_snapshot.usb_preferences.volume==62)
	assert(not service.local_snapshot.binary_files.has(".campus-os.json"))
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
	game._stand_from_chair()
	if game.player.seated!=null:push_error("Could not stand before moving the USB to the next workstation");quit(1);return
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
	assert(not service.local_snapshot.files.has("Downloads/manual.pdf") and service.local_snapshot.binary_files.has("Downloads/manual.pdf"))
	assert(desktop.style_choice==1 and desktop.wallpaper_choice==2 and desktop.pinned_apps==["Calculator"])
	assert(desktop.workstation_volume(station)==62)
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
	var placement: Node=game.personal_placement
	game.player.global_position=Vector3(13,0,-18)
	await physics_frame
	var floor: Variant=game.school.ground_drop_position(game.player.global_position,1)
	if not floor is Vector3:push_error("USB placement fixture has no floor");quit(1);return
	placement._place(1,"usb:"+id,floor,0.0)
	if not placement.is_placed(1,"usb:"+id):push_error("USB did not place on the floor");quit(1);return
	placement._pickup(1,placement.key_for(1,"usb:"+id))
	if placement.is_placed(1,"usb:"+id):push_error("USB did not return to the hotbar");quit(1);return
	lost.discard({"location":"hotbar","item":{"kind":"usb","id":id}})
	if profile.data.dorm.usb_drives[id].location!="lost" or not lost.drops.values().any(func(drop):return drop.get("parcel",{}).get("usb",{}).get("id","")==id):
		push_error("USB Discard did not produce a recoverable drop");quit(1);return
	await create_timer(.2).timeout
	print("USB_GAMEPLAY PASS")
	game.queue_free();await process_frame;quit()
