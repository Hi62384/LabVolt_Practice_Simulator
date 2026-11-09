extends RefCounted
const Equipment = preload("res://scripts/equipment_catalog.gd")
# No solver here: inspect topology and readings recomputed by the existing LabState.
static func evaluate(state: Object, plan: Dictionary, require_power := true) -> Dictionary:
	var baseline := preload("res://scripts/lab_challenges/scenario_catalog.gd").baseline_error(state)
	if not baseline.is_empty():return {"ok":false,"failures":[baseline],"measurements":{}}
	var failures: Array=[]
	if require_power and not state.powered:failures.append("Energize after a valid preflight.")
	if not state.checked or state.safety_errors!=0:failures.append("Safe preflight without live edits is required.")
	if state.cables.any(func(c):return c.owner!=0):failures.append("Finish carried leads.")
	var solved: Dictionary=state.solver.solve(state.terminals,state.completed(),state.switches,true,state.level,state.dyn_load)
	if solved.get("fault","")!="":failures.append(str(solved.fault))
	if absf(float(state.frequency)-60)>0.001 or (plan.kind=="power_factor" and absf(float(state.level)-float(plan.level))>0.001):failures.append("Keep the specified source settings.")
	for pair in plan.healthy_leads:
		if not _wire_connected(state,pair[0],pair[1]):failures.append("Required measurement/load connection is not restored.");break
	var desired: Dictionary=plan.switches.duplicate(true)
	if plan.kind=="power_factor":desired.C[plan.element]=true
	elif plan.kind=="unbalanced_load":
		desired.R.fill(false)
		for bank in 3:desired.R[bank*3+plan.element]=true
	for kind in ["R","L","C"]:
		if state.switches[kind]!=desired[kind]:failures.append("Select the specified load-bank elements.");break
	if plan.kind=="power_factor":
		if absf(float(solved.voltmeters[0])-120.0*float(plan.level))>.1 or float(solved.ammeters[0])<.001:failures.append("Use the actual V0 and series AM0 instruments.")
		if float(solved.p)<1 or float(solved.pf)<0.98 or absf(float(solved.q))>maxf(.1,float(solved.p)*.03):failures.append("Measure and correct actual reactive power.")
	else:
		var volts: Array=solved.voltmeters;var amps: Array=solved.ammeters
		if float(volts.min())<119.0 or float(volts.max())>120.1:failures.append("Verify all three actual phase voltages.")
		if float(amps.min())<=0 or float(amps.max())-float(amps.min())>maxf(.002,float(amps.max())*.02):failures.append("Branch currents must be balanced.")
		if plan.kind!="motor_open_phase":
			var expected := 120.0/float(Equipment.LOADS.R.values[plan.element])
			if absf(float(amps.max())-expected)>.003+expected*.02 or absf(float(solved.q))>maxf(.1,float(solved.p)*.01):failures.append("Use only the specified balanced resistive load.")
		if plan.kind=="motor_open_phase" and (absf(float(state.dyn_load)-float(plan.dyn_load))>.001 or not solved.get("motor",{}).get("balanced",false) or absf(float(solved.motor_rpm))<1 or absf(float(solved.motor_rpm))>=1800):failures.append("Verify the actual motor model is running with balanced winding voltages.")
	var recorded: Dictionary=state.records
	if recorded.is_empty() or int(recorded.get("revision",-100))!=int(state.revision)-1: # LabState record increments revision after capturing.
		failures.append("Record current instrument measurements after the final wiring/settings change.")
	else:
		if absf(float(recorded.get("p",0))-float(solved.p))>maxf(.15,absf(float(solved.p))*.03):failures.append("Connect the real wattmeter coils for actual total power.")
	return {"ok":failures.is_empty(),"failures":failures,"measurements":{"voltmeters":solved.voltmeters.duplicate(),"ammeters":solved.ammeters.duplicate(),"wattmeters":solved.wattmeters.duplicate(),"p":solved.p,"q":solved.q,"pf":solved.pf,"motor_rpm":solved.motor_rpm}}
static func _wire_connected(state: Object,a: String,b: String) -> bool:
	# Exact physical nets, excluding meter shunts. Existing linked() treats coils as
	# conductive and cannot distinguish a bypassed series current instrument.
	var reached := {a:true}
	for iteration in state.terminals.size():
		var changed := false
		for wire in state.completed():
			if reached.has(wire.a) and not reached.has(wire.b):reached[wire.b]=true;changed=true
			if reached.has(wire.b) and not reached.has(wire.a):reached[wire.a]=true;changed=true
		if not changed:break
	return reached.has(b)
static func meaningful_measurement(state: Object) -> bool:
	return state.powered and not state.records.is_empty() and float(state.records.get("v",0))>1 and float(state.records.get("i",0))>0.001 and float(state.records.get("p",0))>0.1

static func fault_present(snapshot: Dictionary, plan: Dictionary) -> bool:
	var cables: Array=snapshot.get("cables",[]).filter(func(c):return c.get("a","")!="" and c.get("b","")!="")
	var phase: int=plan.fault_phase
	if plan.kind in ["open_phase","motor_open_phase"]:
		return not _connected(cables,"AM%d_OUT"%phase,"M%d"%(phase+1) if plan.kind=="motor_open_phase" else "R%d_P"%phase)
	if plan.kind=="instrument_connection":return not _connected(cables,"V%d_COM"%phase,"R%d_N"%phase)
	if plan.kind=="power_factor":return not bool(snapshot.switches.C[plan.element])
	var expected := [false,false,false];expected[plan.element]=true
	return snapshot.switches.R.slice(phase*3,phase*3+3)!=expected
static func _connected(cables: Array,a: String,b: String) -> bool:
	var reached := {a:true}
	for iteration in 120:
		var changed := false
		for wire in cables:
			if reached.has(wire.a) and not reached.has(wire.b):reached[wire.b]=true;changed=true
			if reached.has(wire.b) and not reached.has(wire.a):reached[wire.a]=true;changed=true
		if not changed:break
	return reached.has(b)
