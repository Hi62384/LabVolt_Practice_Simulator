extends SceneTree
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var game: Node
var deadline:=0
var profiles:={}
var results:=[]
var events:=[]

func _initialize() -> void:call_deferred("run")

func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("LIFT NETWORK TIMEOUT " + label);quit(1);return false

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
		var rules=controller.host
		rules.context=func(peer):
			return {"identity":str(peer),"position":Vector3(-.5,0,31.5) if peer==1 else Vector3(-5,0,32.5),"room_id":"gym","allowed":true,"grounded":true}
		rules.load_profile=func(id):
			if not profiles.has(id):profiles[id]=Rules.empty_profile()
			return profiles[id].duplicate(true)
		rules.commit_profile=func(id,_delta,p):profiles[id]=p.duplicate(true);return true
		controller.interested_peers=func(_room):return game.session.roster.keys()
		print("LIFT_HOST_READY")
		if not await until(func():return game.session.roster.size()==2,"client connected"):return
		var start: Dictionary=rules.act(1,{"op":"start","station":"gym/pullup","exercise":"pullup","weight":0,"sequence":1})
		if not start.ok:push_error("Host could not use pull-up station: "+str(start));quit(1);return
		if not await until(func():return events.any(func(e):return e.peer!=1 and e.event.get("activity","")=="exercise" and int(e.event.get("reps",0))>=1),"remote repetition broadcast"):return
		if not events.any(func(e):return e.peer!=1 and e.event.get("activity","")=="exercise" and float(e.event.get("phase",0))>.05 and float(e.event.get("phase",0))<.95):
			push_error("Live movement preview was not broadcast");quit(1);return
		if not rules.active.has(1) or rules.active[1].exercise!="pullup":push_error("Concurrent exercise was interrupted");quit(1);return
		var remote:=0
		for peer in game.session.roster:
			if int(peer)!=1:remote=int(peer)
		if profiles.get(str(remote),{}).get("gym",{}).get("muscles",{}).is_empty():push_error("Remote repetition did not persist fatigue");quit(1);return
		if not await until(func():return events.any(func(e):return e.peer==remote and e.event.get("activity","")=="idle"),"remote finish broadcast"):return
		print("LIFT_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:push_error("Join failed");quit(1);return
		if not await until(func():return game.session.roster.size()==2,"connected"):return
		var panel: Node=game.campus_services.facility_panel
		panel.open_for("gym/pushup","pushup")
		if not await until(func():return panel.state.has("profile"),"profile refresh"):return
		var start_button: Button
		for button in panel.find_children("*","Button",true,false):
			if button.text=="Bodyweight":start_button=button;break
		if start_button==null:push_error("Bodyweight action missing");quit(1);return
		start_button.pressed.emit()
		if not await until(func():return panel.state.get("active",{}).get("type","")=="exercise" and not panel.pending,"start acknowledged"):return
		controller.preview_motion(.5,0,0,int(panel.state.active.started))
		await create_timer(.2).timeout
		for half in 2:
			var controls=panel.body.find_children("*","HSlider",true,false)
			if controls.size()!=1:push_error("Effort control missing");quit(1);return
			var lift=controls[0].get_parent()
			lift.held=true
			for step in 120:
				lift.effort.value=minf(1.0,lift._target_effort()+.10)
				lift._process(.1)
				if panel.workout_reached:break
			lift.held=false
			if not panel.workout_reached:push_error("Controlled lift could not advance");quit(1);return
			if not await until(func():return is_instance_valid(panel.workout_step) and not panel.workout_step.disabled,"movement ready"):return
			panel.workout_step.pressed.emit()
			if not await until(func():return not panel.pending and int(panel.state.get("active",{}).get("phase",-1))==(1 if half==0 else 0),"movement acknowledged"):return
		if int(panel.state.active.reps)!=1:push_error("Client did not receive completed repetition");quit(1);return
		await create_timer(.2).timeout
		var finish: Button
		for button in panel.body.find_children("*","Button",true,false):
			if button.text=="Finish set":finish=button;break
		if finish==null or finish.disabled:push_error("Finish action unavailable");quit(1);return
		finish.pressed.emit()
		if not await until(func():return not panel.pending and panel.state.get("active",{}).is_empty(),"finish acknowledged"):return
		await create_timer(.5).timeout
		print("LIFT_CLIENT PASS")
	quit(0)
