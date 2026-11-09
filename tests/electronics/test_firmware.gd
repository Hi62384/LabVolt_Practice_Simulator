extends SceneTree
const Runtime=preload("res://scripts/firmware_runtime.gd")
var fails := 0
func check(ok: bool,message: String):
	print("PASS " if ok else "FAIL ",message)
	if not ok:fails+=1
func _initialize():
	check(not Runtime.compile("load file.txt").ok,"unsupported host operations rejected")
	check(not Runtime.compile("goto 200").ok,"bad jump diagnostics")
	var runner=Runtime.new();var nodes=["v","g","d0","d1","a0","pwm"]
	var state=runner.tick("goto 1",nodes,{"v":5.0,"g":0.0},.001)
	check(state.status=="Running","infinite loop yields within bounded instruction budget")
	var station=load("res://scripts/dc_station.gd").new()
	var board=load("res://scripts/breadboard_model.gd").empty()
	board.parts=[{"id":"mcu","type":"lv_mcu","a":"A1","b":"F1","pins":["A1","A2","A3","F1","F2","F3"],"firmware":Runtime.TEMPLATE},{"id":"r","type":"r220","a":"B3","b":"A7"},{"id":"led","type":"led","a":"B7","b":"B2"}]
	board.ports=["A1","A2","A3","F3"]
	check(station.apply({"op":"board","design":board})=="","programmable board validates")
	station.master=true;station.channels[0].enabled=true;station.wires=[["CH1+","B1"],["CH1-","B2"]]
	for i in 100:station.step(.001)
	check(station.result.ok and float(station.result.i.get("board/led",0))>.01,"firmware drives actual LED current")
	for i in 500:station.step(.001)
	check(absf(float(station.result.i.get("board/led",0)))<.00001,"wait and write switch actual LED off")
	for i in 500:station.step(.001)
	check(float(station.result.i.get("board/led",0))>.01,"program loop returns LED on")
	station.master=false
	for i in 5:station.step(.001)
	check(not station.firmware_states["board/mcu"].powered,"loss of circuit power resets controller")
	var bp=load("res://scripts/breadboard_model.gd").blueprint(board,"Blinker")
	check(bp.parts[0].firmware==Runtime.TEMPLATE,"custom assembly preserves firmware")
	print("FIRMWARE FAILURES: ",fails);quit(fails)
