extends SceneTree
func _initialize():
	var station=load("res://scripts/dc_station.gd").new()
	var board=load("res://scripts/breadboard_model.gd").empty()
	board.parts=[{"id":"b","type":"button","a":"A1","b":"A2"},{"id":"t","type":"toggle","a":"A3","b":"A4"},{"id":"p","type":"pot10k","a":"A5","b":"A6","pins":["A5","A6","A7"],"setting":.5}]
	assert(station.apply({"op":"board","design":board})=="")
	assert(station.apply({"op":"input","id":"t"})=="")
	assert(station.board.parts[1].pressed)
	station.apply({"op":"input","id":"t"});assert(not station.board.parts[1].pressed)
	for i in 30:station.apply({"op":"input","id":"p"})
	assert(station.board.parts[2].setting==1)
	for i in 30:station.apply({"op":"input","id":"p","reverse":true})
	assert(station.board.parts[2].setting==0)
	station.apply({"op":"input","id":"b"});assert(station.board.parts[0].pressed)
	for i in 510:station.step()
	assert(not station.board.parts[0].pressed)
	assert(station.apply({"op":"input","id":"missing"})!="")
	print("PASS: physical switch toggles, potentiometer clamps at both endpoints, momentary button releases, missing controls rejected")
	quit()
