extends RefCounted
# Bounded educational behavioral models. Logic updates once per simulation step.
static func expand(model: Dictionary,id: String,nodes: Array,state: Dictionary,voltages: Dictionary={},runtime: Dictionary={}) -> Array:
	if model.get("kind","")=="native_controller":
		var program_state := state.duplicate(true);program_state.merge(runtime.get("__programs",{}).get(id,{}),true)
		# Missing disconnected header nodes are relative to this board ground. An
		# absolute zero fallback can invent VIN on an isolated, shifted-reference island.
		var referenced := voltages.duplicate()
		var mapped: Array=preload("res://scripts/firmware_backends/native_boards.gd").logical_nodes(str(model.board),id,nodes)
		var zero := float(voltages.get(mapped[1],0)) if mapped.size()>1 else 0.
		for pin in nodes:
			if not referenced.has(pin):referenced[pin]=zero
		return preload("res://scripts/firmware_backends/native_boards.gd").expand(model,id,nodes,program_state,referenced,runtime)
	if preload("res://scripts/io_devices/catalog.gd").supports(str(model.get("kind",""))):return preload("res://scripts/io_devices/devices.gd").expand(model,id,nodes,state,voltages,runtime)
	if model.get("kind","")=="worker_model":return preload("res://scripts/component_models/library.gd").expand(model,id,nodes,state,voltages,runtime)
	state=state.duplicate(true);state.merge(runtime.get("__inputs",{}).get(id,{}),true);state.merge(runtime.get("__programs",{}).get(id,{}),true)
	var out: Array=[]
	if model.kind in ["timer555","flip74","spi_display","shift595"]:return preload("res://scripts/stateful_devices.gd").expand(model.kind,id,nodes,runtime.get(id,{}))
	match str(model.kind):
		"portable_source":
			var voltage := preload("res://scripts/electronics/portable_sources.gd").voltage(model,state,float(runtime.get("__simulation_time",0.0)))
			out.append({"id":id,"kind":"V","a":nodes[0],"b":nodes[1],"value":voltage,"resistance":model.resistance})
		"polar_cap":
			out.append({"id":id,"kind":"C","a":nodes[0],"b":nodes[1],"value":model.value})
			out.append({"id":id+"/reverse","kind":"D","a":nodes[1],"b":nodes[0],"vf":.8,"ron":33.0})
		"variable_cap","variable_inductor":
			var setting := clampf(float(state.get("setting",.5)),0,1)
			out.append({"id":id,"kind":"C" if model.kind=="variable_cap" else "L","a":nodes[0],"b":nodes[1],"value":lerpf(float(model.minimum),float(model.value),setting)})
		"signal_transformer":
			out.append({"id":id+"/primary","kind":"L","a":nodes[0],"b":nodes[1],"value":.2,"resistance":1.2,"coupled":id+"/secondary","mutual":.097})
			out.append({"id":id+"/secondary","kind":"L","a":nodes[2],"b":nodes[3],"value":.05,"resistance":.32,"coupled":id+"/primary","mutual":.097})
		"photodiode","solar_panel":
			var illumination := clampf(float(state.get("setting",.65)),0,1)
			out.append({"id":id,"kind":"I","a":nodes[1],"b":nodes[0],"value":float(model.value)*illumination})
			out.append({"id":id+"/junction","kind":"D","a":nodes[0],"b":nodes[1],"vf":2.0 if model.kind=="solar_panel" else .61,"ron":3.0})
		"opamp":
			out.append({"id":id,"kind":"E","a":nodes[4],"b":nodes[3],"cp":nodes[0],"cn":nodes[1],"high":nodes[2],"gain":100000.,"resistance":50.})
			for pin in 3:out.append({"id":id+"/bias"+str(pin),"kind":"R","a":nodes[pin],"b":nodes[3],"value":1e7})
		"bjt":
			var c: String=nodes[0];var b: String=nodes[1];var e: String=nodes[2]
			var pnp: bool=model.get("polarity","NPN")=="PNP"
			out.append({"id":id+"/be","kind":"D","a":e if pnp else b,"b":b if pnp else e,"vf":.65,"ron":2.})
			out.append({"id":id+"/bc","kind":"D","a":c if pnp else b,"b":b if pnp else c,"vf":.65,"ron":2.})
			out.append({"id":id+"/forward","kind":"F","a":b if pnp else c,"b":c if pnp else b,"control":id+"/be","gain":.99})
			out.append({"id":id+"/reverse","kind":"F","a":b if pnp else e,"b":e if pnp else b,"control":id+"/bc","gain":.5})
		"speaker":out.append({"id":id,"kind":"R","a":nodes[0],"b":nodes[1],"value":8.,"audio":true})
		"buzzer":out.append({"id":id,"kind":"R","a":nodes[0],"b":nodes[1],"value":1000.})
		"controller":
			out.append({"id":id,"kind":"controller","nodes":nodes,"source":str(state.get("firmware",preload("res://scripts/firmware_runtime.gd").TEMPLATE)),"run":bool(state.get("run",true))})
			out.append({"id":id+"/power","kind":"R","a":nodes[0],"b":nodes[1],"value":1000.0})
			var state_now: Dictionary=runtime.get(id,{})
			for pin in preload("res://scripts/firmware_runtime.gd").PINS:
				var index: int=preload("res://scripts/firmware_runtime.gd").PINS[pin]
				var driving: bool=state_now.get("powered",false) and state_now.get("modes",{}).get(pin,"in")=="out" and state_now.get("outputs",{}).has(pin)
				var duty := float(state_now.get("outputs",{}).get(pin,0))
				var high := fposmod(float(state_now.get("time",0))*50.0,1.0)<duty
				out.append({"id":id+"/"+pin,"kind":"R","a":nodes[index],"b":nodes[0] if high and driving else nodes[1],"value":40.0 if driving else 1e12})
		"pot":
			var fraction := clampf(float(state.get("setting",.5)),0,1)
			out.append({"id":id+"/upper","kind":"R","a":nodes[0],"b":nodes[1],"value":maxf(.01,float(model.value)*fraction)})
			out.append({"id":id+"/lower","kind":"R","a":nodes[1],"b":nodes[2],"value":maxf(.01,float(model.value)*(1-fraction))})
		"seven_segment":
			for i in 8:out.append({"id":id+"/"+str(i),"kind":"LED","a":nodes[i],"b":nodes[8],"vf":1.8,"ron":10})
		"logic":
			var ground: String=nodes[6];var supply: String=nodes[13]
			var zero := float(voltages.get(ground,0));var vcc := float(voltages.get(supply,0))-zero
			out.append({"id":id+"/power","kind":"R","a":supply,"b":ground,"value":1e6})
			var gates: Array=[[0,1,2],[3,4,5],[8,9,7],[11,12,10]]
			if model.gate=="NOT":gates=[[0,0,1],[2,2,3],[4,4,5],[8,8,7],[10,10,9],[12,12,11]]
			for i in gates.size():
				var gate: Array=gates[i];var va := float(voltages.get(nodes[gate[0]],0))-zero;var vb := float(voltages.get(nodes[gate[1]],0))-zero
				for input_pin in ([gate[0]] if gate[0]==gate[1] else [gate[0],gate[1]]):out.append({"id":id+"/input"+str(i)+"/"+str(input_pin),"kind":"R","a":nodes[input_pin],"b":ground,"value":1e9})
				var high_a := va>=.7*vcc;var high_b := vb>=.7*vcc;var high := false
				match str(model.gate):
					"NAND":high=not(high_a and high_b)
					"AND":high=high_a and high_b
					"OR":high=high_a or high_b
					"XOR":high=high_a!=high_b
					"NOT":high=not high_a
				var valid := vcc>=2 and vcc<=6 and (va<=.3*vcc or va>=.7*vcc) and (vb<=.3*vcc or vb>=.7*vcc)
				out.append({"id":id+"/out"+str(i),"kind":"R","a":nodes[gate[2]],"b":supply if high else ground,"value":40.0 if valid else 1e12})
		_:
			var copy := model.duplicate(true);copy.id=id;copy.a=nodes[0];copy.b=nodes[1]
			if copy.kind=="R" and model.get("physical_resistor",false):
				copy.nominal_value=model.value
				var measured: Dictionary=runtime.get("__resistors",{}).get(id,{})
				if preload("res://scripts/physical_resistors.gd").valid(measured) and measured.nominal==model.value and measured.tolerance==model.resistance_tolerance and measured.watts==model.power_rating_w:copy.value=measured.actual
			if copy.kind in ["button","toggle"]:copy.kind="R";copy.value=.01 if state.get("pressed",false) else 1e12
			out.append(copy)
	return out
