extends SceneTree
const PORT := 26319
var game
var dorm
var role: String
var deadline: int
var marker := ""

func _initialize() -> void:call_deferred("run")

func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.08).timeout
	push_error("DORM NETWORK TIMEOUT "+label)
	quit(1)
	return false

func door(bay: String) -> Dictionary:
	for contract in dorm.hall.room_contracts:
		if contract.dorm_id==bay:return contract
	return {}

func walk_to(point: Vector3) -> bool:
	return await until(func():
		game.player.global_position=point
		game.session.send_pose({"position":point})
		var pose: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
		return pose.get("position",Vector3.INF).distance_to(point)<.3
	,"host-validated dorm approach "+str(point))

func change(op: String,value: Variant) -> bool:
	var revision: int=int(game.electronics.profile.data.dorm.revision)
	dorm.submit_intent("dorm-test-"+str(revision),{"op":op,"value":value,"revision":revision})
	return await until(func():return int(game.electronics.profile.data.dorm.revision)>revision,"saved "+op)

func run() -> void:
	role=OS.get_cmdline_user_args()[0]
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.characters.selected="dorm-network-"+role
	game.school._identity_changed()
	game.electronics.profile.open(game.characters.selected)
	dorm=game.dorm_interactions
	deadline=Time.get_ticks_msec()+55000
	game.session.chat_received.connect(func(_peer,_sender,message):marker=message)
	if role=="host":
		if game.session.host_game("Host",PORT)!=OK:quit(1);return
	else:
		if game.session.join_game("127.0.0.1","Visitor",PORT)!=OK:quit(1);return
	game.capture()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	if not await until(func():return dorm.snapshot.get("identities",{}).size()==2,"two authenticated dorm assignments"):return
	var own_id: int=game.multiplayer.get_unique_id()
	var guest_id: int=dorm.snapshot.identities.keys().filter(func(peer):return peer!=1)[0]
	var guest: String=dorm.authenticated_identity(guest_id)
	var host_room: String=dorm.room_for_peer(1)
	var guest_room: String=dorm.room_for_peer(guest_id)
	if host_room==guest_room or host_room.is_empty() or guest_room.is_empty():push_error("FAIL shared dorm identity");quit(1);return
	var host_bay: String=dorm._bay_for(host_room)
	var guest_bay: String=dorm._bay_for(guest_room)
	if role=="host":
		if not await until(func():return marker=="PRIVATE_DENIED","private dorm denied visitor"):return
		if dorm.open_doors.has(host_bay) or not dorm.open_doors.has(guest_bay):push_error("FAIL wrong door opened");quit(1);return
		if not await change("invite",[guest]):return
		if not await change("policy","Invited"):return
		print("DORM host invitation saved")
		if not await until(func():return dorm.occupants.get(guest_id,"")==host_room,"invited visitor entry"):return
		if not await change("policy","Private"):return
		var host_door := door(host_bay)
		if not await until(func():
			var pose: Dictionary=game.session.poses.get(guest_id,{})
			return not dorm.occupants.has(guest_id) and pose.get("position",Vector3.INF).distance_to(host_door.door)<1.1
		,"revocation moved visitor out on the host"):return
		print("PASS host separate dorms, private door denial, invited access and revocation")
	else:
		var guest_door := door(guest_bay)
		if not await walk_to(guest_door.door+Vector3(1.3 if guest_door.side=="west" else -1.3,0,0)):return
		dorm.interact(dorm.hall.door_targets[guest_bay])
		if not await until(func():return dorm.snapshot.open_doors.has(guest_bay),"own door opened"):return
		var host_door := door(host_bay)
		if not await walk_to(host_door.door+Vector3(1.3 if host_door.side=="west" else -1.3,0,0)):return
		dorm.interact(dorm.hall.door_targets[host_bay])
		await create_timer(.6).timeout
		if dorm.snapshot.open_doors.has(host_bay) or dorm.can_enter(guest,host_room):push_error("FAIL private dorm access");quit(1);return
		print("DORM client private door rejected")
		game.session.chat("PRIVATE_DENIED")
		if not await until(func():return dorm.can_enter(guest,host_room),"invitation replicated"):return
		print("DORM client invitation received")
		dorm.interact(dorm.hall.door_targets[host_bay])
		if not await until(func():return dorm.snapshot.open_doors.has(host_bay),"invited door opened"):return
		print("DORM client invited door opened")
		if not await walk_to(host_door.entry_anchor):return
		print("DORM client reached interior")
		var result: Dictionary=dorm.storage_transfer(guest,host_room,"foreign-cabinet","r220",1,true)
		if result.get("ok",false) or result.get("error","")!="Owner required":push_error("FAIL guest cabinet access");quit(1);return
		if not await until(func():return not dorm.can_enter(guest,host_room) and game.player.global_position.distance_to(host_door.door)<1.1,"revocation ejected visitor"):return
		if not await walk_to(game.player.global_position):return
		print("PASS client own door, invited entry, owner-only cabinet and revocation")
	await create_timer(2).timeout
	quit()

