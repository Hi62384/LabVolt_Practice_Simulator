extends RefCounted
## Authored digital-lab plans. Every operation goes through the DC
## station domain and every observation uses the normal evidence reader.
const Board=preload("res://scripts/breadboard_model.gd")
const Evidence=preload("res://scripts/campus/academics/digital_evidence.gd")

static func commands(kind: String) -> Array:
	if kind=="digital_scope":
		return [
			_wire("GEN","S1",0),_wire("REF","GND",1),
			{"op":"generator","key":"wave","value":"Square"},
			{"op":"generator","key":"frequency","value":40.},
			{"op":"generator","key":"amplitude","value":2.5},
			{"op":"generator","key":"offset","value":2.5},
			{"op":"generator","key":"duty","value":.5},
			{"op":"generator","key":"enabled","value":true,"label":"reading scope"},
			{"op":"observe","label":"reading scope"},
		]
	var board:=Board.empty()
	var inputs: Array=[]
	var count:=rows_required(kind)
	match kind:
		"digital_binary":
			var gate:=_chip(board,"practice_gate","hc08",1)
			inputs=[gate[0],gate[1],gate[3],gate[4]]
		"digital_truth_table","digital_interlock":
			var gate:=_chip(board,"practice_gate","hc08",1)
			inputs=[gate[1],gate[0]]
		"digital_simplify":
			var final_gate:=_chip(board,"final_and","hc08",1)
			var junction:=_chip(board,"junction","hc32",11)
			var inverter:=_chip(board,"inverter","hc04",21)
			board.wires.append_array([[junction[2],final_gate[1]],[inverter[0],junction[0]],[inverter[1],junction[1]]])
			inputs=[inverter[0],final_gate[0]]
		"digital_combination":
			var first:=_chip(board,"first_and","hc08",1)
			var final_gate:=_chip(board,"final_or","hc32",11)
			board.wires.append([first[2],final_gate[0]])
			inputs=[final_gate[1],first[1],first[0]]
		"digital_display":
			var decoder:=_chip(board,"decoder","ls47",1,8)
			var display: Array=[]
			for row in range(11,20):display.append("A%d"%row)
			_part(board,"display","seven_segment_ca",display)
			board.wires.append(["P1",display[8]])
			for pin in [2,3,4]:board.wires.append(["P1",decoder[pin]])
			for segment in 7:
				var drive: String=decoder[[12,11,10,9,8,14,13][segment]]
				_part(board,"limiter_%d"%segment,"r330",[_adjacent(drive),_adjacent(display[segment])])
			inputs=[decoder[6],decoder[0],decoder[1],decoder[5]]
		"digital_flipflop":
			var gate:=_chip(board,"flip","flip74",1)
			for pin in [0,3]:board.wires.append(["P1",gate[pin]])
			inputs=[gate[2],gate[1]]
		_:return []
	for index in inputs.size():
		_part(board,"input_%d"%index,"toggle",["P%d"%(index+2),_adjacent(inputs[index])])
		_part(board,"pull_down_%d"%index,"r10000",["N%d"%(index+2),_adjacent(inputs[index],2)])
	var plan: Array=[{"op":"board","design":board,"label":"placing breadboard"},
		_wire("CH1+","B1",0),_wire("CH1-","B2",1),_channel(0,"limit",.1),_channel(0,"voltage",5.),
		_channel(0,"enabled",true),{"op":"master","label":"powering breadboard"}]
	var previous:=0
	for row in count:
		for bit in inputs.size():
			if (previous^row)&(1<<bit):
				plan.append({"op":"input","id":"input_%d"%bit,"label":"setting logic inputs"})
		plan.append({"op":"observe","row":row,"label":"checking circuit behavior"})
		previous=row
	return plan

static func rows_required(kind: String) -> int:
	match kind:
		"digital_scope":return 1
		"digital_binary":return 16
		"digital_combination":return 8
		"digital_display":return 10
		_:return 4

static func _chip(board: Dictionary,id: String,type: String,start: int,half := 7) -> Array:
	var pins: Array=[]
	for row in range(start,start+half):pins.append("A%d"%row)
	for row in range(start+half-1,start-1,-1):pins.append("F%d"%row)
	_part(board,id,type,pins)
	board.wires.append_array([["N1",pins[half-1]],["P1",pins.back()]])
	return pins

static func _adjacent(pin: String,offset := 1) -> String:
	return String.chr(pin.unicode_at(0)+offset)+pin.substr(1)

static func _part(board: Dictionary,id: String,type: String,pins: Array) -> void:
	board.parts.append({"id":id,"type":type,"a":pins[0],"b":pins[1],"pins":pins})

static func observation(kind: String,station: RefCounted,row: int) -> Dictionary:
	if kind=="digital_scope":return Evidence.scope_sample(station)
	if not station.board_simulating() or station.solved_revision!=station.revision:return {}
	var samples: Array
	match kind:
		"digital_binary":samples=Evidence.binary_samples(station.board,station.result)
		"digital_simplify":samples=Evidence.combinational_samples(station.board,station.wires,station.result,4)
		"digital_combination":samples=Evidence.combinational_samples(station.board,station.wires,station.result,5)
		"digital_display":samples=Evidence.display_samples(station.board,station.wires,station.result,station.firmware_states,station.netlist())
		"digital_flipflop":
			for sample in Evidence.flip_samples(station.board,station.result,station.firmware_states):
				if sample.gate!="flip:a" or sample.clock!=bool(row&1) or sample.data!=bool(row&2):continue
				var expected:=row==3
				return {"gate":sample.gate,"row":row,"correct":sample.output==expected and sample.state==expected}
			return {}
		_:samples=Evidence.samples(station.board,station.result).filter(func(sample):return sample.gate=="practice_gate:0")
	for sample in samples:
		if sample.row==row:return sample
	return {}

static func _wire(a: String,b: String,color: int) -> Dictionary:
	return {"op":"wire","a":a,"b":b,"lead_color":color}

static func _channel(index: int,key: String,value: Variant) -> Dictionary:
	return {"op":"channel","index":index,"key":key,"value":value,"label":"setting logic inputs"}
