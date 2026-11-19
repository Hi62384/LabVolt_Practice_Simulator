extends "res://scripts/campus/academics/equipment_evidence.gd"
const Catalog=preload("res://scripts/equipment_catalog.gd")
# The 1.2 kΩ bank plus both finite-impedance voltage coils can load a
# branch ammeter by slightly over 2%. Retain margin for shunt voltage drop.
const AMMETER_LOADING_TOLERANCE := 0.03
var ac_observations := {}
var ac_steps := {}
var ac_retained := {}

func supports(assignment: Dictionary) -> Dictionary:
	if assignment.get("course_id","")!="ELM253":return super.supports(assignment)
	if game==null or game.session.labs.is_empty():return {"ok":false,"error":"No authoritative AC bench is available."}
	var plan: Dictionary=assignment.get("physical_ac_plan",{})
	if plan.get("banks",[]).is_empty() or assignment.get("reference_ac",{}).get("result",{}).is_empty():
		return {"ok":false,"error":"This practical has no realizable AC bank plan or reference."}
	return {"ok":true,"error":""}

func recovery_state() -> Dictionary:
	var data := super.recovery_state();data.ac_observations=ac_observations;data.ac_steps=ac_steps;data.ac_retained=ac_retained;return data
func restore_recovery(data: Dictionary) -> void:
	super.restore_recovery(data);ac_observations=data.get("ac_observations",{}).duplicate(true);ac_steps=data.get("ac_steps",{}).duplicate(true);ac_retained=data.get("ac_retained",{}).duplicate(true)

func _ac_roots(lab: RefCounted,instruments: bool) -> Dictionary:
	var roots := {}
	for id in lab.terminals:roots[id]=id
	for lead in lab.completed():roots[Solver.root(roots,lead.a)]=Solver.root(roots,lead.b)
	roots[Solver.root(roots,"PV_N")]=Solver.root(roots,"P_N")
	if instruments:
		for i in range(3):
			for tap in ["IN","2_5","8","25"]:
				var a := "AM%d_%s"%[i,tap];var b := "AM%d_OUT"%i
				if roots.has(a) and roots.has(b):roots[Solver.root(roots,a)]=Solver.root(roots,b)
		for i in range(2):
			var a := "W%d_IN"%i;var b := "W%d_OUT"%i
			roots[Solver.root(roots,a)]=Solver.root(roots,b)
	return roots

func _ac_signature(lab: RefCounted) -> String:
	return var_to_bytes([lab.switches,lab.completed(),lab.level,lab.frequency,lab.daq_settings,lab.igbt_damping,lab.dyn_load,lab.protective_earth_profile,lab.external_connections]).hex_encode().sha256_text()

func capture(peer: int,bench: int,assignment: Dictionary) -> Dictionary:
	if assignment.get("course_id","") in ["ETY155","DGS266"]:return super.capture(peer,bench,assignment)
	if game==null or not game.multiplayer.is_server() or bench<0 or bench>=game.session.labs.size():return {}
	if not game.session.roster.has(peer) or not game.school.equipment_access(peer,bench,"ELM253"):return {}
	var lab: RefCounted=game.session.labs[bench]
	var plan: Dictionary=assignment.get("physical_ac_plan",{})
	if plan.get("banks",[]).is_empty():return {}
	var key := _key(peer,bench,assignment)
	var signature := _ac_signature(lab)
	if not lab.powered and lab.readings.get("fault","")=="" and ac_retained.has(key) and ac_retained[key].signature==signature:
		var saved: Dictionary=ac_retained[key].evidence.duplicate(true);saved.steps=ac_steps.get(key,[]).duplicate();return saved
	var roots := _ac_roots(lab,true);var nodes := {};var expected := {}
	var topology: bool=lab.powered and lab.external_connections==0 and lab.readings.get("fault","")=="" and absf(lab.level-float(plan.variable_level))<0.001 and absf(lab.frequency-float(plan.frequency_hz))<0.01
	for node in plan.source_nodes:nodes[node]=Solver.root(roots,str(plan.source_nodes[node]))
	for node in nodes:
		if nodes.values().count(nodes[node])!=1:topology=false
	for bank in plan.banks:
		var id: String=str(bank.kind)+str(bank.index);expected[id]=bank
		var values: Array=Catalog.LOADS[bank.kind].values
		var total := 0.0
		for i in range(3):
			if lab.switches[bank.kind][int(bank.index)*3+i]:total+=1/float(values[i]) if bank.kind in ["R","L"] else float(values[i])
		var value := (1/total if bank.kind in ["R","L"] else total) if total>0 else 0.0
		if absf(value-float(bank.value))>maxf(1e-12,float(bank.value)*0.001):topology=false
		for pair in [[bank.a,id+"_P"],[bank.b,id+"_N"]]:
			var root := Solver.root(roots,str(pair[1]))
			if nodes.has(pair[0]) and nodes[pair[0]]!=root:topology=false
			elif not nodes.has(pair[0]) and nodes.values().has(root):topology=false
			else:nodes[pair[0]]=root
	for kind in ["R","L","C"]:
		for i in range(3):
			if not expected.has(kind+str(i)) and lab.switches[kind].slice(i*3,i*3+3).has(true):topology=false
	var recorded: Dictionary=ac_observations.get(key,{}) if ac_retained.get(key,{}).get("signature","")==signature else {}
	return {"ac":true,"topology":topology,"readings":lab.readings.duplicate(true),"plan":plan,"observations":recorded.duplicate(true),"steps":ac_steps.get(key,[]).duplicate()}

