extends SceneTree
## Existing DCStation + Breadboard expansion + production MNA, no alternate solver.
const Station=preload("res://scripts/dc_station.gd")
const Board=preload("res://scripts/breadboard_model.gd")
var station=Station.new()
var failed:=0
var checks:=0
var signals:=["RS","E","D4","D5","D6","D7"]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL "+label)
func settle(count: int=3) -> void:
	for step in count:station.step(.0005)
	check(station.result.get("ok",false),"production station electrical solve")
func set_switch(name: String,pressed: bool) -> void:
	for part in station.board.parts:
		if part.id==name:part.pressed=pressed
func nibble(value: int,rs: bool) -> void:
	set_switch("RS",rs);set_switch("E",false)
	for bit in 4:set_switch("D"+str(bit+4),(value&(1<<bit))!=0)
	settle();set_switch("E",true);settle();set_switch("E",false);settle()
func byte(value: int,rs: bool=false) -> void:nibble(value>>4,rs);nibble(value&15,rs)
func _initialize() -> void:
	var board:=Board.empty()
	var pins: Array=[]
	for row in range(2,10):pins.append("A"+str(row));pins.append("F"+str(row))
	board.parts=[{"id":"power","type":"battery","a":"A1","b":"F1"},{"id":"lcd","type":"hd44780","a":"A2","b":"F2","pins":pins}]
	board.wires=[[pins[0],"F1"],[pins[1],"A1"],[pins[2],"F1"],[pins[4],"F1"],["N1","F1"]]
	var indices: Array=[3,5,10,11,12,13]
	for index in signals.size():
		var row:=index+14
		board.parts.append({"id":signals[index],"type":"toggle","a":"A"+str(row),"b":"F"+str(row),"pressed":false})
		var hole: String=pins[indices[index]]
		var adjacent: String=("B" if hole.begins_with("A") else "G")+hole.substr(1)
		board.parts.append({"id":"pd"+str(index),"type":"r10000","a":adjacent,"b":"N"+str(index+1)})
		board.wires.append_array([["A"+str(row),"A1"],["F"+str(row),pins[indices[index]]]])
	var inventory:={"battery":1,"hd44780":1,"toggle":6,"r10000":6}
	check(Board.validate(board,inventory)=="","real buildable breadboard design: "+Board.validate(board,inventory))
	station.board=board;settle(30)
	nibble(2,false);byte(0x28);byte(0x0C);byte(0x80)
	for character in "TEST".to_ascii_buffer():byte(character,true)
	var live: Dictionary=station.snapshot().firmware.get("board/lcd",{})
	check(live.get("lines",[""])[0].begins_with("TEST"),"actual switch-wired HD44780 text in station snapshot")
	check(live.get("display",false),"actual physical display enabled")
	station.board.parts=station.board.parts.filter(func(part):return part.id!="power")
	settle(5)
	check(not station.snapshot().firmware["board/lcd"].powered,"physical supply removal powersdisplayoff")
	check(not station.snapshot().firmware["board/lcd"].has("ram"),"unpowered snapshot no stalevisibleframe")
	print("STATION checks=",checks," failures=",failed)
	quit(1 if failed else 0)
