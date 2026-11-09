extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var Board=load("res://scripts/breadboard_model.gd");var Custom=load("res://scripts/custom_circuit.gd")
	var original=Board.empty();original.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}];original.ports=["A1","F1","A2","F2"]
	var definitions={"ic:a":Board.blueprint(original,"Resistor module")}
	var nested=Board.empty();nested.definitions=definitions.duplicate(true);nested.parts=[{"id":"nested","type":"ic:a","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]}];nested.ports=original.ports.duplicate()
	definitions["ic:b"]=Board.blueprint(nested,"Nested module")
	assert(Custom.validate("ic:b",definitions)=="");assert(Custom.materials("ic:b",definitions)=={"r1000":1})
	var outer=Board.empty();outer.definitions=definitions;outer.parts=[{"id":"module","type":"ic:b","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]}];outer.ports=original.ports.duplicate()
	assert(Board.validate(outer,{"ic:b":1})=="")
	var station=load("res://scripts/dc_station.gd").new();assert(station.apply({"op":"board","design":outer})=="")
	station.master=true;station.channels[0].enabled=true;station.wires=[["CH1+","B1"],["CH1-","B2"]];station.step();assert(station.result.ok)
	assert(abs(float(station.result.i["board/module/nested/r"])-.005)<.00001)
	var cyclic=definitions.duplicate(true);cyclic["ic:a"].parts=[{"id":"loop","type":"ic:b","nodes":["L1","R1","L2","R2"]}]
	assert("Circular" in Custom.validate("ic:b",cyclic))
	var profile=load("res://scripts/electronics_profile.gd").new();profile.open("custom-"+str(Time.get_ticks_usec()));profile.data.blueprints=definitions
	var before=int(profile.data.inventory.r1000)
	assert(profile.obtain_ic("ic:b",true)=="Custom IC added to inventory")
	assert(profile.data.inventory.r1000==before-1 and profile.data.inventory["ic:b"]==1)
	assert(profile.save()==OK)
	var pin_map=[]
	for i in 6:pin_map.append({"name":"Signal "+str(i),"hole":"A"+str(i+1)})
	assert(profile.save_blueprint("Six pin",pin_map,"Named pin mapping").begins_with("Blueprint saved"))
	var found=false
	for bp in profile.data.blueprints.values():
		if bp.name=="Six pin":found=bp.pins.size()==6 and bp.pins[5].node=="L6"
	assert(found)
	print("PASS: nested IC equals original circuit, recursive BOM counts once, circular dependencies rejected, crafting consumes one real resistor and saves")
	quit()
