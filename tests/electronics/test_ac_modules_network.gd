extends SceneTree
const PORT := 26316
const FIXTURE := preload("res://scripts/lab_challenges/scenario_catalog.gd")
var game
var role: String
var deadline: int
var notice := ""

func _initialize() -> void:call_deferred("run")

func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.07).timeout
	push_error("AC MODULES TIMEOUT "+label+" "+notice)
	quit(1)
	return false

func state(index: int) -> Dictionary:
	return game.session.labs[index].snapshot() if role=="host" else game.station_snapshots[index]

func install(index: int,leads: Array,switches: Dictionary) -> bool:
	var lab=game.session.labs[index]
	var plan := {"frequency":60.0,"level":.5,"dyn_load":0.0,"switches":switches,"leads":leads}
	var error: String=FIXTURE.setup_error(lab,plan)
	if not error.is_empty():push_error(error);quit(1);return false
	FIXTURE.install(lab,plan)
	lab.mode="Free Laboratory"
	return true

func action(index: int,request: Dictionary,control: String) -> bool:
	var lab=game.session.labs[index]
	var target: Vector3=lab.positions[control]
	target=Vector3(target.x,0,target.z+.5)
	if not await until(func():
		game.player.global_position=target
		game.session.send_pose({"position":target})
		var pose: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
		return pose.get("position",Vector3.INF).distance_to(target)<.5
	,"reach "+control):return false
	var rev: int=state(index).revision
	request["station"]=index
	game.session.request(request)
	return await until(func():return state(index).revision>rev,str(request))

func transformer_ok() -> bool:
	var current := state(1)
	var r: Dictionary=current.readings
	return current.powered and current.level>.54 and r.fault=="" and absf(r.daq_v[0].length()-66.0)<.08 and absf(r.daq_i[0].length()-.22)<.002 and absf((r.voltages.TX_5-r.voltages.TX_9).length()-33.0)<.05

func motor_ok() -> bool:
	var current := state(2)
	var r: Dictionary=current.readings
	return current.powered and current.dyn_measure and current.igbt_damping and current.dyn_load>.19 and r.fault=="" and r.get("motor",{}).get("balanced",false) and absf(r.motor_rpm)>1200.0 and absf(r.dynamo_voltage-120.)<.01 and absf(r.dynamo_torque-.24)<.001

func run() -> void:
	role=OS.get_cmdline_user_args()[0]
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	deadline=Time.get_ticks_msec()+47000
	game.session.message_received.connect(func(message):notice=message)
	if role=="host":
		if game.session.host_game("Host",PORT)!=OK:quit(1);return
		game.capture()
		var switches: Dictionary=game.session.labs[1].switches.duplicate(true)
		switches.R[2]=true
		if not install(1,[["PV_A","TX_1"],["PV_N","TX_2"],["TX_5","DAQ_I0_4"],["DAQ_I0_N","R0_P"],["TX_6","R0_N"],["DAQ_E0_P","R0_P"],["DAQ_E0_N","R0_N"]],switches):return
		if not install(2,[["P_A","M1"],["P_B","M2"],["P_C","M3"],["M4","P_N"],["M5","P_N"],["M6","P_N"],["P_A","DYN_0"],["P_N","DYN_1"]],game.session.labs[2].switches):return
		game.session.broadcast()
	else:
		if game.session.join_game("127.0.0.1","Operator",PORT)!=OK:quit(1);return
		if not await until(func():return game.station_snapshots.size()==3 and state(1).cables.size()==7 and state(2).cables.size()==8,"independent rack wiring"):return
		if not await action(1,{"op":"voltage","delta":.05},"variable"):return
		if not await action(1,{"op":"power"},"power"):return
		if not await action(2,{"op":"dyn_load","delta":.1},"dyn_load"):return
		await create_timer(.08).timeout
		if not await action(2,{"op":"dyn_load","delta":.1},"dyn_load"):return
		if not await action(2,{"op":"dyn_measure","pressed":true},"dyn_measure"):return
		if not await action(2,{"op":"igbt_damping"},"igbt_damping"):return
		if not await action(2,{"op":"power"},"power"):return
	if not await until(func():return transformer_ok() and motor_ok() and not state(0).powered,"transformer, DAQ, motor and separate racks"):return
	print("PASS ",role," transformer tap, DAQ voltage/current, balanced motor RPM, dynamometer and IGBT damping control")
	if role=="client":
		await create_timer(1).timeout
		game.session.leave()
	else:
		if not await until(func():return game.session.roster.size()==1 and not state(2).dyn_measure and state(2).powered,"disconnect released held measurement without shutting down the rack"):return
		print("PASS host released dynamometer measurement on disconnect")
	quit()
