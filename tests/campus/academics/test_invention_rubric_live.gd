extends SceneTree
const Station=preload("res://scripts/dc_station.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Runtime=preload("res://scripts/firmware_runtime.gd")
const Rubric=preload("res://scripts/campus/academics/invention_rubric.gd")
func _initialize() -> void:
	var station:=Station.new()
	var board:=Board.empty()
	board.parts=[{"id":"mcu","type":"lv_mcu","a":"A1","b":"F1","pins":["A1","A2","A3","F1","F2","F3"],"firmware":Runtime.TEMPLATE},{"id":"r","type":"r220","a":"B3","b":"A7"},{"id":"led","type":"led","a":"B7","b":"B2"}]
	board.ports=["A1","A2","A3","F3"]
	assert(station.apply({"op":"board","design":board})=="")
	station.board_owner=1;station.master=true;station.channels[0].enabled=true;station.wires=[["CH1+","B1"],["CH1-","B2"]]
	for i in 100:station.step(.001)
	var result:=Rubric.evaluate_led(station)
	assert(result.passed)
	station.board_epoch+=1
	assert(not Rubric.evaluate_led(station).passed)
	print("INVENTION_RUBRIC_LIVE PASS")
	quit()
