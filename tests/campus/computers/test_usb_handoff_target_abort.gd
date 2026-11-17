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
	push_error("USB TARGET ABORT TIMEOUT: "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["host","client"] or not args[1].is_valid_int():quit(1);return
	var role:=str(args[0]);var port:=int(args[1])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var profile=game.electronics.profile;profile.open("target-abort-"+role)
	game.school.local_identity=profile.data.dorm.owner
	var id: String=""
	if role=="host":
		profile.data.dollars=1000;profile.buy_usb(8);id=str(profile.data.dorm.usb_drives.keys()[0])
		var drive=Drive.new(8*1024*1024);var bytes:=PackedByteArray();bytes.resize(4*1024*1024);drive.write_file("large.bin",bytes)
		if Archive.save(game.school.local_identity,id,"USB drive",8,drive)!=OK:quit(1);return
		profile.data.dorm.carry_items.erase("usb:"+id);profile.data.dorm.usb_drives[id].location="lost";profile.save()
	deadline=Time.get_ticks_msec()+60000
	if role=="host":
		if game.session.host_game("USB host",port)!=OK:quit(1);return
		print("USB_TARGET_ABORT_HOST_READY")
		if not await until(func():return game.session.roster.size()==2 and not game.discarded_items.drops.is_empty(),"join and lost item"):return
		var lost: Node=game.discarded_items;var drop_id: int=int(lost.drops.keys()[0]);var point: Vector3=lost.drops[drop_id].position
		var target_peer:=0
		if not await until(func():
			for peer in game.session.roster:
				if int(peer)!=1 and game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(point)<.6:return true
			return false
		,"recipient position"):return
		for peer in game.session.roster:
			if int(peer)!=1:target_peer=int(peer)
		lost.usb_handoffs.start(target_peer,drop_id,1)
		if not await until(func():return not game.discarded_items.usb_handoffs.pending.is_empty(),"handoff started"):return
		if not await until(func():return game.session.roster.size()==1 and game.discarded_items.usb_handoffs.pending.is_empty(),"recipient left and handoff aborted"):return
		if profile.data.dorm.usb_drives[id].location!="lost":push_error("Original USB was not restored");quit(1);return
		var original: Dictionary=Archive.load(game.school.local_identity,id,8)
		if original.has("error") or original.drive.entries["large.bin"].data.size()!=4*1024*1024:push_error("Original archive lost");quit(1);return
		print("USB_TARGET_ABORT_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","USB recipient",port)!=OK:quit(1);return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound and not game.discarded_items.drops.is_empty(),"lost item available"):return
		var lost: Node=game.discarded_items;var drop_id: int=int(lost.drops.keys()[0]);var point: Vector3=lost.drops[drop_id].position
		game.player.global_position=point
		if not await until(func():
			game.session.send_pose({"position":point})
			return game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(point)<.6
		,"position accepted"):return
		if not await until(func():return not lost.usb_handoffs.incoming.is_empty(),"recipient download started"):return
		print("USB_TARGET_ABORT_CLIENT PASS")
	game.session.leave();game.queue_free();await process_frame;quit()