func record_measurement(peer: int,bench: int,assignment: Dictionary) -> bool:
	if assignment.get("course_id","") in ["ETY155","DGS266"]:return super.record_measurement(peer,bench,assignment)
	var evidence := capture(peer,bench,assignment)
	if not evidence.get("topology",false):return false
	var lab: RefCounted=game.session.labs[bench]
	if not lab.powered:return false
	var roots := _ac_roots(lab,false);var key := _key(peer,bench,assignment)
	var measured_channels := {}
	var resistor_high := Solver.root(roots,"R0_P")
	var resistor_low := Solver.root(roots,"R0_N")
	var current_path := [resistor_high]
	var expected_watts: float=lab.readings.bank_voltages.get("R0",0.0)*lab.readings.bank_currents.get("R0",0.0)
	for i in range(2):
		var inlet := Solver.root(roots,"W%d_IN"%i)
		var outlet := Solver.root(roots,"W%d_OUT"%i)
		var common := Solver.root(roots,"W%d_VN"%i)
		var watts: float=lab.readings.wattmeters[i]
		if inlet!=outlet and outlet==resistor_high:
			current_path.append(inlet)
			if common==resistor_low and _matches_watts(watts,expected_watts):measured_channels.power=watts
	for i in range(3):
		for tap in ["150","300"]:
			var matches: bool=Solver.root(roots,"V%d_COM"%i)==Solver.root(roots,"R0_N") and Solver.root(roots,"V%d_%s"%[i,tap])==Solver.root(roots,"R0_P")
			var value: float=lab.readings.voltmeters[i]
			if matches and value<=float(lab.readings.voltmeter_ranges[i]):measured_channels.voltage=value
		for tap in ["IN","2_5","8","25"]:
			var a := Solver.root(roots,"AM%d_%s"%[i,tap]);var b := Solver.root(roots,"AM%d_OUT"%i)
			var measured: float=lab.readings.ammeters[i]
			var actual: float=lab.readings.bank_currents.get("R0",0)
			if a!=b and (a in current_path or b in current_path) and measured>1e-9 and measured<=float(lab.readings.ammeter_ranges[i]) and absf(measured-actual)<maxf(1e-7,actual*AMMETER_LOADING_TOLERANCE):measured_channels.current=measured
	if measured_channels.is_empty():return false
	ac_observations[key]=measured_channels
	evidence.observations=measured_channels.duplicate()
	ac_retained[key]={"signature":_ac_signature(lab),"evidence":evidence.duplicate(true)}
	return true

func observe_ac_action(peer: int,bench: int,action: Dictionary,before: Dictionary) -> void:
	var assignment: Dictionary={}
	if game.school.formal_active() and game.school.activity.get("course_id","")=="ELM253":
		assignment=game.school.project
	elif is_instance_valid(game.lecture_classes):
		var assigned: Dictionary=game.lecture_classes.assigned_lab(peer)
		if assigned.get("course","")!="ELM253" or int(assigned.get("bench",-1))!=bench:return
		assignment=game.school.papers.get(int(assigned.get("paper",0)),{}).get("project",{})
	if assignment.is_empty():return
	var key := _key(peer,bench,assignment)
	if not ac_steps.has(key):ac_steps[key]=[]
	var op := str(action.get("op",""))
	if op in ["plug","unplug","switch"] and not before.get("powered",true) and not "power_off_before_wiring" in ac_steps[key]:ac_steps[key].append("power_off_before_wiring")
	if op in ["plug","unplug","switch"] and before.get("powered",false) and not "unsafe_live_change" in ac_steps[key]:ac_steps[key].append("unsafe_live_change")
	var lab: RefCounted=game.session.labs[bench]
	if op=="power" and before.get("powered",false) and not lab.powered and ac_retained.get(key,{}).get("signature","")==_ac_signature(lab) and _complete_observations(assignment,ac_observations.get(key,{})) and not "power_off_after_measurement" in ac_steps[key]:ac_steps[key].append("power_off_after_measurement")

