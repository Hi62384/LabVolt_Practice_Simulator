extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const Preferences=preload("res://scripts/campus/computers/desktop_preferences.gd")
var game: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	print("USB DEBUG ",label," roster=",game.session.roster.size()," bound=",game.electronics_trade.authority.bound," drives=",game.electronics.profile.data.get("dorm",{}).get("usb_drives",{}))
	push_error("USB NETWORK TIMEOUT: "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [2,3] or args[0] not in ["host","client"] or not args[1].is_valid_int():quit(1);return
	var role:=str(args[0]);var port:=int(args[1]);var station:="commons_r0_c0"
	var disconnect_case: bool=args.size()==3 and args[2]=="disconnect"
	var save_error_case: bool=args.size()==3 and args[2]=="save_error"
	var interrupted_case: bool=args.size()==3 and args[2]=="interrupted_write"
	var handoff_abort: bool=args.size()==3 and args[2]=="handoff_source_abort"
	var handoff_case: bool=args.size()==3 and args[2] in ["handoff","handoff_source_abort"]
	var purchase_case: bool=args.size()==3 and args[2]=="purchase"
	var download_case: bool=args.size()==3 and args[2]=="download"
	var wallpaper_case: bool=args.size()==3 and args[2]=="wallpaper"
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var profile=game.electronics.profile
	profile.open("usb-network-"+role)
	game.school.local_identity=profile.data.dorm.owner
	var drive_id: String=""
	if role=="client":
		profile.data.dollars=1000
		if not purchase_case:
			profile.buy_usb(8)
			drive_id=str(profile.data.dorm.usb_drives.keys()[0])
			var drive=Drive.new(8*1024*1024);drive.write_file("network.txt","owner data".to_utf8_buffer())
			if wallpaper_case:
				var image:=Image.create_empty(320,180,false,Image.FORMAT_RGB8)
				image.fill(Color.CORNFLOWER_BLUE)
				var settings:={"wallpaper":Preferences.CUSTOM_WALLPAPER,"image":Marshalls.raw_to_base64(image.save_jpg_to_buffer(.9))}
				assert(drive.write_file(Preferences.PATH,JSON.stringify(settings).to_utf8_buffer()))
			if handoff_abort:
				var payload:=PackedByteArray();payload.resize(4*1024*1024)
				drive.write_file("large.bin",payload)
			if Archive.save(game.school.local_identity,drive_id,"USB drive",8,drive)!=OK:push_error("USB archive fixture failed");quit(1);return
		if handoff_case:
			profile.data.dorm.carry_items.erase("usb:"+drive_id);profile.data.dorm.usb_drives[drive_id].location="lost"
			if profile.save()!=OK:push_error("Lost USB fixture failed");quit(1);return
	var service: Node=game.computers
	var point: Vector3=service.stations[station].anchor
	deadline=Time.get_ticks_msec()+60000
	if role=="host":
		if game.session.host_game("USB host",port)!=OK:push_error("Host failed");quit(1);return
		print("USB_HOST_READY")
		if not await until(func():return game.session.roster.size()==2,"client joined"):return
		if handoff_case:
			if not await until(func():return game.electronics_trade.authority.bound and game.discarded_items.drops.values().any(func(drop):return drop.get("parcel",{}).has("usb")),"lost USB available"):return
			var lost: Node=game.discarded_items
			var drop_id: int=-1
			for key in lost.drops:
				if lost.drops[key].get("parcel",{}).has("usb"):drop_id=int(key);break
			var original: Dictionary=lost.drops[drop_id].parcel.usb
			game.player.global_position=lost.drops[drop_id].position
			lost._pickup(1,drop_id,1)
			if handoff_abort:
				if not await until(func():return game.session.roster.size()==1 and lost.usb_handoffs.pending.is_empty(),"sender disconnected and reservation aborted"):return
				var ledger=game.electronics_trade.authority.ledger
				if ledger.state.accounts[original.owner].profile.dorm.usb_drives[original.id].location!="lost" or profile.data.dorm.get("usb_drives",{}).has(original.id):push_error("Interrupted handoff changed ownership");quit(1);return
				if not await until(func():return game.session.roster.size()==2 and ledger.bindings.values().has(original.owner),"sender reconnected"):return
				if ledger.state.accounts[original.owner].profile.dorm.usb_drives[original.id].location!="lost":push_error("Sender recovery did not restore lost state");quit(1);return
				print("USB_HOST_HANDOFF_ABORT PASS")
				game.session.leave();game.queue_free();await process_frame;quit();return
			if not await until(func():return profile.data.dorm.get("usb_drives",{}).has(original.id),"recipient committed"):return
			var received: Dictionary=Archive.load(game.school.local_identity,original.id,int(original.capacity_mb))
			if received.has("error") or received.drive.entries["network.txt"].data.get_string_from_utf8()!="owner data":push_error("Recipient archive is invalid");quit(1);return
			await create_timer(.5).timeout
			print("USB_HOST_HANDOFF PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		if not await until(func():return not service.stations[station].power.usb.is_empty(),"USB mounted"):return
		var usb: Dictionary=service.stations[station].power.usb
		if wallpaper_case:
			if not await until(func():return service.stations[station].power.powered,"client powered workstation"):return
			assert(not game.computer_room_adapter.usb_previews.has(station),"Host saw another player's private wallpaper")
		if usb.drive.entries.get("network.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()!="owner data":push_error("Uploaded USB data differs");quit(1);return
		if interrupted_case:
			var owner_peer:=0
			for peer in game.electronics_trade.authority.ledger.bindings:
				if game.electronics_trade.authority.ledger.bindings[peer]==usb.owner:owner_peer=int(peer)
			if owner_peer==0:push_error("USB owner not bound");quit(1);return
			service.stations[station].power.turn_on(Time.get_ticks_msec())
			service.usb_writes[station]={"token":"fixture","owner_peer":owner_peer,"actor":owner_peer,"lease":0,"entries":{},"workspace":{},"started":Time.get_ticks_msec()-31000}
			service._prune()
			if not service.stations[station].power.usb.is_empty() or service.stations[station].power.powered:push_error("Timed-out USB remained mounted");quit(1);return
			await create_timer(.5).timeout
			print("USB_HOST_INTERRUPTED PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		if disconnect_case:
			var owner: String=usb.owner;var usb_id: String=usb.id
			if not await until(func():return service.sessions.values().any(func(session):return session.station==station),"USB desktop opened before disconnect"):return
			if not await until(func():return service.stations[station].power.usb.is_empty(),"disconnected USB recovered"):return
			if service.stations[station].power.powered or service.public_workspaces.has(station) or service.sessions.values().any(func(session):return session.station==station):push_error("Disconnected USB left an active computer session");quit(1);return
			var account: Dictionary=game.electronics_trade.authority.ledger.state.accounts.get(owner,{})
			if account.get("profile",{}).get("dorm",{}).get("usb_drives",{}).get(usb_id,{}).get("location","")!="lost":push_error("Disconnected USB was not marked lost");quit(1);return
			if not await until(func():return game.electronics_trade.authority.ledger.state.accounts.get(owner,{}).get("profile",{}).get("dorm",{}).get("usb_drives",{}).get(usb_id,{}).get("location","")=="hotbar","reconnected owner reclaimed USB"):return
			print("USB_HOST_DISCONNECT PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		if not await until(func():return service.stations[station].power.usb.is_empty(),"USB removed"):return
		if not await until(func():return not service.stations[station].power.usb.is_empty(),"USB reinserted"):return
		if service.stations[station].power.usb.drive.entries["network.txt"].data.get_string_from_utf8()!="updated by client":push_error("Reinserted USB data differs");quit(1);return
		if not await until(func():return service.stations[station].power.usb.is_empty(),"reinserted USB removed"):return
		print("USB_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","USB student",port)!=OK:push_error("Join failed");quit(1);return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound,"inventory bound"):return
		if purchase_case:
			profile.buy_usb(8)
			if not await until(func():return not profile.data.dorm.get("usb_drives",{}).is_empty(),"USB purchase acknowledged"):return
			drive_id=str(profile.data.dorm.usb_drives.keys()[0])
			var purchased: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
			if purchased.has("error") or not purchased.drive.entries.is_empty():push_error("Purchased USB archive was not initialized");quit(1);return
			purchased.drive.write_file("network.txt","owner data".to_utf8_buffer())
			if Archive.save(game.school.local_identity,drive_id,"USB drive",8,purchased.drive)!=OK:quit(1);return
		if handoff_case:
			if handoff_abort:
				if not await until(func():return profile.data.dorm.get("usb_drives",{}).get(drive_id,{}).get("location","")=="handoff","sender reservation"):return
				var retained: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
				if retained.has("error") or retained.drive.entries["large.bin"].data.size()!=4*1024*1024:push_error("Sender archive was not preserved");quit(1);return
				game.session.leave();await create_timer(2.0).timeout
				if game.session.join_game("127.0.0.1","USB student",port)!=OK:push_error("Sender reconnect failed");quit(1);return
				if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound and profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="lost","sender reservation recovered"):return
				await create_timer(.5).timeout
				print("USB_CLIENT_HANDOFF_ABORT PASS")
				game.session.leave();game.queue_free();await process_frame;quit();return
			if not await until(func():return not profile.data.dorm.get("usb_drives",{}).has(drive_id),"sender ownership released"):return
			var retained: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
			if retained.has("error") or retained.drive.entries["network.txt"].data.get_string_from_utf8()!="owner data":push_error("Sender backup was lost");quit(1);return
			print("USB_CLIENT_HANDOFF PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		game.player.global_position=point
		if not await until(func():
			game.session.send_pose({"position":point})
			return game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(point)<.6
		,"position accepted"):return
		game.hotbar._sync_dorm_items()
		for index in game.hotbar.slots.size():
			if game.hotbar.slots[index].get("id","")==drive_id:game.hotbar.active=index
		service.request({"op":"usb_port","station":station})
		if not await until(func():return profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="connected","connection confirmed"):return
		if interrupted_case:
			if not await until(func():return profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="lost","timed-out write recovery"):return
			var preserved: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
			if preserved.has("error") or preserved.drive.entries["network.txt"].data.get_string_from_utf8()!="owner data":push_error("Interrupted write lost archive");quit(1);return
			print("USB_CLIENT_INTERRUPTED PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		await create_timer(.5).timeout
		if disconnect_case:
			service.request({"op":"power","station":station})
			await create_timer(1.8).timeout
			service.request({"op":"enter","station":station})
			if not await until(func():return service.local_snapshot.get("public_device",false),"USB desktop before disconnect"):return
			var intact: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
			if intact.has("error") or intact.drive.entries["network.txt"].data.get_string_from_utf8()!="owner data":push_error("USB data not preserved on disconnect");quit(1);return
			game.session.leave()
			await create_timer(2.0).timeout
			if game.session.join_game("127.0.0.1","USB student",port)!=OK:push_error("Reconnect failed");quit(1);return
			if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound and profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="lost","reconnected lost inventory"):return
			var lost: Node=game.discarded_items
			if not await until(func():return lost.drops.values().any(func(drop):return str(drop.get("visual",""))=="usb"),"lost USB appeared"):return
			var drop_id: int=-1
			for key in lost.drops:
				if lost.drops[key].get("visual","")=="usb":drop_id=int(key);break
			var drop_point: Vector3=lost.drops[drop_id].position
			game.player.global_position=drop_point
			if not await until(func():
				game.session.send_pose({"position":drop_point})
				return game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(drop_point)<.6
			,"lost and found position"):return
			lost.request_pickup.rpc_id(1,drop_id,1)
			if not await until(func():return profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="hotbar","reclaimed USB"):return
			print("USB_CLIENT_DISCONNECT PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		service.request({"op":"power","station":station})
		await create_timer(1.8).timeout
		if wallpaper_case:
			if not await until(func():return game.computer_room_adapter.usb_previews.has(station),"wallpaper before desktop opens"):return
			var preview: Control=game.computer_room_adapter.usb_previews[station].viewport.get_child(0)
			assert(service.local_snapshot.is_empty() and preview.wallpaper_choice==Preferences.CUSTOM_WALLPAPER)
			assert(preview.wallpaper_panel.texture.get_size()==Vector2(320,180),"Preview did not load custom image")
		service.request({"op":"enter","station":station})
		if not await until(func():return service.local_snapshot.get("files",{}).has("network.txt"),"USB desktop opened"):return
		if wallpaper_case:
			service.request({"op":"save_preferences","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"settings":{"wallpaper":6}})
			if not await until(func():return service.local_snapshot.get("usb_preferences",{}).get("wallpaper",0)==6,"wallpaper committed"):return
			if not await until(func():return game.computer_room_adapter.usb_previews[station].viewport.get_child(0).wallpaper_choice==6,"wallpaper preview refresh"):return
		if save_error_case:
			var archive_path: String=Archive.path(game.school.local_identity,drive_id)
			if DirAccess.rename_absolute(archive_path,archive_path+".fixture")!=OK:push_error("Could not stage save failure");quit(1);return
			var notices: Array=[]
			service.operation_failed.connect(func(message: String):notices.append(message))
			service.request({"op":"save","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"path":"network.txt","text":"must roll back","version":int(service.local_snapshot.files["network.txt"].version)})
			if not await until(func():return notices.any(func(message):return str(message).contains("USB save failed")),"save failure reported"):return
			if service.local_snapshot.files["network.txt"].text!="owner data":push_error("Failed save changed desktop");quit(1);return
			if DirAccess.rename_absolute(archive_path+".fixture",archive_path)!=OK:push_error("Could not restore save fixture");quit(1);return
			await create_timer(.15).timeout
		service.request({"op":"save","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"path":"network.txt","text":"updated by client","version":int(service.local_snapshot.files["network.txt"].version)})
		if not await until(func():return service.local_snapshot.get("files",{}).get("network.txt",{}).get("text","")=="updated by client","USB write acknowledged"):return
		var edited: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
		if edited.has("error") or edited.drive.entries["network.txt"].data.get_string_from_utf8()!="updated by client":push_error("USB write was not saved on owner client");quit(1);return
		if download_case and not await test_large_download(service,drive_id):return
		service.request({"op":"power","station":station})
		await create_timer(.2).timeout
		service.request({"op":"usb_port","station":station})
		if not await until(func():return profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="hotbar","removal confirmed"):return
		var loaded: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
		if loaded.has("error") or loaded.drive.entries["network.txt"].data.get_string_from_utf8()!="updated by client":push_error("USB archive changed");quit(1);return
		await create_timer(.4).timeout
		game.hotbar._sync_dorm_items()
		for index in game.hotbar.slots.size():
			if game.hotbar.slots[index].get("id","")==drive_id:game.hotbar.active=index
		service.request({"op":"usb_port","station":station})
		if not await until(func():return profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="connected","reinsertion confirmed"):return
		await create_timer(.4).timeout
		service.request({"op":"usb_port","station":station})
		if not await until(func():return profile.data.dorm.usb_drives.get(drive_id,{}).get("location","")=="hotbar","second removal confirmed"):return
		print("USB_CLIENT PASS")
	game.session.leave();game.queue_free();await process_frame;quit()

func test_large_download(service: Node,drive_id: String) -> bool:
	var payload:="%PDF-1.7\n".to_ascii_buffer()
	payload.resize(2*1024*1024+1)
	payload[payload.size()-1]=131
	var path:="Downloads/network.pdf"
	await create_timer(.15).timeout
	service.request({"op":"download","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"name":"network.pdf","bytes":payload})
	if not await until(func():return service.local_snapshot.get("binary_files",{}).get(path,0)==payload.size(),"large download saved to remote USB"):return false
	var saved: Dictionary=Archive.load(game.school.local_identity,drive_id,8)
	if saved.has("error") or saved.drive.entries.get(path,{}).get("data")!=payload:
		push_error("Remote USB did not preserve the large download");quit(1);return false
	print("USB_LARGE_DOWNLOAD PASS")
	return true
