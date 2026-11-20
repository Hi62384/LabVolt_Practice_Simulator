extends SceneTree
## Exercises the reported relay/switch-inductor LED handoff on a real board,
## then confirms that stopping Circuit Maker clears its rendered live state.
const Station=preload("res://scripts/dc_station.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Workspace=preload("res://scripts/electronics/circuit_workspace/workspace.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	_check_flyback()
	await _check_editor_stop()
	print("INVENTION_ANALOG_UI PASS: stored inductor energy lights flyback LED, and Stop clears live LED/meter state")
	quit()

func _check_flyback() -> void:
	var board: Dictionary=Board.empty()
	board.ports=["A1","F1","A3","F2"]
	# All six physical leads occupy distinct holes while their internal
	# breadboard nodes create the required flyback loop.
	board.parts=[
		{"id":"sw","type":"toggle","a":"A1","b":"A2"},
		{"id":"coil","type":"l100","a":"B2","b":"F1"},
		{"id":"led","type":"led","a":"G1","b":"C2"}
	]
	assert(Board.validate(board,{},true)=="","Flyback test circuit must be physically placeable")
	var station:=Station.new()
	assert(station.apply({"op":"board","design":board})=="")
	station.master=true
	station.channels[0].enabled=true
	station.channels[0].voltage=5.0
	station.channels[0].limit=.5
	station.wires=[["CH1+","B1"],["CH1-","B2"]]
	assert(station.apply({"op":"input","id":"board/sw","pressed":true})=="")
	for index in 10:station.step(.0005)
	assert(station.result.get("ok",false),str(station.result))
	var charged_current:=float(station.result.get("i",{}).get("board/coil",0.0))
	assert(charged_current>.02,"Closed switch must store nonzero inductor current")
	assert(absf(float(station.result.get("i",{}).get("board/led",0.0)))<.0000001,
		"LED must block reverse current while the inductor charges")
	assert(station.apply({"op":"input","id":"board/sw","pressed":true})=="")
	station.step(.0005)
	assert(station.result.get("ok",false),str(station.result))
	var flash_current:=float(station.result.get("i",{}).get("board/led",0.0))
	assert(flash_current>.005,"Opening the switch must route stored inductor current through the correctly oriented LED")
	for index in 100:station.step(.0005)
	assert(station.result.get("ok",false),str(station.result))
	assert(absf(float(station.result.get("i",{}).get("board/led",0.0)))<.00001,
		"Flyback LED must turn off after inductor energy dissipates")

func _check_editor_stop() -> void:
	var board: Dictionary=Board.empty()
	board.parts=[{"id":"led","type":"led","a":"A1","b":"F1"}]
	var workspace:=Workspace.new()
	root.add_child(workspace)
	workspace.configure_maker(board,{},Catalog.all(),{},true)
	await process_frame
	assert(is_instance_valid(workspace.simulation_button),"Circuit Maker simulation button must be present")
	workspace.simulation_button.button_pressed=true
	assert(workspace.simulating,"Circuit Maker must enter simulation mode")
	workspace.canvas.currents={"board/led":.02}
	workspace.canvas.device_states={"board/led":{"on":true}}
	workspace.canvas.accept_measurements({"ok":true,"v":{"A1":5.0}})
	workspace.simulation_button.button_pressed=false
	assert(not workspace.simulating and workspace.simulation_button.text=="Simulate",
		"Stop must leave simulation mode")
	assert(workspace.canvas.currents.is_empty() and workspace.canvas.device_states.is_empty(),
		"Stop must clear stale LED and component indications without hover")
	assert(workspace.canvas.measurements.is_empty(),
		"Stop must clear stale meter readings without hover")
	workspace.queue_free()
	await process_frame
