extends SceneTree
var game: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("PUBLIC NETWORK TIMEOUT: "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["host","client"] or not args[1].is_valid_int():
		push_error("Usage: test_public_network.gd -- host|client PORT");quit(1);return
	var role:=str(args[0]);var port:=int(args[1]);var id:="commons_r0_c0"
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	deadline=Time.get_ticks_msec()+60000
	var service: Node=game.computers
	var point: Vector3=service.stations[id].anchor
	if role=="host":
		if game.session.host_game("Host",port)!=OK:push_error("Host failed");quit(1);return
		print("PUBLIC_HOST_READY")
		if not await until(func():return game.session.roster.size()==2,"client joined"):return
		var second:="commons_r0_c1"
		var second_point: Vector3=service.stations[second].anchor
		game.school.local_identity="network-host"
		game.player.global_position=second_point;game.session.poses[1]={"position":second_point}
		service.request({"op":"power","station":second})
		service.request({"op":"enter","station":second})
		if not service.local_snapshot.get("public_device",false):push_error("Host workstation did not open");quit(1);return
		service.request({"op":"save","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"path":"host.txt","text":"host","version":0})
		if not service.local_snapshot.get("files",{}).has("host.txt"):push_error("Host save failed");quit(1);return
		if not await until(func():return service.public_workspaces.get(id,{}).get("files",{}).has("network.txt"),"remote saved file"):return
		if service.public_workspaces[id].files.has("host.txt") or service.public_workspaces[second].files.has("network.txt"):
			push_error("Concurrent workstations shared files");quit(1);return
		if not await until(func():return game.session.roster.size()==1,"client left"):return
		if not service.stations[id].power.powered or not service.public_workspaces[id].files.has("network.txt"):
			push_error("Power or files changed when user left");quit(1);return
		game.session.poses[1]={"position":point}
		service.request({"op":"power","station":id})
		if service.public_workspaces.has(id) or service.stations[id].power.powered:
			push_error("Host power off did not clear the workspace");quit(1);return
		print("PUBLIC_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:push_error("Join failed");quit(1);return
		if not await until(func():return game.session.roster.size()==2,"connected"):return
		game.school.local_identity="network-student"
		game.player.global_position=point
		if not await until(func():
			game.session.send_pose({"position":point})
			return game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(point)<.6
		,"position accepted"):return
		service.request({"op":"power","station":id})
		await create_timer(.3).timeout
		service.request({"op":"enter","station":id})
		if not await until(func():return service.local_snapshot.get("public_device",false),"desktop opened"):return
		service.request({"op":"save","lease":service.local_snapshot.lease,"revision":service.local_snapshot.revision,"path":"network.txt","text":"hello","version":0})
		if not await until(func():return service.local_snapshot.get("files",{}).has("network.txt"),"save acknowledged"):return
		print("PUBLIC_CLIENT PASS")
	game.session.leave();game.queue_free();await process_frame;quit()
