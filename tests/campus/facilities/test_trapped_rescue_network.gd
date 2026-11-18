extends SceneTree
## Exercise a failed lift and a remote rescue through the real controller RPCs.
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var game: Node
var deadline:=0
var profiles:={}
var events:=[]
var results:=[]

func _initialize() -> void:call_deferred("run")

func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("RESCUE NETWORK TIMEOUT: "+label);quit(1);return false

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or str(args[0]) not in ["host","client"] or not str(args[1]).is_valid_int() or int(args[1])<1 or int(args[1])>65535:
		push_error("Usage: test_trapped_rescue_network.gd -- host|client PORT")
		quit(1)
		return
	var role:=str(args[0]);var port:=int(args[1])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	deadline=Time.get_ticks_msec()+60000
	var controller: Node=game.campus_services.facilities.controller
	controller.room_event.connect(func(peer,event):events.append({"peer":peer,"event":event.duplicate(true)}))
	controller.owner_result.connect(func(result):results.append(result))
	if role=="host":
		if game.session.host_game("Host",port)!=OK:push_error("Host failed");quit(1);return
		game.front.entered()
		await process_frame
		# Use deterministic fixture profiles while the real host controller ticks.
		game.campus_services.set_process(false)
		var rules=controller.host
		rules.context=func(peer):
			var p: Vector3=Vector3(4,0,32.5) if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.INF)
			return {"identity":str(peer),"position":p,"room_id":"gym","allowed":true,"grounded":true}
		rules.load_profile=func(id):
			if not profiles.has(id):profiles[id]=Rules.empty_profile()
			return profiles[id].duplicate(true)
		rules.commit_profile=func(id,_d,p):profiles[id]=p.duplicate(true);return true
		rules.barbell_mass=func(_station):return 65.0
		controller.interested_peers=func(_room):return game.session.roster.keys()
		if not await until(func():return game.session.roster.size()==2,"client joined"):return
		var result: Dictionary=rules.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":1})
		if not result.ok:push_error("Start failed: "+str(result));quit(1);return
		for press in 30:
			if rules.active.get(1,{}).get("type","") != "exercise":
				break
			await _wait_real(.11)
			result = rules.act(1,{"op":"effort","sequence":int(profiles["1"].last_sequence)+1})
			if not result.ok and rules.active.get(1,{}).get("type","") != "trapped":
				push_error("Effort failed: "+str(result));quit(1);return
		await _wait_real(.18)
		if rules.active.get(1,{}).get("type","")!="trapped":push_error("Lift did not trap player");quit(1);return
		if game.health.people.get(1,{}).get("health",100.0) >= 100.0:
			await _wait_real(.24)
		if game.health.people.get(1,{}).get("health",100.0) >= 100.0:
			push_error("Trapped player did not take damage");quit(1);return
		if not await until(func():return not rules.active.has(1),"player rescued"):return
		if not await until(func():return game.session.roster.size()==1,"client left"):return
		print("RESCUE_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:push_error("Join failed");quit(1);return
		game.front.entered()
		if not await until(func():
			var p:=Vector3(4,0,32.5);game.player.global_position=p;game.session.send_pose({"position":p})
			return game.session.roster.size()==2 and game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(p)<.6
		,"approach station"):return
		if not await until(func():return events.any(func(e):return e.peer==1 and e.event.get("activity","")=="trapped"),"trapped event"):return
		events.clear()
		var bar: StaticBody3D = game.gym_barbells.rescue_targets["gym/benchpress"]
		if not await until(func():return bar.collision_layer==4,"rescue target follows trapped bar"):return
		while not events.any(func(e):return e.peer==1 and e.event.get("activity","")=="idle") and Time.get_ticks_msec()<deadline:
			game.current_target = bar
			game.activate(true)
			await _wait_real(1.1)
		if not events.any(func(e):return e.peer==1 and e.event.get("activity","")=="idle"):
			push_error("Rescue did not release player");quit(1);return
		if not results.any(func(r):return r.get("ok",false)):
			push_error("No rescue request was accepted");quit(1);return
		print("RESCUE_CLIENT PASS")
	game.session.leave()
	game.queue_free()
	await process_frame
	quit(0)


func _wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec()+ceili(seconds*1000.0)
	while Time.get_ticks_msec()<end:
		await process_frame
