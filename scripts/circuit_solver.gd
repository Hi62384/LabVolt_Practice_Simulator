extends RefCounted
## Training-grade, steady-state, sinusoidal 60 Hz nodal solver.
## All voltage phasors are RMS. Real and imaginary components use Vector2.
## It is NOT a safety-certified circuit emulator.

var frequency := 60.0
const Network = preload("res://scripts/ac_network.gd")
const Motor = preload("res://scripts/induction_motor.gd")
const LINE_NEUTRAL_V := 120.0
const TWO_PI := 6.283185307179586
const Catalog = preload("res://scripts/equipment_catalog.gd")
const Aux = preload("res://scripts/ac_auxiliary.gd")
const ProtectiveEarth = preload("res://scripts/electrical_safety/protective_earth.gd")
var protective_earth_profile: Dictionary = {}
var daq_settings: Dictionary = {}
var igbt_damping := false
const SHUNT_OHMS := Catalog.CURRENT_COIL_OHMS

func _mul(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)

func _div(a: Vector2, b: Vector2) -> Vector2:
	var den := b.x * b.x + b.y * b.y
	if den < 1.0e-25:
		return Vector2.ZERO
	return Vector2((a.x * b.x + a.y * b.y) / den, (a.y * b.x - a.x * b.y) / den)

func _conj(a: Vector2) -> Vector2:
	return Vector2(a.x, -a.y)

func _root(id: String, parent: Dictionary) -> String:
	var node := id
	while parent.get(node, node) != node:
		node = str(parent[node])
	return node

func _join(a: String, b: String, parent: Dictionary) -> void:
	if not parent.has(a) or not parent.has(b):
		return
	var ra := _root(a, parent)
	var rb := _root(b, parent)
	if ra != rb:
		parent[rb] = ra

func _blank() -> Dictionary:
	return {
		"voltages": {}, "ammeters": [0.0, 0.0, 0.0], "ammeter_ranges": [0.5,0.5,0.5],
		"voltmeters": [0.0, 0.0, 0.0], "voltmeter_ranges": [100.0,100.0,100.0], "wattmeters": [0.0, 0.0],
		"p": 0.0, "q": 0.0, "s": 0.0, "pf": 1.0,
		"motor_rpm": 0.0, "fault": "", "warning": "", "bank_currents": {},
		"bank_voltages": {}, "daq_v": [Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO], "daq_i": [Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]
	}

func solve(terminals: Array, leads: Array, switches: Dictionary, powered: bool, variable_level: float, dynamometer_load: float = 0.0, motor_slip := 0.05, iteration := 0) -> Dictionary:
	var ac := _solve_domain(terminals, leads, switches, powered, variable_level, dynamometer_load, motor_slip, iteration, false, {})
	if not powered or not ac.fault.is_empty():
		ac.merge(Aux.readouts({}, {}))
		return ac
	var ports := {}
	for lead in leads:
		ports[lead.a] = true
		ports[lead.b] = true
	var dc := {}
	var gate_state := {}
	if ports.keys().any(func(port: String): return port.begins_with("DC_") or port.begins_with("DAQ_AO") or port.begins_with("DAQ_DO") or port.begins_with("IGBT_") and port != "IGBT_EARTH"):
		dc = _solve_domain(terminals, leads, switches, true, variable_level, 0., motor_slip, 0, true, {})
		gate_state = Aux.switch_state(dc.voltages)
		if gate_state.legs.any(func(rail: int): return rail != 0) and dc.fault.is_empty():
			dc = _solve_domain(terminals, leads, switches, true, variable_level, 0., motor_slip, 0, true, gate_state)
			ac = _solve_domain(terminals, leads, switches, true, variable_level, dynamometer_load, motor_slip, iteration, false, gate_state)
		ac.dc_voltages = dc.voltages
		ac.daq_dc_v = dc.daq_v
		ac.daq_dc_i = dc.daq_i
		ac.igbt = gate_state
		if not dc.fault.is_empty():
			ac.fault = dc.fault
		for i in 3:
			ac.ammeters[i] = Vector2(ac.ammeters[i], dc.ammeters[i]).length()
			ac.voltmeters[i] = Vector2(ac.voltmeters[i], dc.voltmeters[i]).length()
		for i in 2:
			ac.wattmeters[i] += dc.wattmeters[i]
		for group in dc.bank_currents:
			ac.bank_currents[group] = Vector2(ac.bank_currents.get(group, 0.), dc.bank_currents[group]).length()
			ac.bank_voltages[group] = Vector2(ac.bank_voltages.get(group, 0.), dc.bank_voltages[group]).length()
		ac.p += dc.p
		ac.s = Vector2(ac.p, ac.q).length()
		ac.pf = ac.p / ac.s if ac.s > .01 else 1.0
	ac.merge(Aux.readouts(ac.voltages, dc.get("voltages", {})), true)
	ac.outlet_volts = {}
	for source in Aux.supplies(variable_level):
		if not ports.has(source.a) and not ports.has(source.b):
			continue
		var domain: Dictionary = dc.get("voltages", {}) if source.dc else ac.voltages
		var positive: Vector2 = domain.get(source.a, Vector2.ZERO)
		var negative: Vector2 = domain.get(source.b, Vector2.ZERO)
		ac.outlet_volts[source.a] = (positive - negative).length()
	return ac

