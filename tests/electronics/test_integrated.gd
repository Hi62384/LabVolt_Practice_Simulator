extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var Board=load("res://scripts/breadboard_model.gd")
	var design=Board.empty();design.parts=[{"id":"load","type":"r1000","a":"A1","b":"F1"}];design.ports=["A1","F1","A2","F2"]
	assert(Board.validate(design,{"r1000":1})=="")
	var station=load("res://scripts/dc_station.gd").new()
	assert(station.apply({"op":"board","design":design})=="")
	station.master=true;station.channels[0].enabled=true;station.channels[0].voltage=5
	station.wires=[["CH1+","B1"],["CH1-","B2"],["VΩ","B1"],["COM","B2"]]
	station.step();assert(station.result.ok)
	assert(abs(float(station.result.i["board/load"])-.005)<.00001)
	assert(abs(station.difference("VΩ","COM")-5)<.001)
	station.master=false;station.meter_mode="Resistance"
	assert(abs(station.test_measure().to_float()-1000)<.1)
	var profile=load("res://scripts/electronics_profile.gd").new();profile.open("integration-"+str(Time.get_ticks_usec()))
	assert(profile.kit_error("starter")=="")
	var before=profile.data.inventory.duplicate(true);profile.duplicate_kit();assert(profile.data.inventory==before)
	assert(profile.reward("assignment",50,1,false)==60);assert(profile.reward("assignment",100,1,false)==0)
	assert(profile.purchase_bundle({"r1000":10},8)=="Bundle purchased")
	var malformed=profile.data.duplicate(true);malformed.inventory.r1000=1.5;assert(not profile.valid(malformed))
	var canvas=load("res://scripts/breadboard_canvas.gd").new();root.add_child(canvas);canvas.board=design.duplicate(true);canvas.selected=["load"]
	canvas.transform_selected(1,0);assert(canvas.board.parts[0].a=="A2");canvas.undo();assert(canvas.board.parts[0].a=="A1")
	assert(canvas.resize_board(10));assert(canvas.board.rows==10)
	var Store=load("res://scripts/notebook_store.gd")
	var notes={"strokes":{"0":[{"points":[Vector2(.1,.2),Vector2(.2,.3)],"color":"263743","width":2}]},"annotations":{},"page":2}
	assert(Store.valid(notes));Store.write("test",notes);assert(Store.read("test")==notes)
	print("PASS: common board/supply/meter netlist, passive measurement, kit templates, rewards once, bundle purchase, save validation, board move/undo/resize, notebook roundtrip")
	quit()
