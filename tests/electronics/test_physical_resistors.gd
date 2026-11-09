extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var Profile=load("res://scripts/electronics_profile.gd")
	var Ledger=load("res://scripts/inventory_authority/ledger.gd")
	var Board=load("res://scripts/breadboard_model.gd")
	var Persistent=load("res://scripts/inventory_authority/component_persistence.gd")
	var type := "r1000_t5_w25"
	var profile=Profile.new();profile.open("resistor-acceptance")
	profile.data.inventory[type]=2;profile.data.kits.starter.items[type]=2
	var ledger=Ledger.new();assert(ledger.open("user://resistor-ledger")==OK)
	assert(ledger.bind(1,"a".repeat(48),"1".repeat(64),profile.data).ok)
	var design: Dictionary=Board.empty();design.parts=[{"id":"load","type":type,"a":"A1","b":"F1"}]
	var actual: Dictionary=ledger.materialize(1,design)
	var parameters: Dictionary=actual.component_runtime["board/load"]
	assert(Persistent.valid(actual.component_runtime) and parameters.actual>=950 and parameters.actual<=1050)
	assert(parameters.watts==0.25 and actual.instance_ids.size()==1)
	var station=load("res://scripts/dc_station.gd").new()
	assert(station.apply({"op":"board","design":actual})=="")
	station.master=true;station.channels[0].enabled=true;station.channels[0].voltage=5;station.channels[0].limit=0.1
	station.wires=[["CH1+","B3"],["CH1-","B4"]]
	station.step(0.0005)
	assert(station.result.ok)
	var primitive: Dictionary=station.netlist().filter(func(part):return part.id=="board/load")[0]
	assert(primitive.value==parameters.actual)
	assert(absf(station.result.drop["board/load"]/station.result.i["board/load"]-parameters.actual)<0.0001)
	assert(station.result.resistor_ratings["board/load"].rating_watts==0.25)
	assert(ledger.deploy(1,0,actual)=="")
	assert(ledger.capture_components(1,station.board,station.firmware_states)=="")
	assert(ledger.recall(1))
	var again: Dictionary=ledger.materialize(1,actual)
	assert(again.component_runtime["board/load"]==parameters)
	var receiver=Profile.new();receiver.open("resistor-recipient")
	assert(ledger.bind(2,"b".repeat(48),"2".repeat(64),receiver.data).ok)
	var selections := {1:{},2:{}}
	for id in actual.instance_ids.values():selections[1][id]=ledger.instance_hash(ledger.account(1).profile.component_instances[id])
	assert(ledger.exchange("physical-resistor-transfer",[1,2],{1:{type:1},2:{}},{},selections).ok)
	var delivered: Dictionary=ledger.materialize(2,design)
	assert(delivered.component_runtime["board/load"]==parameters)
	var reopened=Ledger.new();assert(reopened.open("user://resistor-ledger")==OK)
	assert(reopened.bind(3,"b".repeat(48),"2".repeat(64),receiver.data).ok)
	assert(reopened.materialize(3,design).component_runtime["board/load"]==parameters)
	var invalid: Dictionary=parameters.duplicate();invalid.actual=1.0
	assert(not Persistent.valid({"board/load":invalid}))
	print("PASS: host-owned resistor tolerances and ratings feed real solver; recall, actual unit trade and host restart preserve measured value; forged out-of-range values rejected")
	quit()
