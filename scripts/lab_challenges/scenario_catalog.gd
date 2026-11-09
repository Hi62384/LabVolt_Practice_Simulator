extends RefCounted
const Equipment = preload("res://scripts/equipment_catalog.gd")
const KINDS := ["open_phase","instrument_connection","unbalanced_load","power_factor","motor_open_phase"]
static func catalog() -> Array:
	return [{"id":"open_phase","title":"Find the missing phase","objective":"Diagnose the missing branch feed; restore and measure a balanced Wye load."},{"id":"instrument_connection","title":"The misleading voltmeter","objective":"Locate and correct the actual instrument reference fault, then verify all three phase readings."},{"id":"unbalanced_load","title":"Unequal branch currents","objective":"Diagnose the mismatched resistor bank selection and restore balance."},{"id":"power_factor","title":"Reactive power investigation","objective":"Measure the inductive load, select the matching existing capacitor and verify corrected PF."},{"id":"motor_open_phase","title":"Motor will not run","objective":"Restore the missing phase of the illustrative induction model and verify balanced winding voltages and actual RPM."}]
static func generate(kind: String, seed_value: int) -> Dictionary:
	if kind not in KINDS: return {}
	var rng := RandomNumberGenerator.new(); rng.seed=seed_value
	var element := rng.randi_range(0,2); var phase := rng.randi_range(0,2)
	var plan := {"schema":1,"kind":kind,"seed":seed_value,"frequency":60.0,"level":1.0,"dyn_load":0.0,"element":element,"fault_phase":phase,"leads":[],"healthy_leads":[],"switches":{"R":[false,false,false,false,false,false,false,false,false],"L":[false,false,false,false,false,false,false,false,false],"C":[false,false,false,false,false,false,false,false,false]},"diagnosis":"","difficulty":1,"source":{"requirement":"00-base-task.txt sections8/9","equipment":"equipment_catalog.gd actual120V load banks","model":"Existing circuit_solver.gd; no substituted values"}}
	if kind=="power_factor":
		var resistance_element := rng.randi_range(0,1)
		plan.element=element; plan.resistance_element=resistance_element; plan.level=[0.5,0.65,0.8][rng.randi_range(0,2)]
		plan.switches.R[resistance_element]=true; plan.switches.L[element]=true
		plan.source_phase="PV_"+["A","B","C"][phase]; plan.return_port="PV_N"
		plan.healthy_leads=[[plan.source_phase,"W0_IN"],["W0_OUT","AM0_IN"],["AM0_OUT","R0_P"],["R0_P","L0_P"],["R0_P","C0_P"],["R0_N","PV_N"],["L0_N","PV_N"],["C0_N","PV_N"],["W0_VN","PV_N"],["V0_150","R0_P"],["V0_COM","PV_N"]]
		plan.leads=plan.healthy_leads.duplicate(true); plan.diagnosis="missing_capacitor"; plan.difficulty=2
	elif kind=="motor_open_phase":
		plan.dyn_load=[0.0,0.15,0.3][rng.randi_range(0,2)]; plan.difficulty=2
		plan.healthy_leads=_three_phase(true)
		plan.healthy_leads.append_array([["P_A","DYN_0"],["P_N","DYN_1"]])
		plan.leads=plan.healthy_leads.duplicate(true)
		plan.leads.erase(["AM%d_OUT"%phase,"M%d"%(phase+1)])
		plan.diagnosis="open_phase_"+str(phase+1); plan.source.model="Illustrative induction_motor.gd parameters; not a manufacturer fault/thermal model"
	else:
		for bank in 3: plan.switches.R[bank*3+element]=true
		plan.healthy_leads=_three_phase(false); plan.leads=plan.healthy_leads.duplicate(true)
		if kind=="open_phase":
			plan.leads.erase(["AM%d_OUT"%phase,"R%d_P"%phase]); plan.diagnosis="open_phase_"+str(phase+1)
		elif kind=="instrument_connection":
			plan.leads.erase(["V%d_COM"%phase,"R%d_N"%phase]); plan.leads.append(["V%d_COM"%phase,"R%d_P"%phase]); plan.diagnosis="voltmeter_reference_"+str(phase+1)
		else:
			plan.switches.R[phase*3+element]=false; plan.switches.R[phase*3+(element+1)%3]=true;plan.diagnosis="load_bank_"+str(phase+1)
	return plan
