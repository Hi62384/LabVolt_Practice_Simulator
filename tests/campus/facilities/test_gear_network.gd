extends SceneTree
var game
var deadline:=0
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("GEAR NETWORK TIMEOUT "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args();var role:=str(args[0]);var port:=int(args[1])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	deadline=Time.get_ticks_msec()+60000
	var gear: Node=game.gym_barbells
	if role=="host":
		if game.session.host_game("Host",port)!=OK:push_error("Host failed");quit(1);return
		print("GEAR_HOST_READY")
		if not await until(func():return gear.plates[1].station=="gym/benchpress" and gear.plates[1].where=="attached","remote loaded barbell"):return
		if not await until(func():return gear.plates[1].where=="rack" and gear.plates[1].station=="","remote returned barbell plate"):return
		if not await until(func():return gear.belts[0].where=="worn" and gear.plates[0].station=="belt/0","remote wore loaded belt"):return
		if not is_equal_approx(gear.belt_mass(0),gear.BELT_KG+gear.plates[0].lb*gear.LB_TO_KG):push_error("host load incorrect");quit(1);return
		if not await until(func():return gear.belts[0].where=="rack" and gear.plates[0].station=="belt/0","belt return"):return
		await create_timer(1.0).timeout
		print("GEAR_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:push_error("Join failed");quit(1);return
		if not await until(func():
			var p:=Vector3(gear.PLATE_RACK.x,0,gear.PLATE_RACK.z);game.player.global_position=p;game.session.send_pose({"position":p})
			return game.session.roster.size()==2 and game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(p)<.6
		,"approach rack"):return
		var peer: int=game.multiplayer.get_unique_id()
		gear.request_plate("pickup",1)
		if not await until(func():return gear.held_plate(peer)==1,"barbell plate pickup"):return
		var plate_attempt:={"at":0}
		if not await until(func():
			var p: Vector3=gear.POSITIONS["gym/benchpress"]
			game.player.global_position=p;game.session.send_pose({"position":p})
			if Time.get_ticks_msec()>=int(plate_attempt.at):
				plate_attempt.at=Time.get_ticks_msec()+350;gear.request_plate("attach",1,"gym/benchpress",-1)
			return gear.plates[1].station=="gym/benchpress"
		,"barbell attachment"):return
		await create_timer(.5).timeout
		gear.request_plate("detach",-1,"gym/benchpress",-1)
		if not await until(func():return gear.held_plate(peer)==1,"barbell detachment"):return
		plate_attempt.at=0
		if not await until(func():
			var p: Vector3=gear.PLATE_RACK
			game.player.global_position=p;game.session.send_pose({"position":p})
			if Time.get_ticks_msec()>=int(plate_attempt.at):
				plate_attempt.at=Time.get_ticks_msec()+350;gear.request_plate("return",1)
			return gear.plates[1].where=="rack"
		,"barbell plate return"):return
		gear.request_plate("pickup",0)
		if not await until(func():return gear.held_plate(peer)==0,"plate pickup"):return
		var next_attempt:={"at":0}
		if not await until(func():
			var p:=Vector3(gear.BELT_RACK.x,0,gear.BELT_RACK.z)
			game.player.global_position=p;game.session.send_pose({"position":p})
			if Time.get_ticks_msec()>=int(next_attempt.at):
				next_attempt.at=Time.get_ticks_msec()+350;gear.request_plate("belt_attach",0,"belt/0")
			return gear.plates[0].station=="belt/0"
		,"plate attachment"):return
		gear.request_belt("pickup",0)
		if not await until(func():return gear.held_belt(peer)==0,"belt pickup"):return
		gear.request_belt("wear",0)
		if not await until(func():return gear.worn_belt(peer)==0,"belt worn"):return
		await create_timer(1.0).timeout
		gear.request_belt("unwear",0)
		if not await until(func():return gear.held_belt(peer)==0,"belt removed"):return
		gear.request_belt("return",0)
		if not await until(func():return gear.belts[0].where=="rack" and gear.plates[0].station=="belt/0","belt returned"):return
		print("GEAR_CLIENT PASS")
	quit()