func _complete_observations(assignment: Dictionary, observations: Dictionary) -> bool:
	return observations.has("voltage") and observations.has("current") and (not assignment.get("practical",{}).get("requires_wattmeter",false) or observations.has("power"))

func _matches_watts(watts: float, expected: float) -> bool:
	return is_finite(watts) and watts>0.0 and expected>0.0 and absf(watts-expected)<=maxf(1e-6,expected*0.03)

func grade(assignment: Dictionary,evidence: Dictionary,procedure: Dictionary={}) -> Dictionary:
	if assignment.get("course_id","") in ["ETY155","DGS266"]:return super.grade(assignment,evidence,procedure)
	if not evidence.get("topology",false):return {"score":0.0,"verified":false,"reason":"Build and power the specified physical AC network; then record its actual instruments."}
	if "unsafe_live_change" in evidence.steps:return {"score":0.0,"verified":true,"reason":"A wiring or bank change was made with AC power on."}
	var expected: Dictionary=assignment.reference_ac.result
	var measured_nodes: Dictionary=evidence.readings.get("voltages",{})
	var operating := true
	var real_power := 0.0
	var reactive_power := 0.0
	for bank in evidence.plan.banks:
		var id: String=str(bank.kind)+str(bank.index)
		var volts: Vector2=expected.voltages[bank.a]-expected.voltages[bank.b]
		var amps: Vector2=expected.currents[id]
		real_power+=volts.dot(amps)
		reactive_power+=volts.y*amps.x-volts.x*amps.y
		var actual_phase: Vector2=measured_nodes.get(id+"_P",Vector2.ZERO)-measured_nodes.get(id+"_N",Vector2.ZERO)
		if volts.length()>1e-5 and absf(angle_difference(volts.angle(),actual_phase.angle()))>deg_to_rad(2.0):operating=false
		for pair in [[evidence.readings.bank_voltages.get(id,INF),volts.length()],[evidence.readings.bank_currents.get(id,INF),amps.length()]]:
			if not is_finite(float(pair[0])) or absf(float(pair[0])-float(pair[1]))>maxf(1e-6,float(pair[1])*0.02):operating=false
	for pair in [[evidence.readings.get("p",INF),real_power],[evidence.readings.get("q",INF),reactive_power]]:
		if not is_finite(float(pair[0])) or absf(float(pair[0])-float(pair[1]))>maxf(0.02,absf(float(pair[1]))*0.02):operating=false
	var score := 40.0 if operating else 0.0
	var r_voltage: float=evidence.readings.bank_voltages.get("R0",0)
	var r_current: float=evidence.readings.bank_currents.get("R0",0)
	var requires_wattmeter: bool=assignment.get("practical",{}).get("requires_wattmeter",false)
	var verified_channels := {}
	for pair in [["voltage",r_voltage,0.02],["current",r_current,AMMETER_LOADING_TOLERANCE]]:
		if evidence.observations.has(pair[0]) and absf(float(evidence.observations[pair[0]])-float(pair[1]))<=maxf(1e-7,float(pair[1])*float(pair[2])):
			verified_channels[pair[0]]=true
			score+=10 if requires_wattmeter else 15
	if requires_wattmeter and _matches_watts(float(evidence.observations.get("power",0.0)),r_voltage*r_current):
		verified_channels.power=true
		score+=10
	if _complete_observations(assignment,verified_channels):score+=10
	for step in ["power_off_before_wiring","power_off_after_measurement"]:
		if step in evidence.steps:score+=10
	var reason := "Actual AC bank switches, cable connectivity, shared phasor solver, physical meter readings and host-observed procedure."
	if requires_wattmeter and not verified_channels.has("power"):
		reason="Record the R0 wattmeter reading with its current coil in series and its voltage common on R0_N."
	return {"score":score,"verified":true,"operating_point":operating,"reason":reason}
