extends SceneTree

const PORT := 26317
const Fixture = preload("res://scripts/lab_challenges/scenario_catalog.gd")
var game
var host: bool
var deadline: int
var notice := ""

func _initialize() -> void:
	call_deferred("run")

func until(condition: Callable, description: String) -> bool:
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await create_timer(.07).timeout
	push_error("AC auxiliary timeout: %s. %s. %s" % [description, notice, str(state().get("readings",{}).get("fault",""))])
	quit(1)
	return false

func state() -> Dictionary:
	if host:
		return game.session.labs[0].snapshot()
	return game.station_snapshots[0] if not game.station_snapshots.is_empty() else {}

func reach(control: String) -> bool:
	var target: Vector3 = game.session.labs[0].positions[control]
	target = Vector3(target.x, 0, target.z + .5)
	return await until(func():
		game.player.global_position = target
		game.session.send_pose({"position":target})
		return game.session.poses.get(game.multiplayer.get_unique_id(), {}).get("position", Vector3.INF).distance_to(target) < .5
	, "reach " + control)

func send(request: Dictionary, control: String) -> bool:
	if not await reach(control):
		return false
	var revision: int = state().revision
	request.station = 0
	game.session.request(request)
	return await until(func(): return state().revision > revision, str(request))

func set_analog_output_in_ui() -> bool:
	if not await reach("daq"):
		return false
	game.paper_ui.daq_page()
	var output_row: HBoxContainer
	for child in game.paper_ui.column.get_children():
		if child is HBoxContainer:
			output_row = child
			break
	if output_row == null or not output_row.get_child(0) is SpinBox:
		push_error("DAQ output controls are missing")
		quit(1)
		return false
	output_row.get_child(0).value = 6.
	output_row.get_child(1).pressed.emit()
	if not await until(func(): return state().daq_settings.get("AO0",0.) == 6., "DAQ panel sets AO0"): return false
	await create_timer(.3).timeout
	game.paper_ui.close()
	return true

func initial_readings() -> bool:
	var r: Dictionary = state().get("readings",{})
	if not r.has("daq_dc_v") or not r.fault.is_empty():
		return false
	return absf(r.daq_dc_v[0].x - 60.) < .02 and absf(r.daq_dc_v[1].x - 120.) < .02 and absf(r.daq_v[2].length() - 24.) < .02

func switched_readings() -> bool:
	var r: Dictionary = state().get("readings",{})
	if not r.get("igbt", {}).get("sync",false) or r.igbt.disabled:
		return false
	return r.igbt.legs == [1,2,1] and r.daq_digital == [true,true,true] and absf(r.daq_analog[0].dc - 6.) < .05 and absf(r.daq_analog[1].dc + 4.) < .05 and absf(r.daq_analog[2].ac_rms - 24.) < .02 and absf(r.daq_dc_v[3].x - 60.) < .02

func disabled_readings() -> bool:
	var r: Dictionary = state().get("readings",{})
	if not r.get("igbt",{}).get("disabled", false):
		return false
	return r.igbt.legs == [0,0,0] and absf(r.daq_dc_v[3].x) < .001

func wire_pulse_test() -> void:
	var lab = game.session.labs[1]
	var switches: Dictionary = lab.switches.duplicate(true)
	switches.R[2] = true
	var leads := [["DC_7","IGBT_1"],["DC_N7","IGBT_2"],["IGBT_3","R0_P"],["IGBT_2","R0_N"],["R0_P","DAQ_E0_P"],["R0_N","DAQ_E0_N"]]
	Fixture.install(lab, {"frequency":60.,"level":.5,"dyn_load":0.,"switches":switches,"leads":leads})
	lab.powered = true
	lab.recalculate()
	var dc = game.dc_lab
	dc.benches[0].generator.merge({"enabled":true,"wave":"Pulse","frequency":60.,"amplitude":2.5,"offset":2.5,"resistance":50.},true)
	dc.external_links.append({"a":{"station":0,"port":"GEN"},"b":{"station":dc.AC_OFFSET + 1,"port":"IGBT_GATE1"},"jacket":0})
	dc.external_links.append({"a":{"station":0,"port":"REF"},"b":{"station":dc.AC_OFFSET + 1,"port":"IGBT_COMMON"},"jacket":0})
	dc.refresh_link_flags()
	game.session.broadcast()

