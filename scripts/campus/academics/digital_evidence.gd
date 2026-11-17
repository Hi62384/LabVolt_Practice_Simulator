extends RefCounted
## Read only: interpret a settled host simulation, never client-supplied marks.
const Board = preload("res://scripts/breadboard_model.gd")
const Catalog = preload("res://scripts/electronics_catalog.gd")
const Solver = preload("res://scripts/electronics_solver.gd")

static func scope_sample(station: RefCounted) -> Dictionary:
	if station.linked or not station.generator.enabled or station.generator.wave not in ["Square","Pulse"]:return {}
	var roots:={"GEN":"GEN","REF":"REF","S1":"S1","GND":"GND"}
	for wire in station.wires:
		for pin in wire:roots.get_or_add(str(pin),str(pin))
	for wire in station.wires:
		if wire.size()==2:roots[Solver.root(roots,str(wire[0]))]=Solver.root(roots,str(wire[1]))
	if Solver.root(roots,"GEN")!=Solver.root(roots,"S1") or Solver.root(roots,"REF")!=Solver.root(roots,"GND"):return {}
	var data: Array=station.scope_capture.display
	if data.size()<8:return {}
	var stats: Dictionary=station.statistics(data,1)
	var frequency:=float(station.generator.frequency)
	if frequency<=0 or float(stats.vpp)<0.5 or absf(float(stats.frequency)-frequency)>frequency*.15:return {}
	if float(station.solver.time)-float(data.back()[0])>maxf(.2,3.0/frequency):return {}
	var low:=INF;var high:=-INF
	for row in data:
		low=minf(low,float(row[1]));high=maxf(high,float(row[1]))
	var extremes:=0;var low_count:=0;var high_count:=0
	for row in data:
		var value: float=(float(row[1])-low)/(high-low)
		if value<=.2:extremes+=1;low_count+=1
		elif value>=.8:extremes+=1;high_count+=1
	if low_count<2 or high_count<2 or float(extremes)/data.size()<.85:return {}
	return {"gate":"scope","row":0,"required":1,"correct":true}

static func display_samples(board: Dictionary, wires: Array, result: Dictionary, states: Dictionary, parts: Array) -> Array:
	if not result.get("ok",false):return []
	var volts: Dictionary=result.get("v",{});var islands: Dictionary=result.get("islands",{});var currents: Dictionary=result.get("i",{})
	var roots:={}
	var connections: Array=Board.wires_only(board)+wires
	for wire in connections:
		for pin in wire:roots.get_or_add(str(pin),str(pin))
	for part in parts:
		roots.get_or_add(str(part.get("a","")),str(part.get("a","")));roots.get_or_add(str(part.get("b","")),str(part.get("b","")))
	for wire in connections:
		if wire.size()==2:roots[Solver.root(roots,str(wire[0]))]=Solver.root(roots,str(wire[1]))
	var output: Array=[]
	var patterns: Array=[[0,1,2,3,4,5],[1,2],[0,1,3,4,6],[0,1,2,3,6],[1,2,5,6],[0,2,3,5,6],[0,2,3,4,5,6],[0,1,2],[0,1,2,3,4,5,6],[0,1,2,3,5,6]]
	for chip in board.get("parts",[]):
		if chip.get("type","")!="ls47" or Board.pins(chip).size()!=16:continue
		var nodes: Array=Board.pins(chip).map(func(h):return "board/"+Board.node(str(h),int(board.rows)))
		var state: Dictionary=states.get("board/"+str(chip.id),{})
		if not state.get("powered",false) or not volts.has(nodes[7]) or not volts.has(nodes[15]):continue
		var ground:=float(volts[nodes[7]]);var supply:=float(volts[nodes[15]])-ground
		if supply<4.5 or supply>5.5 or not islands.has(nodes[7]) or islands.get(nodes[7])!=islands.get(nodes[15]):continue
		var levels: Array=[]
		for pin in [6,0,1,5,2,3,4]:
			if not volts.has(nodes[pin]) or islands.get(nodes[pin])!=islands.get(nodes[7]):break
			var value: float=(float(volts[nodes[pin]])-ground)/supply
			if not is_finite(value) or (value>.3 and value<.7):break
			levels.append(int(value>=.7))
		if levels.size()!=7 or levels.slice(4)!=[1,1,1]:continue
		var digit: int=levels[0]+2*levels[1]+4*levels[2]+8*levels[3]
		if digit>=10:continue
		for display in board.parts:
			if display.get("type","")!="seven_segment_ca" or Board.pins(display).size()!=9:continue
			var dn: Array=Board.pins(display).map(func(h):return "board/"+Board.node(str(h),int(board.rows)))
			if Solver.root(roots,dn[8])!=Solver.root(roots,nodes[15]):continue
			var valid:=true
			for segment in 7:
				var source:=Solver.root(roots,nodes[[12,11,10,9,8,14,13][segment]])
				var sink:=Solver.root(roots,dn[segment])
				if source==sink:valid=false;break
				var resistor:=false
				for part in parts:
					if part.get("kind","")!="R" or float(part.get("value",0))<100.0 or float(part.get("value",0))>100000.0:continue
					var a:=Solver.root(roots,str(part.a));var b:=Solver.root(roots,str(part.b))
					if (a==source and b==sink) or (a==sink and b==source):resistor=true;break
				var id:="board/"+str(display.id)+"/"+str(segment)
				if not resistor or not currents.has(id):valid=false;break
				var current:=float(currents[id]);var lit: bool=segment in patterns[digit]
				if not is_finite(current) or current<-.000001 or current>.04 or (lit and current<.00005) or (not lit and absf(current)>.00005):valid=false;break
			output.append({"gate":str(chip.id)+":"+str(display.id),"row":digit,"required":10,"correct":valid})
	return output

