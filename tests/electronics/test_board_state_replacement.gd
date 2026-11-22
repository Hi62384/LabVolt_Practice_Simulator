extends SceneTree
## Real station solver regression: an installed replacement must not inherit a
## different physical component's capacitor charge, battery usage or button
## timers. Unchanged parts retain their state across ordinary wiring edits.
const Board=preload("res://scripts/breadboard_model.gd")
const Station=preload("res://scripts/dc_station.gd")

func _initialize() -> void:
	var station:=Station.new()
	var board: Dictionary=Board.empty()
	board.parts=[
		{"id":"feed","type":"r1000","a":"A1","b":"A2"},
		{"id":"storage","type":"c10.0","a":"B2","b":"F1"}
	]
	board.instance_ids={"feed":"resistor-1","storage":"capacitor-1"}
	board.ports=["A1","F1","A3","F2"]
	assert(Board.validate(board,{},true)=="")
	assert(station.apply({"op":"board","design":board})=="")
	station.master=true
	station.channels[0].enabled=true
	station.channels[0].limit=.5
	station.wires=[["CH1+","B1"],["CH1-","B2"]]
	for tick in 50:station.step(.001)
	assert(station.result.get("ok",false),str(station.result))
	var charge: float=float(station.solver.memory.get("board/storage",0.0))
	assert(charge>4.0 and charge<5.1,"Physical capacitor must charge through the 1 kOhm resistor")
	var rewired: Dictionary=board.duplicate(true)
	rewired.wires=[["A10","F10"]]
	assert(station.apply({"op":"board","design":rewired})=="")
	assert(is_equal_approx(float(station.solver.memory.get("board/storage",0.0)),charge),
		"Editing unrelated wiring discharged an unchanged capacitor")
	var replacement: Dictionary=rewired.duplicate(true)
	replacement.instance_ids.storage="capacitor-2"
	assert(station.apply({"op":"board","design":replacement})=="")
	assert(not station.solver.memory.has("board/storage"),
		"A different physical capacitor inherited the old capacitor's charge")
	assert(station.solver.last.is_empty() and station.result.is_empty(),
		"Replaced board leaked stale pre-replacement voltages into the next controller tick")
	station.step(.001)
	assert(station.result.get("ok",false),str(station.result))
	assert(float(station.solver.memory.get("board/storage",5.0))<charge-0.5,
		"Replacement capacitor did not restart its RC transient")
	# A new part with the same editor ID but a different type must also reset.
	var changed_type: Dictionary=replacement.duplicate(true)
	changed_type.parts[1].type="r1000"
	changed_type.instance_ids.storage="resistor-2"
	assert(station.apply({"op":"board","design":changed_type})=="")
	assert(not station.solver.memory.has("board/storage"),
		"Changing a capacitor to a resistor retained storage energy")
	# The high-level bench also needs to clear deferred button releases when
	# its editor ID is reused: an old key-up must not release a new button.
	var buttons:=Station.new()
	var pressed_board: Dictionary=Board.empty()
	pressed_board.parts=[{"id":"trigger","type":"button","a":"A1","b":"F1"}]
	pressed_board.instance_ids={"trigger":"button-1"}
	assert(buttons.apply({"op":"board","design":pressed_board})=="")
	assert(buttons.apply({"op":"input","id":"board/trigger","pressed":true})=="")
	assert(buttons.button_releases.has("board/trigger"))
	var new_button: Dictionary=pressed_board.duplicate(true)
	new_button.instance_ids.trigger="button-2"
	assert(buttons.apply({"op":"board","design":new_button})=="")
	assert(not buttons.button_releases.has("board/trigger"),
		"Old momentary timer would release a newly installed button")
	# With the same ID and battery rating, swapping physical batteries must not
	# give the new pack the old one's discharge and depleted voltage.
	var battery_station:=Station.new()
	var powered_board: Dictionary=Board.empty()
	powered_board.parts=[
		{"id":"cell","type":"battery","a":"A1","b":"F1"},
		{"id":"load","type":"r1000","a":"B1","b":"G1"}
	]
	powered_board.instance_ids={"cell":"battery-1","load":"load-1"}
	assert(Board.validate(powered_board,{},true)=="")
	assert(battery_station.apply({"op":"board","design":powered_board})=="")
	battery_station.step(100.0)
	assert(battery_station.result.get("ok",false),str(battery_station.result))
	assert(not battery_station.solver.battery_discharge.is_empty(),
		"Real battery model did not record discharge from its load")
	var replacement_battery: Dictionary=powered_board.duplicate(true)
	replacement_battery.instance_ids.cell="battery-2"
	assert(battery_station.apply({"op":"board","design":replacement_battery})=="")
	assert(battery_station.solver.battery_discharge.is_empty(),
		"Replacement battery inherited the discharged capacity of an old pack")
	battery_station.step(.001)
	assert(battery_station.result.get("ok",false),str(battery_station.result))
	assert(is_equal_approx(float(battery_station.result.charge.get("board/cell",0.0)),1.0),
		"Newly installed battery did not begin at full capacity")
	print("BOARD_STATE_REPLACEMENT PASS")
	quit()
