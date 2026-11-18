extends SceneTree
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var game: Node
var deadline:=0
var profiles:={}
var events:=[]
var abort_on_disconnect:=false
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		if abort_on_disconnect and game.session.roster.size()<2:push_error("Client disconnected before "+label);quit(1);return false
		await create_timer(.05).timeout
	push_error("CARRIED BENCH NETWORK TIMEOUT "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args();var role:=str(args[0]);var port:=int(args[1])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	deadline=Time.get_ticks_msec()+60000
	var controller: Node=game.campus_services.facilities.controller
	var gear: Node=game.gym_barbells
	controller.room_event.connect(func(peer,event):events.append({"peer":peer,"event":event.duplicate(true)}))
	if role=="host":
		if game.session.host_game("Host",port)!=OK:push_error("Host failed");quit(1);return
		var rules=controller.host
		rules.context=func(peer):return {"identity":str(peer),"position":rules.anchors["gym/benchpress"].position,"room_id":"gym","allowed":true,"grounded":true}
		rules.load_profile=func(id):
			if not profiles.has(id):profiles[id]=Rules.empty_profile()
			return profiles[id].duplicate(true)
		rules.commit_profile=func(id,_delta,p):profiles[id]=p.duplicate(true);return true
		controller.interested_peers=func(_room):return game.session.roster.keys()
		print("CARRIED_BENCH_HOST_READY")
		if not await until(func():return game.session.roster.size()==2,"client joined"):return
		abort_on_disconnect=true
		var peer:=0
		for id in game.session.roster:
			if int(id)!=1:peer=int(id)
		if not await until(func():return rules.active.get(peer,{}).get("equipment","")=="barbell" and gear.bench_models.has(peer),"carried bar exercise and visible model"):return
		if not is_equal_approx(float(rules.active[peer].weight),gear.loaded_mass("gym/benchpress")) or float(rules.active[peer].weight)<=20.0:push_error("Host used wrong loaded bar mass");quit(1);return
		if gear.bench_models[peer].visual.get_child_count()<2:push_error("Loaded plate is missing from the bench bar");quit(1);return
		events.clear()
		if not await until(func():return events.any(func(e):return e.peer==peer and e.event.get("activity","")=="idle"),"set stopped"):return
		if not await until(func():return not gear.bench_models.has(peer),"bench model removed"):return
		abort_on_disconnect=false
		if not await until(func():return not game.session.roster.has(peer),"client disconnected"):return
		print("CARRIED_BENCH_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:push_error("Join failed");quit(1);return
		var peer: int=game.multiplayer.get_unique_id()
		if not await until(func():
			var p: Vector3=gear.PLATE_RACK;game.player.global_position=p;game.session.send_pose({"position":p})
			return game.session.roster.size()==2 and game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(p)<.6
		,"approach plate rack"):return
		var retry:={"at":0}
		if not await until(func():
			if Time.get_ticks_msec()>=int(retry.at):retry.at=Time.get_ticks_msec()+350;gear.request_plate("pickup",0)
			return gear.held_plate(peer)==0
		,"pick up plate"):return
		if not await until(func():
			var p:=Vector3(4,0,30.2);game.player.global_position=p;game.session.send_pose({"position":p})
			return game.session.roster.size()==2 and game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(p)<.6
		,"approach bench rack"):return
		retry.at=0
		if not await until(func():
			if Time.get_ticks_msec()>=int(retry.at):retry.at=Time.get_ticks_msec()+350;gear.request_plate("attach",0,"gym/benchpress",-1)
			return gear.plates[0].station=="gym/benchpress"
		,"load bar"):return
		retry.at=0
		if not await until(func():
			if Time.get_ticks_msec()>=int(retry.at):retry.at=Time.get_ticks_msec()+350;gear.request("pickup_bar","gym/benchpress",0,0)
			return gear.held_bar(peer)=="gym/benchpress"
		,"pick up bar"):return
		var panel: Node=game.campus_services.facility_panel
		var target: Node
		for candidate in game.find_children("*","StaticBody3D",true,false):
			if candidate.get_meta("role","")=="gym_equipment" and candidate.get_meta("station","")=="gym/benchpress":target=candidate;break
		if target==null:push_error("Bench interaction target missing");quit(1);return
		game.current_target=target;game.player.enabled=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true
		var aimed: Dictionary=game.campus_services._aimed_facility()
		# The headless display backend cannot capture the OS mouse. Exercise the
		# same bench hit-test and event routing used after that outer guard.
		var routed: bool=game.campus_services._route_bench_equipment(click)
		if not routed or panel.station_kind!="bench_barbell":
			push_error("Right-click bench failed: mouse=%s enabled=%s formal=%s aimed=%s held=%s position=%s" % [Input.mouse_mode,game.player.enabled,game.school.formal_active(),aimed,gear.held_bar(peer),game.player.global_position]);quit(1);return
		if not await until(func():return panel.state.has("profile"),"profile ready"):return
		var start: Button
		for button in panel.find_children("*","Button",true,false):
			if button.text=="Start set":start=button;break
		if start==null or start.disabled:push_error("Carried bar bench action missing");quit(1);return
		start.pressed.emit()
		if not await until(func():return panel.state.get("active",{}).get("equipment","")=="barbell" and not panel.pending,"exercise acknowledged"):return
		await create_timer(.8).timeout
		var cancel := InputEventKey.new()
		cancel.keycode = KEY_X
		cancel.pressed = true
		if not panel.handle_workout_input(cancel):
			push_error("Workout HUD did not handle ending the set");quit(1);return
		if not await until(func():return not panel.pending and panel.state.get("active",{}).is_empty(),"exercise stopped"):return
		await create_timer(.5).timeout
		print("CARRIED_BENCH_CLIENT PASS")
	if role=="host":
		controller.host.context=Callable();controller.host.load_profile=Callable();controller.host.commit_profile=Callable()
		controller.interested_peers=Callable()
	# Close the transport while its RPC targets still exist, as normal game
	# navigation does, before destroying the scene.
	game.session.leave()
	game.queue_free()
	await process_frame
	quit(0)