static func signature(board: Dictionary, wires: Array) -> String:
	var components: Array=[]
	for part in board.get("parts",[]):
		components.append([str(part.get("id","")),str(part.get("type","")),Board.pins(part)])
	return var_to_bytes([board.get("rows",30),components,board.get("wires",[]),board.get("ports",[]),wires]).hex_encode().sha256_text()

static func samples(board: Dictionary, result: Dictionary) -> Array:
	if not result.get("ok",false):return []
	var volts: Dictionary=result.get("v",{})
	var islands: Dictionary=result.get("islands",{})
	var samples_out: Array=[]
	for part in board.get("parts",[]):
		var model: Dictionary=Catalog.simulation_entry(str(part.get("type","")))
		if model.get("kind","")!="logic":continue
		var pins: Array=Board.pins(part)
		if pins.size()!=14:continue
		var nodes: Array=pins.map(func(h):return "board/"+Board.node(str(h),int(board.get("rows",30))))
		if not volts.has(nodes[6]) or not volts.has(nodes[13]) or not islands.has(nodes[6]) or islands.get(nodes[6])!=islands.get(nodes[13]):continue
		var ground := float(volts[nodes[6]])
		var supply := float(volts[nodes[13]])-ground
		if not is_finite(supply) or supply<2.0 or supply>6.0:continue
		var gates: Array=[[0,1,2],[3,4,5],[8,9,7],[11,12,10]]
		if model.gate=="NOT":gates=[[0,0,1],[2,2,3],[4,4,5],[8,8,7],[10,10,9],[12,12,11]]
		for index in gates.size():
			var gate: Array=gates[index]
			var levels: Array=[]
			for pin in gate:
				var node: String=nodes[pin]
				if not volts.has(node) or islands.get(node)!=islands.get(nodes[6]):break
				var level := (float(volts[node])-ground)/supply
				if not is_finite(level) or (level>.3 and level<.7):break
				levels.append(level>=.7)
			if levels.size()!=3:continue
			var a: bool=levels[0];var b: bool=levels[1];var expected := false
			match str(model.gate):
				"AND":expected=a and b
				"NAND":expected=not (a and b)
				"OR":expected=a or b
				"XOR":expected=a!=b
				"NOT":expected=not a
				_:continue
			var row := int(a) if model.gate=="NOT" else int(a)*2+int(b)
			samples_out.append({"gate":str(part.id)+":"+str(index),"kind":str(model.gate),"row":row,"correct":levels[2]==expected,"required":2 if model.gate=="NOT" else 4,"a":a,"b":b,"output":levels[2],"nodes":[nodes[gate[0]],nodes[gate[1]],nodes[gate[2]]]})
	return samples_out

