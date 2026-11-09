extends "res://scripts/campus/academics/equipment_evidence.gd"
const Catalog=preload("res://scripts/equipment_catalog.gd")
var ac_observations := {}
var ac_steps := {}
var ac_retained := {}

func supports(assignment: Dictionary) -> Dictionary:
	if assignment.get("course_id","")=="ETY155":return super.supports(assignment)
	if assignment.get("physical_ac_plan",{}).get("banks",[]).is_empty():return {"ok":false,"error":"This practical has no realizable AC bank plan."}
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
				roots[Solver.root(roots,a)]=Solver.root(roots,b)
		for i in range(2):
			for end in ["VP","OUT"]:roots[Solver.root(roots,"W%d_IN"%i)]=Solver.root(roots,"W%d_%s"%[i,end])
	return roots

func capture(peer: int,bench: int,assignment: Dictionary) -> Dictionary:
	if assignment.get("course_id","")=="ETY155":return super.capture(peer,bench,assignment)
	if game==null or not game.multiplayer.is_server() or bench<0 or bench>=game.session.labs.size():return {}
	var lab: RefCounted=game.session.labs[bench]
	var plan: Dictionary=assignment.get("physical_ac_plan",{})
	if plan.get("banks",[]).is_empty():return {}
	var key := _key(peer,bench,assignment)
	var signature := var_to_bytes([lab.switches,lab.completed(),lab.level,lab.frequency]).hex_encode().sha256_text()
	if not lab.powered and ac_retained.has(key) and ac_retained[key].signature==signature:
		var saved: Dictionary=ac_retained[key].evidence.duplicate(true);saved.steps=ac_steps.get(key,[]).duplicate();return saved
	var roots := _ac_roots(lab,true);var nodes := {};var expected := {}
	var topology: bool=lab.powered and lab.readings.get("fault","")=="" and absf(lab.level-float(plan.variable_level))<0.001 and absf(lab.frequency-float(plan.frequency_hz))<0.01
	for node in plan.source_nodes:nodes[node]=Solver.root(roots,str(plan.source_nodes[node]))
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
	return {"ac":true,"topology":topology,"readings":lab.readings.duplicate(true),"plan":plan,"observations":ac_observations.get(_key(peer,bench,assignment),{}).duplicate(true),"steps":ac_steps.get(_key(peer,bench,assignment),[]).duplicate()}

func record_measurement(peer: int,bench: int,assignment: Dictionary) -> bool:
	if assignment.get("course_id","")=="ETY155":return super.record_measurement(peer,bench,assignment)
	var evidence := capture(peer,bench,assignment)
	if not evidence.get("topology",false):return false
	var lab: RefCounted=game.session.labs[bench]
	var roots := _ac_roots(lab,false);var key := _key(peer,bench,assignment)
	if not ac_observations.has(key):ac_observations[key]={}
	for i in range(3):
		for tap in ["150","300"]:
			var matches: bool=Solver.root(roots,"V%d_COM"%i)==Solver.root(roots,"R0_N") and Solver.root(roots,"V%d_%s"%[i,tap])==Solver.root(roots,"R0_P")
			var value: float=lab.readings.voltmeters[i]
			if matches and value<=float(tap):ac_observations[key].voltage=value
		for tap in ["IN","2_5","8","25"]:
			var a := Solver.root(roots,"AM%d_%s"%[i,tap]);var b := Solver.root(roots,"AM%d_OUT"%i)
			var rp := Solver.root(roots,"R0_P")
			var measured: float=lab.readings.ammeters[i]
			var actual: float=lab.readings.bank_currents.get("R0",0)
			if a!=b and (a==rp or b==rp) and measured>1e-9 and absf(measured-actual)<maxf(1e-7,actual*0.02):ac_observations[key].current=measured
	evidence.observations=ac_observations[key].duplicate(true)
	ac_retained[key]={"signature":var_to_bytes([lab.switches,lab.completed(),lab.level,lab.frequency]).hex_encode().sha256_text(),"evidence":evidence.duplicate(true)}
	return not ac_observations[key].is_empty()

func observe_ac_action(peer: int,bench: int,action: Dictionary,before: Dictionary) -> void:
	if not game.school.formal_active() or game.school.activity.get("course_id","")!="ELM253":return
	var assignment: Dictionary=game.school.project;var key := _key(peer,bench,assignment)
	if not ac_steps.has(key):ac_steps[key]=[]
	var op := str(action.get("op",""))
	if op in ["plug","unplug","switch"] and not before.get("powered",true) and not "power_off_before_wiring" in ac_steps[key]:ac_steps[key].append("power_off_before_wiring")
	if before.get("powered",false) and not game.session.labs[bench].powered and ac_observations.get(key,{}).size()==2 and not "power_off_after_measurement" in ac_steps[key]:ac_steps[key].append("power_off_after_measurement")

func grade(assignment: Dictionary,evidence: Dictionary,procedure: Dictionary={}) -> Dictionary:
	if assignment.get("course_id","")=="ETY155":return super.grade(assignment,evidence,procedure)
	if not evidence.get("topology",false):return {"score":0.0,"verified":false,"reason":"Build and power the specified physical AC network; then record its actual instruments."}
	var expected: Dictionary=assignment.reference_ac.result
	var operating := true
	for bank in evidence.plan.banks:
		var id: String=str(bank.kind)+str(bank.index)
		var volts: Vector2=expected.voltages[bank.a]-expected.voltages[bank.b]
		var amps: Vector2=expected.currents[id]
		for pair in [[evidence.readings.bank_voltages.get(id,INF),volts.length()],[evidence.readings.bank_currents.get(id,INF),amps.length()]]:
			if not is_finite(float(pair[0])) or absf(float(pair[0])-float(pair[1]))>maxf(1e-6,float(pair[1])*0.02):operating=false
	var score := 40.0 if operating else 0.0
	var r_voltage: float=evidence.readings.bank_voltages.get("R0",0)
	var r_current: float=evidence.readings.bank_currents.get("R0",0)
	for pair in [["voltage",r_voltage],["current",r_current]]:
		if evidence.observations.has(pair[0]) and absf(float(evidence.observations[pair[0]])-float(pair[1]))<=maxf(1e-7,float(pair[1])*0.02):score+=15
	if evidence.observations.size()==2:score+=10
	for step in ["power_off_before_wiring","power_off_after_measurement"]:
		if step in evidence.steps:score+=10
	return {"score":score,"verified":true,"operating_point":operating,"reason":"Actual AC bank switches, cable connectivity, shared phasor solver, physical meter readings and host-observed procedure."}
