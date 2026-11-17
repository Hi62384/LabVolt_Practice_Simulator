extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
var game: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	print("PORTABLE DEBUG ",label," bound=",game.electronics_trade.authority.bound," pending=",game.electronics.profile.data.get("usb_write_pending",{})," decisions=",game.electronics.profile.data.get("usb_write_decisions",{})," drives=",game.electronics.profile.data.get("dorm",{}).get("usb_drives",{}))
	push_error("PORTABLE NETWORK TIMEOUT: "+label);quit(1);return false
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [2,3] or args[0] not in ["host","client"]:fail("Invalid arguments");return
	var role:=str(args[0]);var port:=int(args[1])
	var purchase_case: bool=args.size()==3 and args[2]=="purchase"
	var host_loss_case: bool=args.size()==3 and args[2] in ["host_loss","host_loss_commit","host_loss_uncommitted"]
	var prepared_case: bool=args.size()==3 and args[2] in ["host_loss_commit","host_loss_uncommitted"]
	var committed_case: bool=args.size()==3 and args[2]=="host_loss_commit"
	var production_prepare: bool=args.size()==3 and args[2]=="production_prepare"
	var production_commit: bool=args.size()==3 and args[2]=="production_commit"
	var production_boundary: bool=production_prepare or production_commit
	var token: String="abcdabcdabcdabcdabcdabcdabcdabcd"
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var profile=game.electronics.profile
	profile.open("portable-network-"+role)
	game.school.local_identity=profile.data.dorm.owner
	var laptop:="";var usb:=""
	if role=="client":
		profile.data.dollars=10000
		if not purchase_case:profile.buy_portable_laptop("basic");laptop=str(profile.data.dorm.portable_laptops.keys()[0])
		profile.buy_usb(8);usb=str(profile.data.dorm.usb_drives.keys()[0])
		var drive=Drive.new(8*1024*1024);drive.write_file("note.txt","original".to_utf8_buffer())
		if Archive.save(game.school.local_identity,usb,"USB drive",8,drive)!=OK:fail("Archive setup failed");return
	deadline=Time.get_ticks_msec()+70000
	if role=="host":
		if game.session.host_game("Portable host",port)!=OK:fail("Host failed");return
		print("PORTABLE_HOST_READY")
		if not await until(func():return game.session.roster.size()==2 and not game.portable_laptops.placed.is_empty(),"laptop placed"):return
		laptop=str(game.portable_laptops.placed.keys()[0])
		var world=game.portable_laptops
		var owner_peer: int=world.placed[laptop].peer
		if world._place_for(owner_peer,laptop,world.placed[laptop].position,0):fail("Duplicate placement accepted");return
		if world._change_for(1,laptop,"pickup"):fail("Non-owner picked up laptop");return
		if not await until(func():return game.computers.stations.has(laptop) and not game.computers.stations[laptop].power.usb.is_empty(),"USB connected"):return
		if production_boundary:
			if not await until(func():return game.computers.stations[laptop].power.usb.drive.entries.get("note.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()=="updated" and not game.computers.usb_writes.has(laptop),"acknowledged write"):return
			if production_commit:
				game.computers.usb_write_committed.connect(func(_station,_token):game.session.leave(),CONNECT_ONE_SHOT)
				if not await until(func():return not game.session.online,"host closed at commit"):return
				await create_timer(2.0).timeout
				if game.session.host_game("Portable host",port)!=OK:fail("Host restart failed");return
			else:
				if not await until(func():return game.session.roster.size()==1,"owner left at prepare"):return
			if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.ledger.bindings.size()==2,"owner rebound"):return
			if game.portable_laptops.placed.has(laptop):fail("Laptop remained deployed");return
			if not await until(func():return game.session.roster.size()==1,"owner left after recovery"):return
			if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.ledger.bindings.size()==2,"owner reconnected again"):return
			if not await until(func():return game.session.roster.size()==1,"owner completed"):return
			print("PORTABLE_HOST_BOUNDARY PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		if host_loss_case:
			if not await until(func():return game.computers.stations[laptop].power.usb.drive.entries.get("note.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()=="updated" and not game.computers.usb_writes.has(laptop),"acknowledged write"):return
			var device=game.computers.stations[laptop].power
			if prepared_case:
				await create_timer(5.0).timeout
				if committed_case:
					var ledger=game.electronics_trade.authority.ledger
					var next: Dictionary=ledger.state.duplicate(true)
					var account: Dictionary=next.accounts[device.usb.owner]
					if not account.has("usb_write_commits"):account.usb_write_commits={}
					account.usb_write_commits[token]={"id":str(device.usb.id),"capacity":int(device.usb.capacity_mb)}
					if not ledger.persist(next):fail("Could not save committed write fixture");return
			var original: Dictionary=device.usb.drive.entries.duplicate(true)
			var workspace: Dictionary=game.computers.public_workspaces[laptop].duplicate(true)
			# Interrupt after host-side staging but before the owner is asked to
			# replace the local archive. The connection itself closes normally.
			device.usb.drive.write_file("note.txt","unacknowledged".to_utf8_buffer())
			var session: Dictionary=game.computers.sessions[owner_peer]
			game.computers.usb_writes[laptop]={"token":"interrupted-fixture","owner_peer":owner_peer,"actor":owner_peer,"lease":session.lease,"entries":original,"workspace":workspace,"started":Time.get_ticks_msec()}
			game.session.leave();await create_timer(2.0).timeout
			if game.session.host_game("Portable host",port)!=OK:fail("Host restart failed");return
			if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.ledger.bindings.size()==2,"owner reconnected after host loss"):return
			if game.portable_laptops.placed.has(laptop):fail("Laptop remained deployed after host loss");return
			if not await until(func():return game.session.roster.size()==1,"owner finished recovery"):return
			print("PORTABLE_HOST_LOSS PASS")
			game.session.leave();game.queue_free();await process_frame;quit();return
		if not await until(func():return not world.placed.has(laptop),"pickup or disconnect cleanup"):return
		if not await until(func():return world.placed.has(laptop),"laptop replaced"):return
		if not await until(func():return game.computers.stations.has(laptop) and not game.computers.stations[laptop].power.usb.is_empty(),"USB reconnected"):return
		if not await until(func():return not world.placed.has(laptop),"disconnect cleanup"):return
		if not await until(func():return game.session.roster.size()==2,"client reconnected"):return
		if world.placed.has(laptop):fail("Laptop duplicated after reconnect");return
		if not await until(func():return game.session.roster.size()==1,"client completed recovery"):return
		print("PORTABLE_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Portable student",port)!=OK:fail("Join failed");return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound,"inventory bound"):return
		if purchase_case:
			profile.buy_portable_laptop("basic")
			if not await until(func():return not profile.data.dorm.get("portable_laptops",{}).is_empty(),"purchase confirmed"):return
			laptop=str(profile.data.dorm.portable_laptops.keys()[0])
			if not profile.data.get("laptop_purchase_pending",{}).is_empty():fail("Pending purchase did not clear");return
		var pos: Vector3=game.computers.stations["commons_r0_c0"].anchor
		game.player.global_position=pos
		if not await until(func():game.session.send_pose({"position":pos});return game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(pos)<.6,"position"):return
		await physics_frame
		var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pos+Vector3.UP*2,pos-Vector3.UP*3,5))
		if hit.is_empty() or hit.normal.y<.9:fail("No placement surface");return
		game.portable_laptops._place_request.rpc_id(1,laptop,hit.position,0.0)
		if not await until(func():return game.portable_laptops.placed.has(laptop),"replicated placement"):return
		game.hotbar._sync_dorm_items()
		for i in game.hotbar.slots.size():
			if game.hotbar.slots[i].get("id","")==usb:game.hotbar.active=i
		game.computers.request({"op":"usb_port","station":laptop})
		if not await until(func():return profile.data.dorm.usb_drives.get(usb,{}).get("location","")=="connected","USB connected"):return
		game.computers.request({"op":"power","station":laptop})
		game.computers.request({"op":"enter","station":laptop})
		if not await until(func():return game.computers.local_snapshot.get("station","")==laptop,"desktop"):return
		var s: Dictionary=game.computers.local_snapshot
		game.computers.request({"op":"save","lease":s.lease,"revision":s.revision,"path":"note.txt","text":"updated","version":1})
		if not await until(func():var a: Dictionary=Archive.load(game.school.local_identity,usb,8);return not a.has("error") and a.drive.entries.get("note.txt",{}).get("data",PackedByteArray()).get_string_from_utf8()=="updated","USB save"):return
		if production_boundary:
			if not await until(func():return int(game.computers.local_snapshot.get("revision",0))>int(s.revision),"first write acknowledged"):return
			await create_timer(1.0).timeout
			if production_prepare:game.computers.usb_write_prepared.connect(func(_station,_token):game.session.leave(),CONNECT_ONE_SHOT)
			var next: Dictionary=game.computers.local_snapshot
			game.computers.request({"op":"save","lease":next.lease,"revision":next.revision,"path":"note.txt","text":"boundary","version":2})
			if not await until(func():return not game.session.online,"boundary disconnect"):return
			var before_reconnect: Dictionary=Archive.load(game.school.local_identity,usb,8)
			if before_reconnect.has("error") or before_reconnect.drive.entries["note.txt"].data.get_string_from_utf8()!="updated":fail("Prepared write replaced acknowledged archive");return
			await create_timer(3.0).timeout
			if game.session.join_game("127.0.0.1","Portable student",port)!=OK:fail("Reconnect failed");return
			if not await until(func():return game.electronics_trade.authority.bound and profile.data.dorm.usb_drives.get(usb,{}).get("location","")=="lost" and profile.data.get("usb_write_pending",{}).is_empty(),"boundary recovered"):return
			var recovered: Dictionary=Archive.load(game.school.local_identity,usb,8)
			var expected: String="boundary" if production_commit else "updated"
			if recovered.has("error") or recovered.drive.entries["note.txt"].data.get_string_from_utf8()!=expected or profile.data.dorm.portable_laptops.size()!=1 or profile.data.dorm.usb_drives.size()!=1:fail("Boundary recovery lost or duplicated data");return
			game.session.leave();await create_timer(2.0).timeout
			if game.session.join_game("127.0.0.1","Portable student",port)!=OK:fail("Second reconnect failed");return
			if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound,"second recovery bind"):return
			recovered=Archive.load(game.school.local_identity,usb,8)
			if recovered.has("error") or recovered.drive.entries["note.txt"].data.get_string_from_utf8()!=expected or not profile.data.get("usb_write_pending",{}).is_empty():fail("Repeated recovery changed data");return
			await create_timer(1.0).timeout
			print("PORTABLE_CLIENT_BOUNDARY PASS")
			await create_timer(.5).timeout
			game.session.leave();game.queue_free();await process_frame;quit();return
		if host_loss_case:
			if prepared_case:
				var staged: Dictionary=Archive.load(game.school.local_identity,usb,8)
				staged.drive.write_file("note.txt","prepared".to_utf8_buffer())
				if Archive.save(game.school.local_identity,token,"USB drive",8,staged.drive)!=OK:fail("Could not stage write");return
				profile.data.usb_write_pending={token:{"id":usb,"capacity":8,"host":game.electronics_trade.authority.bound_host}}
				var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
				var saved_marker: Error=profile.save();profile.authority_submit=callback
				if saved_marker!=OK:fail("Could not save write marker");return
			if not await until(func():return not game.session.online,"host disconnected"):return
			var preserved: Dictionary=Archive.load(game.school.local_identity,usb,8)
			if preserved.has("error") or preserved.drive.entries["note.txt"].data.get_string_from_utf8()!="updated":fail("Interrupted write damaged acknowledged archive");return
			await create_timer(3.0).timeout
			if game.session.join_game("127.0.0.1","Portable student",port)!=OK:fail("Reconnect failed");return
			if not await until(func():return game.electronics_trade.authority.bound and profile.data.dorm.usb_drives.get(usb,{}).get("location","")=="lost","host-loss recovery"):return
			if profile.data.dorm.portable_laptops.get(laptop,{}).get("location","")!="hotbar" or profile.data.dorm.portable_laptops.size()!=1 or profile.data.dorm.usb_drives.size()!=1:fail("Host-loss inventory missing or duplicated");return
			preserved=Archive.load(game.school.local_identity,usb,8)
			var expected: String="prepared" if committed_case else "updated"
			if preserved.has("error") or preserved.drive.entries["note.txt"].data.get_string_from_utf8()!=expected or not profile.data.get("usb_write_pending",{}).is_empty():fail("Recovered archive changed or marker remained");return
			if committed_case:
				game.computers._apply_committed_usb_write(laptop,token)
				preserved=Archive.load(game.school.local_identity,usb,8)
				if preserved.has("error") or preserved.drive.entries["note.txt"].data.get_string_from_utf8()!=expected:fail("Repeated confirmation changed archive");return
			print("PORTABLE_CLIENT_HOST_LOSS PASS")
			await create_timer(.5).timeout
			game.session.leave();game.queue_free();await process_frame;quit();return
		game.computers.request({"op":"power","station":laptop})
		game.computers.request({"op":"usb_port","station":laptop})
		if not await until(func():return profile.data.dorm.usb_drives.get(usb,{}).get("location","")=="hotbar","USB removed"):return
		game.portable_laptops._change_request.rpc_id(1,laptop,"pickup")
		if not await until(func():return not game.portable_laptops.placed.has(laptop),"pickup replicated"):return
		await create_timer(.5).timeout
		game.portable_laptops._place_request.rpc_id(1,laptop,hit.position,0.0)
		if not await until(func():return game.portable_laptops.placed.has(laptop),"second placement"):return
		game.hotbar._sync_dorm_items()
		for i in game.hotbar.slots.size():
			if game.hotbar.slots[i].get("id","")==usb:game.hotbar.active=i
		game.computers.request({"op":"usb_port","station":laptop})
		if not await until(func():return profile.data.dorm.usb_drives.get(usb,{}).get("location","")=="connected","USB reconnected"):return
		await create_timer(1.0).timeout
		game.session.leave();await create_timer(2.0).timeout
		if game.session.join_game("127.0.0.1","Portable student",port)!=OK:fail("Reconnect failed");return
		if not await until(func():return game.electronics_trade.authority.bound and profile.data.dorm.usb_drives.get(usb,{}).get("location","")=="lost","USB recovery"):return
		if profile.data.dorm.portable_laptops.get(laptop,{}).get("location","")!="hotbar":fail("Laptop ownership lost");return
		var saved: Dictionary=Archive.load(game.school.local_identity,usb,8)
		if saved.has("error") or saved.drive.entries["note.txt"].data.get_string_from_utf8()!="updated":fail("USB data lost");return
		print("PORTABLE_CLIENT PASS")
	await create_timer(.5).timeout
	game.session.leave();game.queue_free();await process_frame;quit()