func pulse_readings() -> bool:
	if game.station_snapshots.size() < 2:
		return false
	var r: Dictionary = game.station_snapshots[1].readings
	if not r.has("daq_dc_v"):
		return false
	return r.daq_dc_v[0].x > 15. and r.daq_dc_v[0].x < 45. and r.daq_v[0].length() > 15.

func pulse_cleared() -> bool:
	var r: Dictionary = game.station_snapshots[1].readings
	return r.get("igbt",{}).get("legs",[]) == [0,0,0] and absf(r.daq_dc_v[0].x) < .001 and r.daq_v[0].length() < .001

func run() -> void:
	host = OS.get_cmdline_user_args()[0] == "host"
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:
		await process_frame
	deadline = Time.get_ticks_msec() + 45000
	game.session.message_received.connect(func(message): notice = message)
	if host:
		if game.session.host_game("Host", PORT) != OK:
			quit(1)
			return
		game.capture()
		var lab = game.session.labs[0]
		var leads := [
			["DC_7","DAQ_E0_P"],["DC_N7","DAQ_E0_N"],["DC_8","DAQ_E1_P"],["DC_N8","DAQ_E1_N"],
			["LOW_0","DAQ_E2_P"],["LOW_1","DAQ_E2_N"],["LOW_1","DAQ_DI2_N"],["LOW_0","DAQ_AI2"],
			["DAQ_AO0","DAQ_AI0"],["DAQ_AO1","DAQ_AI1"],["DAQ_AO0_N","DAQ_DI2_N"],["DAQ_AO1_N","DAQ_DI2_N"],
			["DAQ_DO0","DAQ_DI0"],["DAQ_DO0","DAQ_DI1"],["DAQ_DO0","DAQ_DI2"],["DAQ_DI0_N","DAQ_DI2_N"],["DAQ_DI1_N","DAQ_DI2_N"],
			["DAQ_DI2_N","IGBT_COMMON"],["DAQ_DO0","IGBT_GATE1"],["DAQ_DO0","IGBT_GATE4"],["DAQ_DO0","IGBT_GATE5"],["DAQ_DO0","IGBT_SYNC"],
			["DAQ_DO1","IGBT_DISABLE"],["DC_7","IGBT_1"],["DC_N7","IGBT_2"],["IGBT_3","DAQ_E3_P"],["IGBT_4","DAQ_E3_N"]
		]
		Fixture.install(lab, {"frequency":60.,"level":.5,"dyn_load":0.,"switches":lab.switches,"leads":leads})
		lab.mode = "Free Laboratory"
		game.session.broadcast()
	else:
		var address := OS.get_environment("LABVOLT_TEST_HOST")
		game.front.network_page(true)
		game.front.join_address.text = address if not address.is_empty() else "127.0.0.1"
		game.front.join_port.text = str(PORT)
		game.front.join_connect.pressed.emit()
		if not await until(func(): return state().get("cables",[]).size() == 27, "rack wiring"): return
		if not await until(func(): return not game.front.joining and game.session.roster.size() == 2, "Join Game connects and registers"): return
		print("PASS Join Game address and port reached the host")
		if not await send({"op":"power"}, "power"): return
		if not await until(initial_readings, "two DC outlets and 24 VAC"): return
		await create_timer(.09).timeout
		if not await set_analog_output_in_ui(): return
		for setting in [["AO1",-4.],["DO0",true]]:
			await create_timer(.09).timeout
			if not await send({"op":"daq_output","channel":setting[0],"value":setting[1]}, "daq"): return
	if not await until(switched_readings, "DAQ loopback and three IGBT legs"): return
	print("PASS auxiliary supply, DAQ analog/digital loopback, IGBT gates and sync")
	if not host:
		await create_timer(.5).timeout
		if not await send({"op":"daq_output","channel":"DO1","value":true}, "daq"): return
	if not await until(disabled_readings, "IGBT disable removes load voltage"): return
	print("PASS IGBT disable disconnects switched power")
	if host:
		wire_pulse_test()
	if not await until(pulse_readings, "live PWM load readings across AC/DC benches"): return
	print("PASS live PWM load readings synced without another rack action")
	if host:
		await create_timer(1).timeout
		game.dc_lab.external_links.clear()
		game.dc_lab.refresh_link_flags()
	if not await until(pulse_cleared, "readings clear when pulse leads are unplugged"): return
	print("PASS unplugging pulse leads clears synced load readings")
	await create_timer(1).timeout
	quit()
