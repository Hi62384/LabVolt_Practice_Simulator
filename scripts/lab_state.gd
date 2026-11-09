extends RefCounted
## Authoritative laboratory domain. No scene or transport dependencies.
const Solver = preload("res://scripts/circuit_solver.gd")
var terminals: Array = []
var positions := {}
var cables: Array[Dictionary] = []
var switches := {}
var stored_cables := {}
var drawer_open := false
var powered := false
var level := 0.58
var frequency := 60.0
var dyn_load := 0.0
var supply_meter := 1
var dyn_measure := false
var dyn_measure_holders := {}
var igbt_damping := false
var daq_settings := {}
var last_action := "ui"
var revision := 0
var next_id := 1
var readings := {}
var checked := false
var safety_errors := 0
var mode := "Free Laboratory"
var task := 0
var seed_value := 1
var element := 0
var records := {}
var result := ""
var solver = Solver.new()
var protective_earth_profile: Dictionary = {}
var external_connections := 0
# Only the authoritative host's instructor/challenge controller may call this.
# Do not expose arbitrary profiles/faults through the client action RPC.
func configure_protective_earth(profile: Dictionary) -> Dictionary:
	if powered:return {"ok":false,"error":"De-energize before changing the teaching model"}
	if bool(profile.get("enabled",false)) and external_connections>0:return {"ok":false,"error":"Disconnect external bench leads before starting this isolated-bench earthing demonstration"}
	var check := preload("res://scripts/electrical_safety/profile.gd").validate(profile)
	if not check.ok:return check
	var split := preload("res://scripts/electrical_safety/protective_earth.gd").prepare_leads(terminals,completed(),profile)
	if not split.ok:return split
	protective_earth_profile=profile.duplicate(true)
	solver.protective_earth_profile=protective_earth_profile
	checked=false;revision+=1;recalculate()
	return {"ok":readings.get("fault","")=="","error":readings.get("fault","")}
# Host-only recovery state; never merge a client-supplied copy.
func protective_earth_recovery() -> Dictionary:return protective_earth_profile.duplicate(true)


func initialize(ids: Array, locations: Dictionary) -> void:
	terminals = ids.duplicate()
	positions = locations.duplicate()
	for kind in ["R","L","C"]:
		switches[kind] = [false,false,false,false,false,false,false,false,false]
	recalculate()

func completed() -> Array:
	return cables.filter(func(c): return c.a != "" and c.b != "")

func recalculate() -> void:
	solver.protective_earth_profile=protective_earth_profile
	solver.frequency = frequency
	solver.daq_settings = daq_settings
	solver.igbt_damping = igbt_damping
	readings = solver.solve(terminals,completed(),switches,powered,level,dyn_load)
	if powered and readings.fault != "":
		var fault: String = readings.fault
		var pre_trip_safety: Dictionary=readings.get("safety",{}).duplicate(true)
		powered = false
		readings = solver.solve(terminals,completed(),switches,false,level,dyn_load)
		readings.fault = fault
		if pre_trip_safety.get("enabled",false):
			pre_trip_safety.snapshot_kind="pre_trip";pre_trip_safety.power_removed=true
			readings.safety=pre_trip_safety
		checked = false

func snapshot() -> Dictionary:
	return {"stored_cables":stored_cables.duplicate(true),"last_action":last_action,"drawer_open":drawer_open,"cables":cables.duplicate(true),"switches":switches.duplicate(true),"powered":powered,"level":level,"frequency":frequency,"dyn_load":dyn_load,"supply_meter":supply_meter,"dyn_measure":dyn_measure,"igbt_damping":igbt_damping,"daq_settings":daq_settings.duplicate(),"revision":revision,"readings":readings.duplicate(true),"checked":checked,"mode":mode,"task":task,"seed":seed_value,"element":element,"records":records.duplicate(true),"result":result,"safety_errors":safety_errors}

func release(peer: int) -> void:
	stored_cables.erase(peer)
	if peer < 0:
		dyn_measure_holders.clear()
	else:
		dyn_measure_holders.erase(peer)
	dyn_measure = not dyn_measure_holders.is_empty()
	for c in cables:
		if c.owner == peer:
			c.owner = 0
	cables = cables.filter(func(c): return c.a != "" or c.b != "")
	revision += 1