func _solve_domain(terminals: Array, leads: Array, switches: Dictionary, powered: bool, variable_level: float, dynamometer_load: float, motor_slip: float, iteration: int, dc: bool, gate_state: Dictionary) -> Dictionary:
	var output := _blank()
	var safety_split := {"ok":true,"ideal_leads":leads,"pe_leads":[]}
	if not protective_earth_profile.is_empty():
		safety_split=ProtectiveEarth.prepare_leads(terminals,leads,protective_earth_profile)
		if not safety_split.ok:
			output.fault="PE MODEL CONFIG: "+str(safety_split.error)
			return output
	var parent: Dictionary = {}
	for id in terminals:
		parent[str(id)] = str(id)
	# Physical plug leads behave as ideal conducting wires. Multiple leads can share a socket.
	for lead in safety_split.ideal_leads:
		_join(str(lead["a"]), str(lead["b"]), parent)
	for i in range(2):
		_join("W%d_IN"%i,"W%d_VP"%i,parent)
	# The two neutral posts on the source are common inside this simplified supply.
	_join("P_N", "PV_N", parent)
	if not powered:
		if not protective_earth_profile.is_empty():
			var off_model := ProtectiveEarth.compile([],[],parent,protective_earth_profile,safety_split.pe_leads)
			if not off_model.ok:output.fault="PE MODEL CONFIG: "+str(off_model.error)
			else:output.safety=ProtectiveEarth.public_evidence(ProtectiveEarth.evidence(off_model,{},false))
		for id in terminals:
			output["voltages"][str(id)] = Vector2.ZERO
		return output

	# 120/208 V, 60 Hz three-phase source. A,B,C have 0,-120,+120 deg phases.
	var level := clampf(variable_level, 0.0, 1.0)
	var base_sources: Array[Dictionary] = [
		{"id":"P_A", "v":Vector2(LINE_NEUTRAL_V, 0.0)},
		{"id":"P_B", "v":Vector2(-60.0, -103.92304845)},
		{"id":"P_C", "v":Vector2(-60.0, 103.92304845)},
		{"id":"P_N", "v":Vector2.ZERO},
		{"id":"PV_A", "v":Vector2(LINE_NEUTRAL_V * level, 0.0)},
		{"id":"PV_B", "v":Vector2(-60.0 * level, -103.92304845 * level)},
		{"id":"PV_C", "v":Vector2(-60.0 * level, 103.92304845 * level)},
		{"id":"PV_N", "v":Vector2.ZERO}
	]
	var fixed: Dictionary = {}
	var fixed_names: Dictionary = {}
	for source in base_sources:
		var source_id: String = source["id"]
		if not parent.has(source_id):
			continue
		var root := _root(source_id, parent)
		var v: Vector2 = Vector2.ZERO if dc else source["v"]
		if fixed.has(root):
			if (fixed[root] as Vector2).distance_to(v) > 0.00001:
				output["fault"] = "SOURCE SHORT: %s tied to %s. Breaker tripped." % [str(fixed_names[root]), source_id]
				return output
		else:
			fixed[root] = v
			fixed_names[root] = source_id

	# Each LabVolt load bank has three PARALLEL components, selected by three toggles.
	# 120 V variant values, documented in the project readme.
	var components: Array[Dictionary] = []
	for kind in ["R", "L", "C"]:
		var active: Array = switches.get(kind, [false, false, false, false, false, false, false, false, false])
		for bank in range(3):
			var y := Vector2.ZERO
			for element in range(3):
				if bool(active[bank * 3 + element]):
					if kind == "R":
						var resistances: Array = Catalog.LOADS.R.values
						y += Vector2(1.0 / resistances[element], 0.0)
					elif kind == "L" and dc:
						y += Vector2(1.0 / 2.0, 0.0)
					elif kind == "L":
						var inductances: Array = Catalog.LOADS.L.values
						y += Vector2(0.0, -1.0 / (TWO_PI * frequency * inductances[element]))
					elif not dc:
						var caps: Array = Catalog.LOADS.C.values
						y += Vector2(0.0, TWO_PI * frequency * caps[element])
			if y.length_squared() > 1.0e-17:
				components.append({"a":"%s%d_P" % [kind,bank], "b":"%s%d_N" % [kind,bank], "y":y, "group":"%s%d" % [kind,bank], "count_power":true})

	# Real ammeters and wattmeter current coils should be connected in SERIES.
	# A low-value shunt is used so current can be measured from its voltage drop.
	for i in range(3):
		components.append({"a":"AM%d_IN" % i, "b":"AM%d_OUT" % i, "y":Vector2(1.0 / SHUNT_OHMS, 0), "group":"AM%d" % i, "count_power":false})
	for i in range(2):
		components.append({"a":"W%d_IN" % i, "b":"W%d_OUT" % i, "y":Vector2(1.0 / SHUNT_OHMS, 0), "group":"W%d" % i, "count_power":false})

	for i in range(3):
		for tap in ["2_5","8","25"]:
			if parent.has("AM%d_%s"%[i,tap]):
				components.append({"a":"AM%d_%s"%[i,tap],"b":"AM%d_OUT"%i,"y":Vector2(1.0/SHUNT_OHMS,0),"group":"TAP%d_%s"%[i,tap],"count_power":false})
	# A documented illustrative induction equivalent; solve mechanical equilibrium
	# against the actual three winding voltages, then restamp the AC network.
	var motor_y := Vector2(.1, 0.) if dc else _div(Vector2(1,0), Motor.impedance(frequency,motor_slip))
	for i in range(3):
		components.append({"a":"M%d" % (i+1), "b":"M%d" % (i+4), "y":motor_y, "group":"MOTOR%d" % i, "count_power":true})

	# Finite instrument loading, explicitly modeled as an approximation.
	for i in range(3):
		for tap in ["150", "300"]:
			components.append({"a":"V%d_%s" % [i,tap], "b":"V%d_COM" % i, "y":Vector2(1.0/(100000.0 if tap == "150" else 250000.0),0), "group":"VM%d_%s" % [i,tap], "count_power":false})
	for i in range(2):
		components.append({"a":"W%d_VP" % i, "b":"W%d_VN" % i, "y":Vector2(1.0/150000.0,0), "group":"VC%d" % i, "count_power":false})
	for i in range(4):
		components.append({"a":"DAQ_E%d_P"%i,"b":"DAQ_E%d_N"%i,"y":Vector2(.000001,0),"group":"DAQV%d"%i,"count_power":false})
		for tap in ["4","40"]:
			components.append({"a":"DAQ_I%d_%s"%[i,tap],"b":"DAQ_I%d_N"%i,"y":Vector2(1.0/SHUNT_OHMS,0),"group":"DAQI%d_%s"%[i,tap],"count_power":false})
	# A multi-tap ideal transformer: every winding shares one core. No losses modeled.
	var transformers: Array=[]
	if parent.has("TX_1") and not dc:
		components.append({"a":"TX_1","b":"TX_2","y":Vector2(.0001,0),"group":"TXMAG","count_power":false})
		for winding in [[3,7,104.0],[7,8,76.0],[8,4,28.0],[5,9,60.0],[9,6,60.0]]:
			transformers.append({"a":_root("TX_%d"%winding[0],parent),"b":_root("TX_%d"%winding[1],parent),"c":_root("TX_1",parent),"d":_root("TX_2",parent),"ratio":winding[2]/120.0,"id":"TX%d"%winding[0],"type":"transformer","value":Vector2.ZERO})
	# Exclude unused isolated sockets from the dense solve.
	var active := fixed.duplicate()
	for lead in leads:
		for port in [str(lead.a),str(lead.b)]:
			if parent.has(port):active[_root(port,parent)]=true
	for part in Aux.impedances(igbt_damping) + Aux.switch_impedances(gate_state):
		components.append({"a":part.a,"b":part.b,"group":part.id,"y":Vector2(1.0 / part.ohms, 0.),"count_power":false})
	var aux_sources := []
	for source in Aux.supplies(level) + Aux.daq_outputs(daq_settings):
		if not parent.has(source.a) or not parent.has(source.b):
			continue
		var a := _root(source.a, parent)
		var b := _root(source.b, parent)
		if not active.has(a) and not active.has(b):
			continue
		var internal: String = "@source/" + source.a
		aux_sources.append({"a":internal, "b":b, "id":source.a, "type":"voltage", "value":Vector2(source.volts if dc == source.get("dc", true) else 0., 0.)})
		components.append({"a":internal,"b":source.a,"group":internal,"y":Vector2(1.0 / float(source.get("ohms", .05)), 0.),"count_power":false})
		parent[internal] = internal
		active[internal] = true
		active[a] = true
		active[b] = true
	for pass_index in range(8):
		for c in components:
			if parent.has(c.a) and parent.has(c.b):
				var a := _root(c.a,parent)
				var b := _root(c.b,parent)
				if active.has(a) or active.has(b):active[a]=true;active[b]=true
		for branch in transformers:
			if active.has(branch.a) or active.has(branch.b) or active.has(branch.c) or active.has(branch.d):
				for port in [branch.a,branch.b,branch.c,branch.d]:active[port]=true
	var nodes: Array = ["0"]
	for id in terminals:
		var root := _root(str(id),parent)
		if active.has(root) and not nodes.has(root):
			nodes.append(root)
	var branches: Array = []
	for root in fixed:
		branches.append({"a":root,"b":"0","id":"source_"+str(root),"type":"voltage","value":fixed[root]})
	for source in aux_sources:
		nodes.append(source.a)
		branches.append(source)
	for c in components:
		if parent.has(c.a) and parent.has(c.b) and active.has(_root(c.a,parent)) and active.has(_root(c.b,parent)):
			branches.append({"a":_root(c.a,parent),"b":_root(c.b,parent),"id":c.group,"type":"impedance","value":_div(Vector2(1,0),c.y)})
	for branch in transformers:
		if active.has(branch.a):branches.append(branch)
	var safety_model := {"ok":true,"enabled":false}
	if not protective_earth_profile.is_empty():
		safety_model=ProtectiveEarth.compile(nodes,branches,parent,protective_earth_profile,safety_split.pe_leads)
		if not safety_model.ok:
			output.fault="PE MODEL CONFIG: "+str(safety_model.error)
			return output
		nodes=safety_model.nodes;branches=safety_model.branches
	var result: Dictionary = Network.new().solve(nodes,branches)
	if safety_model.enabled:
		var safety_limits := {}
		for root in fixed:safety_limits["source_"+str(root)]=Catalog.VARIABLE_LIMIT_AMPS if str(fixed_names[root]).begins_with("PV_") else Catalog.FIXED_LIMIT_AMPS
		output.safety=ProtectiveEarth.public_evidence(ProtectiveEarth.evidence(safety_model,result,true,safety_limits))
		if not output.safety.get("warnings",[]).is_empty():output.warning=" ".join(output.safety.warnings)
	if result.fault != "":
		output.fault = result.fault
		return output
	for source in Aux.supplies(level):
		var current: Vector2 = result.currents.get(source.a, Vector2.ZERO)
		if current.length() > float(source.amps):
			output.fault = "SUPPLY OVERCURRENT: %s exceeds %.0f A. Breaker tripped." % [source.a, source.amps]
	if not result.floating_references.is_empty():
		output.warning = (output.warning+" " if output.warning!="" else "")+"Disconnected islands use local references; absolute voltage to earth is undefined."
	for id in terminals:
		output.voltages[str(id)] = result.voltages.get(_root(str(id),parent),Vector2.ZERO)
	output["source_currents"] = {}
	output["source_phasors"] = {}
	for root in fixed:
		var amps: float = result.currents["source_"+str(root)].length()
		output.source_currents[fixed_names[root]] = amps
		output.source_phasors[fixed_names[root]]=result.currents["source_"+str(root)]
		var limit: float = Catalog.VARIABLE_LIMIT_AMPS if str(fixed_names[root]).begins_with("PV_") else Catalog.FIXED_LIMIT_AMPS
		if amps > limit:
			output.fault = "SUPPLY OVERCURRENT: %.2f A exceeds %.0f A simulated limit. Breaker tripped." % [amps,limit]

	for component in components:
		var a_id := str(component["a"])
		var b_id := str(component["b"])
		var delta: Vector2 = output["voltages"].get(a_id, Vector2.ZERO) - output["voltages"].get(b_id, Vector2.ZERO)
		var current: Vector2 = result.currents.get(str(component["group"]), Vector2.ZERO)
		var group := str(component["group"])
		if group.begins_with("AM"):
			output["ammeters"][int(group.substr(2))] = current.length()
		elif group.begins_with("W"):
			var meter: int = int(group.substr(1))
			var vcoil: Vector2 = output["voltages"].get("W%d_VP" % meter, Vector2.ZERO) - output["voltages"].get("W%d_VN" % meter, Vector2.ZERO)
			output["wattmeters"][meter] = _mul(vcoil, _conj(current)).x
		elif bool(component["count_power"]):
			var apparent: Vector2 = _mul(delta, _conj(current))
			output["p"] += apparent.x
			output["q"] += apparent.y
			if group.begins_with("R") or group.begins_with("L") or group.begins_with("C"):
				output["bank_currents"][group] = current.length()
				output["bank_voltages"][group] = delta.length()
				# The selected training load parts are 120 V nominal.
				if delta.length() > Catalog.LOAD_TRIP_VOLTS:
					output["fault"] = "OVER-VOLTAGE: load %s has %.1f V (120 V nominal). Breaker tripped." % [group, delta.length()]
		if (group.begins_with("AM") or group.begins_with("W")) and current.length() > 5.0:
			output["fault"] = "OVER-CURRENT: %s reads %.1f A. Breaker tripped." % [group,current.length()]

	for i in range(3):
		var selected: String = "V%d_150" % i
		var alternate: String = "V%d_300" % i
		var first_used := false
		var second_used := false
		for lead in leads:
			if lead["a"] == selected or lead["b"] == selected:
				first_used = true
			if lead["a"] == alternate or lead["b"] == alternate:
				second_used = true
		if not first_used and second_used:
			selected = alternate
			output["voltmeter_ranges"][i] = 250.0
		if first_used or second_used:
			var v_measure: Vector2 = output["voltages"].get(selected, Vector2.ZERO) - output["voltages"].get("V%d_COM" % i, Vector2.ZERO)
			output["voltmeters"][i] = v_measure.length()
	for i in range(3):
		for tap in ["2_5","8","25"]:
			var id := "AM%d_%s"%[i,tap]
			if leads.any(func(w): return w.a==id or w.b==id):
				output.ammeters[i] = result.currents.get("TAP%d_%s"%[i,tap],Vector2.ZERO).length()
				output.ammeter_ranges[i] = {"2_5":2.5,"8":8.0,"25":25.0}[tap]
	for i in range(4):
		output.daq_v[i]=output.voltages.get("DAQ_E%d_P"%i,Vector2.ZERO)-output.voltages.get("DAQ_E%d_N"%i,Vector2.ZERO)
		output.daq_i[i]=result.currents.get("DAQI%d_4"%i,Vector2.ZERO)+result.currents.get("DAQI%d_40"%i,Vector2.ZERO)
	if dc:
		return output
	output["s"] = sqrt(output["p"] * output["p"] + output["q"] * output["q"])
	if output["s"] > 0.01:
		output["pf"] = output["p"] / output["s"]

	var winding_volts: Array[Vector2] = []
	for i in range(3):
		winding_volts.append(output.voltages.get("M%d"%(i+1),Vector2.ZERO)-output.voltages.get("M%d"%(i+4),Vector2.ZERO))
	var minimum_voltage := minf(winding_volts[0].length(),minf(winding_volts[1].length(),winding_volts[2].length()))
	var maximum_voltage := maxf(winding_volts[0].length(),maxf(winding_volts[1].length(),winding_volts[2].length()))
	var excitation: Vector2 = output.voltages.get("DYN_0", Vector2.ZERO) - output.voltages.get("DYN_1", Vector2.ZERO)
	var load_fraction := clampf(excitation.length() / 120., 0., 1.)
	var operating: Dictionary = Motor.operating_point(minimum_voltage,frequency,dynamometer_load * load_fraction)
	output.dynamo_torque = dynamometer_load * load_fraction * 1.2
	if absf(motor_slip-float(operating.slip)) > .0001 and iteration<6:
		return _solve_domain(terminals,leads,switches,powered,variable_level,dynamometer_load,float(operating.slip),iteration+1,false,gate_state)
	var sequence: float = winding_volts[0].x*winding_volts[1].y-winding_volts[0].y*winding_volts[1].x
	var balanced := maximum_voltage>20 and (maximum_voltage-minimum_voltage)/maximum_voltage<.05 and (winding_volts[0]+winding_volts[1]+winding_volts[2]).length()<maximum_voltage*.1 and absf(sequence)>maximum_voltage*maximum_voltage*.5
	output.motor_rpm = float(operating.rpm)*(1 if sequence<0 else -1) if balanced else 0.0
	output["motor"] = operating
	output.motor["balanced"] = balanced
	var motor_power := 0.0
	for i in range(3):
		motor_power += _mul(winding_volts[i],_conj(result.currents.get("MOTOR%d"%i,Vector2.ZERO))).x
	output.motor["input_power"] = motor_power
	output.motor["efficiency"] = float(operating.shaft_power)/motor_power if motor_power>.01 and balanced else 0.0
	return output
