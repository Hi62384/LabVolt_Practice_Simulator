extends SceneTree
var failures := 0
var assertions := 0
const Catalog = preload("res://scripts/lab_challenges/scenario_catalog.gd")
const Objectives = preload("res://scripts/lab_challenges/objectives.gd")
const State = preload("res://scripts/lab_state.gd")
const Fixture = preload("res://tests/fixture.gd")
func check(ok: bool, msg: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(msg)
func _initialize() -> void:call_deferred("run")
func repair(state: Object,plan: Dictionary) -> void:
	state.powered=false;state.cables.clear()
	for pair in plan.healthy_leads:
		state.cables.append({"id":state.next_id,"a":pair[0],"b":pair[1],"owner":0,"creator":1,"color":0});state.next_id+=1
	for kind in ["R","L","C"]:state.switches[kind].fill(false)
	if plan.kind=="power_factor":state.switches.R[plan.resistance_element]=true;state.switches.L[plan.element]=true;state.switches.C[plan.element]=true
	elif plan.kind!="motor_open_phase":
		for bank in 3:state.switches.R[bank*3+plan.element]=true
	state.checked=false;state.revision+=1;state.recalculate()
func run() -> void:
	for kind in Catalog.KINDS:
		var variants := {}
		for seed_value in [1,2,3,4,5,100]:
			var state := State.new();state.initialize(Fixture.ids(),Fixture.locations())
			var plan := Catalog.generate(kind,seed_value)
			check(plan==Catalog.generate(kind,seed_value),"seeded scenario reproducibility")
			variants[str([plan.element,plan.fault_phase,plan.level,plan.dyn_load])]=true
			check(Catalog.setup_error(state,plan)=="","buildable "+kind)
			Catalog.install(state,plan)
			check(Objectives.fault_present(state.snapshot(),plan),"genuine initial fault "+kind)
			var initial: Dictionary=state.solver.solve(state.terminals,state.completed(),state.switches,true,state.level,state.dyn_load)
			check(initial.fault=="","initial fault scenario safely solves "+kind+" "+str(initial.fault))
			if kind=="open_phase":check(absf(float(initial.bank_currents.get("R%d"%plan.fault_phase,-1)))<1e-6,"actual open branch has zero current")
			if kind=="instrument_connection":check(absf(float(initial.voltmeters[plan.fault_phase]))<1e-6,"faulty common-node voltmeter actually reads zero")
			if kind=="unbalanced_load":check(float(initial.ammeters.max())-float(initial.ammeters.min())>.04,"actual unequal loads create unequal currents")
			if kind=="power_factor":check(float(initial.pf)<.98,"actual uncompensated circuit has low PF")
			if kind=="motor_open_phase":check(is_zero_approx(float(initial.motor_rpm)),"actual existing motor model does not rotate with missing phase")
			repair(state,plan)
			state.checked=true;state.powered=true;state.recalculate()
			state.records={"v":state.readings.voltmeters.max(),"i":state.readings.ammeters.max(),"p":state.readings.wattmeters[0]+state.readings.wattmeters[1],"revision":state.revision};state.revision+=1
			var result := Objectives.evaluate(state,plan)
			check(result.ok,"repaired actual solver "+kind+" seed="+str(seed_value)+" "+str(result.failures))
			state.records.revision-=2;check(not Objectives.evaluate(state,plan).ok,"stale readings cannot complete "+kind);state.records.revision+=2
			state.safety_errors=1;check(not Objectives.evaluate(state,plan).ok,"unsafe live edits block completion "+kind);state.safety_errors=0
			if kind in ["open_phase","unbalanced_load","instrument_connection"]:
				var expected := 3*120.0*120.0/float(preload("res://scripts/equipment_catalog.gd").LOADS.R.values[plan.element])
				check(absf(result.measurements.p-expected)<.2,"independent3V²/R reference")
			if kind=="power_factor":
				check(result.measurements.pf>.999,"actual PF correction")
				var v := float(state.readings.bank_voltages.R0);var equipment := preload("res://scripts/equipment_catalog.gd")
				var expected_q := v*v*(1.0/(TAU*60.0*float(equipment.LOADS.L.values[plan.element]))-TAU*60.0*float(equipment.LOADS.C.values[plan.element]))
				check(absf(float(result.measurements.q)-expected_q)<.002,"independent V²(1/ωL−ωC) reactive-power reference")
				check(absf(float(result.measurements.p)-v*v/float(equipment.LOADS.R.values[plan.resistance_element]))<.002,"independent V²/R corrected real power")
			if kind=="motor_open_phase":check(absf(result.measurements.motor_rpm)>0 and absf(result.measurements.motor_rpm)<1800,"actual illustrative motor RPM")
		check(variants.size()>1,"source-backed value/condition variation across seeds "+kind)
	check(load("res://scripts/lab_challenges/host.gd")!=null,"host parses")
	print("BASE_SCENARIOS_RESULT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