func holding(peer: int) -> Dictionary:
	for c in cables:
		if c.owner == peer:
			return c
	return {}

func act(peer: int, a: Dictionary, position: Vector3, host := false) -> String:
	var op := str(a.get("op",""))
	var port := str(a.get("port",""))
	if op in ["plug","unplug"]:
		if not positions.has(port) or (position+Vector3.UP*1.65).distance_to(positions[port]) > 3.25:
			return "Move within reach of the terminal."
	if op in ["plug","unplug","switch","frequency","reset","undo","discard"] and powered and mode!="Free Laboratory":
		safety_errors += 1
		return "Power OFF before altering this training circuit."
	match op:
		"drawer":
			if position.distance_to(positions.get("storage",Vector3.ZERO))>3.25:
				return "Move closer to the drawer."
			drawer_open = not drawer_open
		"stash":
			var c := holding(peer)
			if c.is_empty() or c.a!="" or c.b!="":return "Only a fully unplugged cable can be stored."
			if not stored_cables.has(peer):stored_cables[peer]=[]
			if stored_cables[peer].size()>=6:return "Cable storage is full."
			stored_cables[peer].append(c.color);cables.erase(c)
		"unstash":
			if not holding(peer).is_empty():return "Store your held cable first."
			var color := int(a.get("color",0))
			if color not in stored_cables.get(peer,[]):return "That cable is not in your inventory."
			stored_cables[peer].erase(color)
			cables.append({"id":next_id,"a":"","b":"","owner":peer,"creator":peer,"color":color});next_id+=1
		"pickup":
			if positions.has("storage") and not drawer_open:
				return "Open the cable drawer first."
			if not holding(peer).is_empty() or cables.size() >= 120:
				return "Finish or return your current cable first."
			if position.distance_to(positions.get("storage",Vector3(-4.2,1.5,-1.4))) > 3.25:
				return "Pick up a cable from the drawer."
			cables.append({"id":next_id,"a":"","b":"","owner":peer,"creator":peer,"color":clampi(int(a.get("color",0)),0,3)})
			next_id += 1
		"plug":
			var c := holding(peer)
			if c.is_empty():
				return "Pick up a cable, or unplug a free end, first."
			var other: String = c.a if c.a != "" else c.b
			if other != "" and positions[port].distance_to(positions[other]) > 5.0:
				return "This 5 m lead cannot reach."
			var count := 0
			for wire in cables:
				if wire.a == port:count += 1
				if wire.b == port:count += 1
			if count >= 12:
				return "Stacking adapter capacity reached (12 plugs)."
			if c.a == "":
				c.a = port
			else:
				c.b = port
			if c.a != "" and c.b != "":
				c.owner = 0
		"grab":
			if not holding(peer).is_empty():
				return "Finish your held cable first."
			var found := false
			for c in cables:
				if c.id == int(a.get("id",-1)) and c.owner == 0 and (c.a == "" or c.b == ""):
					var anchor: String = c.a if c.a != "" else c.b
					if anchor=="" or position.distance_to(positions[anchor]+Vector3(0,-.55,.2))>3.25:
						return "Move within reach of the loose connector."
					c.owner = peer
					found = true
					break
			if not found:
				return "Another player already took that cable."
		"unplug":
			var held := holding(peer)
			if not held.is_empty() and held.a != port and held.b != port:
				return "Press G to put down your other cable first."
			var found := false
			for i in range(cables.size()-1,-1,-1):
				var c := cables[i]
				if (c.a == port or c.b == port) and (c.owner == 0 if held.is_empty() else c.id == held.id):
					if c.b == port:
						c.b = ""
					else:
						c.a = ""
					c.owner = peer
					found = true
					break
			if not found:
				return "No unlocked cable end at that post."
		"discard":
			var held := holding(peer)
			if held.is_empty():
				return "No held cable."
			cables.erase(held)
		"return":
			var c := holding(peer)
			if c.is_empty():
				return "No held cable."
			# Preserve installed end when dropping; return fully loose cables to rack.
			c.owner = 0
			cables = cables.filter(func(w): return w.a != "" or w.b != "")
		"undo":
			if not holding(peer).is_empty():
				return "Return the held cable first."
			for i in range(cables.size()-1,-1,-1):
				var c := cables[i]
				if c.creator == peer and c.owner == 0 and c.a != "" and c.b != "":
					if position.distance_to(positions[c.b]) > 3.25:
						return "Move within reach of your last connection to undo."
					c.b = ""
					c.owner = peer
					break
		"switch":
			var kind := str(a.get("kind",""))
			var i := int(a.get("index",-1))
			if not switches.has(kind) or i < 0 or i >= 9:
				return "Invalid switch."
			var key := "%s_%d" % [kind,i]
			if not positions.has(key) or position.distance_to(positions[key]) > 3.25:
				return "Move within reach of the switch."
			if bool(a.get("expected",false)) != bool(switches[kind][i]):
				return "Another player already changed this switch."
			switches[kind][i] = not switches[kind][i]
		"voltage", "frequency":
			if not is_finite(float(a.get("delta",0))):
				return "Invalid dial setting."
			if position.distance_to(positions.get("variable",Vector3.ZERO)) > 3.25:
				return "Move within reach of the supply dial."
			if op == "voltage":
				level = clampf(level + clampf(float(a.get("delta",0)), -0.05,0.05),0,1)
			else:
				frequency = clampf(frequency + clampf(float(a.get("delta",0)),-5,5),45,65)
		"dyn_load":
			if position.distance_to(positions.get("dyn_load",Vector3.ZERO))>3.25:
				return "Move within reach of the dynamometer."
			var change := float(a.get("delta",.1))
			if not is_finite(change):return "Invalid load setting."
			dyn_load = clampf(dyn_load+clampf(change,-.1,.1),0.,1.)
			records.clear()
		"supply_meter", "dyn_measure", "igbt_damping":
			if position.distance_to(positions.get(op,Vector3.ZERO))>3.25:return "Move within reach of the control."
			if op=="supply_meter":supply_meter=posmod(supply_meter+int(sign(float(a.get("delta",1)))),14)
			elif op=="dyn_measure":
				if bool(a.get("pressed",true)):
					dyn_measure_holders[peer]=true
				else:
					dyn_measure_holders.erase(peer)
				dyn_measure = not dyn_measure_holders.is_empty()
			else:igbt_damping=not igbt_damping
		"daq_output":
			if not positions.has("daq") or position.distance_to(positions.daq)>3.25:
				return "Move within reach of the DAQ."
			var channel := str(a.get("channel",""))
			var setting: Variant = a.get("value")
			if channel in ["AO0","AO1"] and (setting is int or setting is float) and is_finite(float(setting)):
				daq_settings[channel] = clampf(float(setting), -10., 10.)
			elif channel in ["DO0","DO1"] and setting is bool:
				daq_settings[channel] = setting
			else:
				return "Invalid DAQ output setting."
		"breaker":
			if position.distance_to(positions.get("power",Vector3.ZERO))>3.25:return "Move closer to the supply."
			powered=false;checked=false
		"check":
			if powered:
				return "De-energize before the preflight check."
			if cables.any(func(c): return c.owner != 0):
				return "Finish all carried leads before preflight."
			var test: Dictionary = solver.solve(terminals,completed(),switches,true,level,dyn_load)
			if test.fault != "":
				return "Preflight: " + str(test.fault)
			checked = true
		"power":
			if position.distance_to(positions.get("power",Vector3.ZERO)) > 3.25:
				return "Operate power at the supply."
			if not powered and mode != "Free Laboratory" and not checked:
				return "Complete preflight with C before energizing."
			if not powered and mode!="Free Laboratory" and cables.any(func(c): return c.owner != 0):
				return "Put the carried cable down with G, then press power."
			powered = not powered
		"reset":
			if not host:
				return "Only the host can reset the shared station."
			cables.clear()
			daq_settings.clear()
			for k in switches:
				switches[k].fill(false)
			checked = false
			records.clear()
			result = ""
		"configure":
			if not host or powered:
				return "Only the host can configure a de-energized experiment."
			mode = str(a.get("mode","Free Laboratory"))
			if not mode in ["Free Laboratory","Guided Learning","Practical Exam","Cooperative Challenge"]:
				mode = "Free Laboratory"
			task = clampi(int(a.get("task",0)),0,2)
			seed_value = int(a.get("seed",1))
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			element = clampi(int(a.get("element",rng.randi_range(0,2))),0,2) if task < 2 else 0
			records.clear()
			result = ""
			safety_errors = 0
			checked = false
		"record":
			if not powered:
				return "Energize and connect instruments before recording."
			var v: float = readings.voltmeters.max()
			var i: float = readings.ammeters.max()
			if v < 1 or i < 0.001:
				return "Connect an actual voltmeter and series ammeter first."
			records = {"v":v,"i":i,"p":readings.wattmeters[0]+readings.wattmeters[1],"revision":revision,"peer":peer}
		"submit":
			result = grade(a)
		_:
			return "Unsupported interaction."
	if op in ["pickup","grab","plug","unplug","switch","voltage","frequency","reset","return","undo","discard"]:
		checked = false
		records.clear()
		result = ""
	last_action = "return" if op=="discard" else op
	revision += 1
	recalculate()
	return ""

