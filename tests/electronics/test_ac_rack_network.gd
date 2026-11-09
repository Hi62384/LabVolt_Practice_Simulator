extends SceneTree
const PORT := 26311
const BENCH := 0
var game
var lab
var role: String
var deadline: int
var notice := ""

func _initialize() -> void: call_deferred("run")

func until(condition: Callable, label: String) -> bool:
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await create_timer(.06).timeout
	push_error("AC NETWORK TIMEOUT "+label+" "+notice)
	quit(1)
	return false

func state() -> Dictionary:
	return lab.snapshot() if role=="host" else game.station_snapshots[BENCH]

func approach(position: Vector3, tolerance := .25) -> bool:
	return await until(func():
		game.player.global_position=position
		game.session.send_pose({"position":position})
		if game.session.roster.size()<2 or game.station_snapshots.size()<=BENCH:return false
		var own: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
		return own.get("position",Vector3.INF).distance_to(position)<tolerance
	,"authoritative approach to AC rack "+str(position))

func act(action: Dictionary) -> bool:
	action["station"]=BENCH
	var revision: int=state().revision
	notice=""
	game.session.request(action)
	var ok: bool=await until(func():return state().revision>revision,str(action))
	await create_timer(.06).timeout
	return ok

func wire(a: String,b: String) -> bool:
	if not await act({"op":"pickup","color":1}):return false
	if not await act({"op":"plug","port":a}):return false
	return await act({"op":"plug","port":b})

func metered(state_now: Dictionary) -> bool:
	var readings: Dictionary=state_now.readings
	return state_now.powered and state_now.switches.R[2] and state_now.switches.L[1] and state_now.switches.C[2] and state_now.frequency==55.0 and state_now.supply_meter==2 and readings.fault=="" and absf(readings.voltmeters[0]-120.0)<.05 and absf(readings.ammeters[0]-.4)<.08 and absf(readings.wattmeters[0]-48.0)<.15 and readings.bank_currents.L0>.1 and readings.bank_currents.C0>.3

func run() -> void:
	role=OS.get_cmdline_user_args()[0]
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	lab=game.session.labs[BENCH]
	deadline=Time.get_ticks_msec()+43000
	game.session.message_received.connect(func(message):notice=message;print("AC notice ",message))
	if role=="host":
		if game.session.host_game("AC host",PORT)!=OK:quit(1);return
		game.capture()
		if not await until(func():return metered(state()),"authoritative instrument readings"):return
		print("PASS host power, RLC, voltmeter, ammeter and wattmeter")
		if not await until(func():return game.session.roster.size()==3,"late observer joined"):return
		if not await until(func():return not state().powered and state().cables.size()==11,"client powered off and unplugged meter"):return
		print("PASS host received breaker and unplug after observer joined")
	elif role=="late":
		if game.session.join_game("127.0.0.1","AC observer",PORT)!=OK:quit(1);return
		if not await until(func():return game.station_snapshots.size()>BENCH and metered(state()) and state().cables.size()==12,"energized late join"):return
		print("PASS late observer received live readings and all leads")
		game.session.chat("AC_OBSERVED")
	else:
		var observed := [false]
		game.session.chat_received.connect(func(_peer,_sender,message):if message=="AC_OBSERVED":observed[0]=true)
		if game.session.join_game("127.0.0.1","AC operator",PORT)!=OK:quit(1);return
		if not await approach(lab.positions.storage):return
		if not await act({"op":"drawer"}):return
		for lead in [["P_A","W0_IN"],["W0_OUT","AM0_IN"],["AM0_OUT","R0_P"],["R0_P","L0_P"],["R0_P","C0_P"],["R0_N","P_N"],["L0_N","P_N"],["C0_N","P_N"],["W0_VN","P_N"],["V0_150","R0_P"],["V0_COM","P_N"],["DAQ_E0_P","R0_P"]]:
			if not await wire(lead[0],lead[1]):return
		for bank in [["R",2],["L",1],["C",2]]:
			var control: Vector3=lab.positions["%s_%d"%bank]
			if not await approach(Vector3(control.x,0,control.z+.5),.45):return
			if not await act({"op":"switch","kind":bank[0],"index":bank[1],"expected":false}):return
		if not await approach(lab.positions.storage):return
		if not await act({"op":"frequency","delta":-5}):return
		if not await act({"op":"supply_meter","delta":1}):return
		if not await act({"op":"power"}):return
		if not await until(func():return metered(state()),"replicated instrument readings"):return
		print("PASS client power, RLC, voltmeter, ammeter and wattmeter")
		if not await until(func():return observed[0],"late observer receipt"):return
		if not await act({"op":"breaker"}):return
		if not await act({"op":"unplug","port":"DAQ_E0_P"}):return
		if not await act({"op":"discard"}):return
		print("PASS client breaker and lead removal")
	await create_timer(1.5).timeout
	quit()