static func combinational_samples(board: Dictionary, wires: Array, result: Dictionary, week: int) -> Array:
	var gates:=samples(board,result);var roots:={}
	for gate in gates:
		for node in gate.nodes:roots.get_or_add(node,node)
	var connections: Array=Board.wires_only(board)+wires
	for wire in connections:
		for node in wire:roots.get_or_add(str(node),str(node))
	for wire in connections:
		if wire.size()==2:roots[Solver.root(roots,str(wire[0]))]=Solver.root(roots,str(wire[1]))
	var output: Array=[]
	for and_gate in gates:
		if and_gate.kind!="AND" or not and_gate.correct:continue
		for or_gate in gates:
			if or_gate.kind!="OR" or not or_gate.correct:continue
			if week==5:
				for input in 2:
					if Solver.root(roots,and_gate.nodes[2])!=Solver.root(roots,or_gate.nodes[input]):continue
					var roots_in: Array=[Solver.root(roots,and_gate.nodes[0]),Solver.root(roots,and_gate.nodes[1]),Solver.root(roots,or_gate.nodes[1-input])]
					if roots_in[0]==roots_in[1] or roots_in[0]==roots_in[2] or roots_in[1]==roots_in[2]:continue
					var c: bool=or_gate.a if input==1 else or_gate.b
					var row:=int(and_gate.a)*4+int(and_gate.b)*2+int(c)
					output.append({"gate":and_gate.gate+":"+or_gate.gate+":"+str(input),"row":row,"required":8,"correct":or_gate.output==((and_gate.a and and_gate.b) or c)})
			elif week==4:
				for input in 2:
					if Solver.root(roots,or_gate.nodes[2])!=Solver.root(roots,and_gate.nodes[input]):continue
					for not_gate in gates:
						if not_gate.kind!="NOT" or not not_gate.correct:continue
						for or_input in 2:
							if Solver.root(roots,not_gate.nodes[2])!=Solver.root(roots,or_gate.nodes[or_input]) or Solver.root(roots,not_gate.nodes[0])!=Solver.root(roots,or_gate.nodes[1-or_input]):continue
							var a_root:=Solver.root(roots,and_gate.nodes[1-input]);var b_root:=Solver.root(roots,not_gate.nodes[0])
							if a_root==b_root:continue
							var a: bool=and_gate.a if input==1 else and_gate.b;var b: bool=not_gate.a
							output.append({"gate":and_gate.gate+":"+or_gate.gate+":"+not_gate.gate,"row":int(a)*2+int(b),"required":4,"correct":and_gate.output==a})
	return output

static func binary_samples(board: Dictionary, result: Dictionary) -> Array:
	if not result.get("ok",false):return []
	var volts: Dictionary=result.get("v",{});var islands: Dictionary=result.get("islands",{});var found: Array=[]
	for part in board.get("parts",[]):
		if str(part.get("type",""))!="hc08" or Board.pins(part).size()!=14:continue
		var nodes: Array=Board.pins(part).map(func(h):return "board/"+Board.node(str(h),int(board.rows)))
		if not volts.has(nodes[6]) or not volts.has(nodes[13]) or not islands.has(nodes[6]) or islands.get(nodes[6])!=islands.get(nodes[13]):continue
		var ground:=float(volts[nodes[6]]);var supply:=float(volts[nodes[13]])-ground
		if supply<2.0 or supply>6.0:continue
		var value:=0;var valid:=true
		for bit in 4:
			var node: String=nodes[[0,1,3,4][bit]]
			if not volts.has(node) or islands.get(node)!=islands.get(nodes[6]):valid=false;break
			var level: float=(float(volts[node])-ground)/supply
			if not is_finite(level) or (level>.3 and level<.7):valid=false;break
			if level>=.7:value|=1<<bit
		if valid:found.append({"gate":str(part.id),"row":value,"required":16,"correct":true})
	return found

static func flip_samples(board: Dictionary, result: Dictionary, states: Dictionary) -> Array:
	if not result.get("ok",false):return []
	var volts: Dictionary=result.get("v",{});var islands: Dictionary=result.get("islands",{})
	var output: Array=[]
	for part in board.get("parts",[]):
		if str(part.get("type",""))!="flip74":continue
		var pins: Array=Board.pins(part)
		if pins.size()!=14:continue
		var nodes: Array=pins.map(func(h):return "board/"+Board.node(str(h),int(board.get("rows",30))))
		var state: Dictionary=states.get("board/"+str(part.id),{})
		if not state.get("powered",false) or not volts.has(nodes[6]) or not volts.has(nodes[13]) or not islands.has(nodes[6]) or islands.get(nodes[6])!=islands.get(nodes[13]):continue
		var ground:=float(volts[nodes[6]]);var supply:=float(volts[nodes[13]])-ground
		if not is_finite(supply) or supply<2.0 or supply>6.0:continue
		for half in [["a",0,1,2,3,4],["b",12,11,10,9,8]]:
			var levels: Array=[]
			for pin in half.slice(1):
				var node: String=nodes[pin]
				if not volts.has(node) or islands.get(node)!=islands.get(nodes[6]):break
				var level: float=(float(volts[node])-ground)/supply
				if not is_finite(level) or (level>.3 and level<.7):break
				levels.append(level>=.7)
			if levels.size()!=5 or not levels[0] or not levels[3] or not state.has(half[0]):continue
			output.append({"gate":str(part.id)+":"+str(half[0]),"data":levels[1],"clock":levels[2],"output":levels[4],"state":bool(state[half[0]])})
	return output