func linked(a: String,b: String) -> bool:
	var parent := {}
	for id in terminals:
		parent[id] = id
	for c in completed():
		solver._join(c.a,c.b,parent)
	# Current coils count as conductive paths for the experiment topology check.
	for i in range(3):
		solver._join("AM%d_IN"%i,"AM%d_OUT"%i,parent)
	for i in range(2):
		solver._join("W%d_IN"%i,"W%d_OUT"%i,parent)
	return solver._root(a,parent) == solver._root(b,parent)

func grade(answer: Dictionary) -> String:
	var topology := true
	if task < 2:
		for i in range(3):
			var source: String = ("P_" if task == 0 else "PV_") + ["A","B","C"][i]
			var sink: String = "P_N" if task == 0 else "PV_" + ["B","C","A"][i]
			var a := "R%d_P"%i
			var b := "R%d_N"%i
			topology = topology and ((linked(a,source) and linked(b,sink)) or (linked(b,source) and linked(a,sink)))
			for j in range(3):
				topology = topology and (bool(switches.R[3*i+j]) == (j==element))
			var expected_voltage := 120.0 if task==0 else 120*.57*sqrt(3)
			topology = topology and absf(float(readings.bank_voltages.get("R%d"%i,0))-expected_voltage)<.25
			topology = topology and absf(float(readings.bank_currents.get("R%d"%i,0))-expected_voltage/[1200.0,600.0,300.0][element])<.002
		for k in ["L","C"]:
			topology = topology and not switches[k].has(true)
	else:
		for k in ["R","L","C"]:
			topology = topology and linked(k+"0_P","P_A") and linked(k+"0_N","P_N") and switches[k][0]
			for j in range(1,9):
				topology = topology and not switches[k][j]
		topology = topology and absf(readings.q) < 0.75 and readings.p > 10
	topology = topology and absf(frequency-60)<.01
	var score := 50 if topology and powered and readings.fault == "" else 0
	if checked and safety_errors == 0:
		score += 20
	var measurements: bool = not records.is_empty() and records.get("p",0) > 0.1
	if measurements:
		for key in ["v","i","p"]:
			var actual: float = records[key]
			measurements = measurements and absf(float(answer.get(key,-999))-actual) <= maxf(0.01,absf(actual)*0.03)
		measurements = measurements and absf(float(records.p)-float(readings.p)) < maxf(0.1,readings.p*0.03)
	if measurements:
		score += 30
	return "%d/100 • Wiring %s • Safe preflight %s • Instrument records %s" % [score,"PASS" if topology else "REVIEW","PASS" if checked and safety_errors == 0 else "REVIEW","PASS" if measurements else "REVIEW"]
