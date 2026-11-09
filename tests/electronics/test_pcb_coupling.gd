extends SceneTree

const Board = preload("res://scripts/breadboard_model.gd")
const Station = preload("res://scripts/dc_station.gd")
const Coupling = preload("res://scripts/dc_coupling.gd")
const RoutedPCB = preload("res://tests/remaining/pcb/pcb_tests.gd")

func _initialize() -> void:
	call_deferred("run")

func link(a: int, port_a: String, b: int, port_b: String) -> Dictionary:
	return {"a":{"station":a,"port":port_a},"b":{"station":b,"port":port_b}}

func run() -> void:
	var supply := Station.new()
	supply.master = true
	supply.channels[0].enabled = true
	var pcb := Station.new()
	pcb.portable_slot = true
	var source := Board.empty()
	source.parts = [
		{"id":"button","type":"button","a":"A1","b":"A2"},
		{"id":"knob","type":"pot10k","a":"B2","b":"B4","pins":["B2","B3","B4"]},
		{"id":"led","type":"led","a":"C3","b":"C5"}
	]
	var circuit := Board.blueprint(source,"Series controls")
	circuit.package = "PCB"
	circuit.layout = source
	circuit.footprint = {"width":8,"height":6,"color":"24775b"}
	circuit.pins = [{"name":"IN","node":"L1"},{"name":"OUT","node":"L5"}]
	pcb.board = Board.standalone("ic:controls",{"ic:controls":circuit})
	var breadboard := Station.new()
	breadboard.portable_slot = true
	breadboard.board = Board.empty()
	breadboard.board.rows = 10
	breadboard.board.ports = ["P10","N10","A1","F1"]
	breadboard.board.parts = [{"id":"led","type":"led","a":"P9","b":"N9"}]
	var routed := Station.new()
	routed.portable_slot = true
	routed.board = Board.standalone("ic:routed",{"ic:routed":RoutedPCB.fixture()})
	var stations := [supply,breadboard,pcb,routed]
	for links in [
		[link(0,"CH1+",2,"X1"),link(2,"X2",0,"CH1-")],
		[link(0,"CH1+",1,"B1"),link(1,"B2",2,"X1"),link(2,"X2",0,"CH1-")],
		[link(0,"CH1+",3,"X1"),link(3,"X2",2,"X1"),link(2,"X2",0,"CH1-")]
	]:
		var error := pcb.apply({"op":"input","id":"board/pcb/button","pressed":false})
		Coupling.step(stations,links,.0005)
		var off := absf(float(pcb.result.get("i",{}).get("board/pcb/led",0)))
		error += pcb.apply({"op":"input","id":"board/pcb/button","pressed":true,"hold":true})
		Coupling.step(stations,links,.0005)
		var on := float(pcb.result.get("i",{}).get("board/pcb/led",0))
		error += pcb.apply({"op":"input","id":"board/pcb/knob","reverse":true})
		Coupling.step(stations,links,.0005)
		var adjusted := float(pcb.result.get("i",{}).get("board/pcb/led",0))
		if not error.is_empty() or off > .0000001 or on < .0001 or adjusted <= on:
			push_error("PCB coupling failed for %s. Off %.9f, on %.9f, adjusted %.9f. %s" % [links,off,on,adjusted,error])
			quit(1)
			return
		if links[0].b.station == 1 and not is_equal_approx(adjusted,float(breadboard.result.i["board/led"])):
			push_error("Breadboard LED did not follow the PCB controls")
			quit(1)
			return
	print("PCB COUPLING PASS")
	quit()


