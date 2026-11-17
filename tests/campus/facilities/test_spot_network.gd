extends SceneTree
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var game
var deadline:=0
var profiles:={}
var results:=[]
var events:=[]
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("SPOT NETWORK TIMEOUT "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args();var role:=str(args[0]);var port:=int(args[1])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	deadline=Time.get_ticks_msec()+60000
	var controller: Node=game.campus_services.facilities.controller
	controller.owner_result.connect(func(value):results.append(value))
	controller.room_event.connect(func(peer,event):events.append({"peer":peer,"event":event.duplicate(true)}))
	if role=="host":
		if game.session.host_game("Host",port)!=OK:push_error("Host failed");quit(1);return
		await process_frame
		var rules=controller.host
		rules.context=func(peer):
			var position: Vector3=Vector3(4,0,32.5) if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.INF)
			return {"identity":str(peer),"position":position,"room_id":"gym","allowed":true,"grounded":true}
		rules.load_profile=func(id):
			if not profiles.has(id):profiles[id]=Rules.empty_profile()
			return profiles[id].duplicate(true)
		rules.commit_profile=func(id,_d,p):profiles[id]=p.duplicate(true);return true
		rules.barbell_mass=func(_station):return 65.0
		controller.interested_peers=func(_room):return game.session.roster.keys()
		print("SPOT_HOST_READY")
		if not await until(func():return not rules.spotters.is_empty(),"spotter reservation"):return
		var result: Dictionary=rules.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":1})
		if not result.ok:push_error("start: "+str(result));quit(1);return
		for i in 2:
			await create_timer(float(rules.active[1].half_ms)/1000.0+.1).timeout
			result=rules.act(1,{"op":"beat","sequence":int(profiles["1"].last_sequence)+1})
			if not result.ok:push_error("beat: "+str(result));quit(1);return
		if not result.get("spot_saved",false):push_error("spotter did not save lift");quit(1);return
		await create_timer(1.0).timeout
		print("SPOT_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:push_error("Join failed");quit(1);return
		if not await until(func():
			var p:=Vector3(4,0,32.5);game.player.global_position=p;game.session.send_pose({"position":p})
			return game.session.roster.size()==2 and game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(p)<.6
		,"approach station"):return
		controller.request({"op":"spot","station":"gym/benchpress","sequence":1})
		if not await until(func():return results.any(func(value):return value.get("ok",false) and value.get("state",{}).get("spotting","")=="gym/benchpress"),"spot acknowledged"):return
		if not await until(func():return events.any(func(value):return value.peer==game.multiplayer.get_unique_id() and value.event.get("activity","")=="spot_assist"),"assist broadcast"):return
		print("SPOT_CLIENT PASS")
	quit()