static func _three_phase(motor: bool) -> Array:
	var links: Array=[["P_A","W0_IN"],["W0_OUT","AM0_IN"],["P_B","AM1_IN"],["P_C","W1_IN"],["W1_OUT","AM2_IN"],["W0_VN","P_B"],["W1_VN","P_B"]]
	for i in 3:
		var plus := "M%d"%(i+1) if motor else "R%d_P"%i
		var minus := "M%d"%(i+4) if motor else "R%d_N"%i
		links.append(["AM%d_OUT"%i,plus]); links.append([minus,"P_N"])
		links.append(["V%d_150"%i,plus]);links.append(["V%d_COM"%i,minus])
	return links
static func baseline_error(state: Object) -> String:
	var profile: Variant={}
	if state.has_method("protective_earth_recovery"):profile=state.call("protective_earth_recovery")
	elif state.get_property_list().any(func(property):return property.name=="protective_earth_profile"):profile=state.get("protective_earth_profile")
	if not profile is Dictionary or not profile.is_empty():return "End the protective-earth demonstration through the trusted host controls with outputs off before starting/restoring team troubleshooting."
	if state.get_property_list().any(func(property):return property.name=="external_connections"):
		var count: Variant=state.get("external_connections")
		if not count is int or count!=0:return "Disconnect external bench leads before this isolated-bench challenge."
	return ""
static func setup_error(state: Object, plan: Dictionary) -> String:
	if plan.is_empty():return "Unknown supported challenge."
	if state.powered:return "De-energize before starting the challenge."
	var baseline := baseline_error(state)
	if not baseline.is_empty():return baseline
	if state.cables.any(func(c):return c.owner!=0): return "Finish carried leads first."
	for wire in plan.leads:
		for port in wire:
			if port not in state.terminals or not state.positions.get(port) is Vector3:return "Required equipment socket unavailable: "+str(port)
		if state.positions[wire[0]].distance_to(state.positions[wire[1]])>5.0:return "The fixed scenario requires a lead longer than the available5m."
	return ""
static func install(state: Object, plan: Dictionary) -> void:
	state.powered=false;state.checked=false;state.safety_errors=0;state.records.clear();state.result="";state.mode="Cooperative Challenge"
	state.frequency=plan.frequency;state.level=plan.level;state.dyn_load=plan.dyn_load;state.switches=plan.switches.duplicate(true);state.cables.clear()
	for pair in plan.leads:
		state.cables.append({"id":state.next_id,"a":pair[0],"b":pair[1],"owner":0,"creator":1,"color":state.next_id%4});state.next_id+=1
	state.revision+=1;state.recalculate()

static func brief(plan: Dictionary) -> String:
	if plan.is_empty():return ""
	if plan.kind=="power_factor":return "60 Hz · %s / PV_N · %.1f V RMS · R %.0f Ω · L %.1f H. Diagnose the reactive-power fault and achieve PF ≥0.98 with existing capacitor switches. Record actual V0, AM0 and W0 readings."%[plan.source_phase,120.0*float(plan.level),Equipment.LOADS.R.values[plan.resistance_element],Equipment.LOADS.L.values[plan.element]]
	if plan.kind=="motor_open_phase":return "60 Hz · 120 V phase-neutral · four-pole illustrative motor · dynamometer %.2f. Diagnose missing phase, restore balanced winding voltages and verify actual RPM below 1800. No manufacturer thermal-fault fidelity is claimed."%float(plan.dyn_load)
	return "60 Hz · 120 V phase-neutral · balanced Wye · one %.0f Ω resistor per bank. Diagnose the measured fault, restore correct wiring/selection, then record all three phase voltages/currents and two-wattmeter total power."%float(Equipment.LOADS.R.values[plan.element])
