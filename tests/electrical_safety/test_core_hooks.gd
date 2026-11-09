extends SceneTree
## Compile proposed current-core changes IN MEMORY. No shared file is modified.
const Profile=preload("res://scripts/electrical_safety/profile.gd")
var failures := 0
var checks := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(a: float,b: float,label: String) -> void:check(absf(a-b)<maxf(1e-5,absf(b)*2e-5),label)
func read_proposal(name: String) -> String:
	var folder := OS.get_environment("LABVOLT_PE_PROPOSALS")
	return FileAccess.get_file_as_string(folder+"/"+name+"-proposal.txt") if folder!="" else FileAccess.get_file_as_string("res://scripts/"+name+".gd")
func _initialize() -> void:
	var source := read_proposal("circuit_solver")
	if not source.contains("var protective_earth_profile"):
		push_error("Shared hooks are not applied. Set LABVOLT_PE_PROPOSALS to the task-local proposal directory for in-memory pre-integration testing.");quit(2);return
	var script := GDScript.new();script.source_code=source
	check(script.reload()==OK,"Proposed current CircuitSolver compiles")
	if failures:quit(1);return
	var solver: Object=script.new()
	var terminals: Array=["P_A","P_N","PV_A","PV_N","EARTH","IGBT_EARTH","R0_P","R0_N"]
	var switches := {"R":[false,true,false,false,false,false,false,false,false],"L":[false,false,false,false,false,false,false,false,false],"C":[false,false,false,false,false,false,false,false,false]}
	var leads: Array=[{"a":"P_A","b":"R0_P"},{"a":"R0_N","b":"P_N"}]
	var old := preload("res://scripts/circuit_solver.gd").new().solve(terminals,leads,switches,true,1.0)
	var normal: Dictionary=solver.solve(terminals,leads,switches,true,1.0)
	check(var_to_bytes(normal)==var_to_bytes(old),"Unconfigured circuit is byte-identical to prior solver result")
	near(normal.bank_currents.R0,.2,"Disabled profile retains analytical normal600ohm load current")
	var profile := Profile.example("explicit_bond")
	profile.faults=[{"id":"line_chassis","a":"P_A","b":"__pe/IGBT","ohms":.5,"enabled":true}]
	solver.protective_earth_profile=profile
	var wired := leads.duplicate(true);wired.append({"a":"EARTH","b":"IGBT_EARTH"})
	var fault: Dictionary=solver.solve(terminals,wired,switches,true,1.0)
	check(str(fault.fault).begins_with("SUPPLY OVERCURRENT"),"Actual fault stamps use existing source trip path")
	near(fault.source_currents.P_A,120/.85+.2,"Existing source current includes PE fault plus genuine load current")
	check(fault.safety.trip_requested,"Host evidence agrees with existing protection threshold")
	check(not fault.safety.has("stamps"),"Public core output hides injected fault ID list")
	var opened: Dictionary=solver.solve(terminals,leads,switches,true,1.0)
	check(opened.fault=="" and not opened.safety.chassis[0].pe_continuous,"Open PE does not fabricate a protective trip")
	near(opened.voltages.IGBT_EARTH.x,120,"Actual chassis/PE terminal becomes energized through insulation fault")
	near(opened.source_currents.P_A,.2,"No invented ground leakage")
	var off: Dictionary=solver.solve(terminals,wired,switches,false,1.0)
	near(off.safety.continuity.chassis[0].resistance_ohms,.25,"Power-off continuity follows actual patch lead")
	for volts in off.voltages.values():near(volts.length(),0,"Existing power-off voltage semantics preserved")
	profile.topology="isolated";profile.source_bond={};solver.protective_earth_profile=profile
	var isolated: Dictionary=solver.solve(terminals,wired,switches,true,1.0)
	check(isolated.fault=="" and not isolated.safety.source_bond_declared,"No automatic source bond in live core")
	near(isolated.source_currents.P_A,.2,"Isolated first chassis fault adds no return current")
	# Test the proposed LabState using the proposed solver as dependency injection;
	# replacing only its constructor avoids writing either shared source file.
	var lab_source := read_proposal("lab_state").replace("var solver = Solver.new()","var solver: Object")
	var lab_script := GDScript.new();lab_script.source_code=lab_source
	check(lab_script.reload()==OK,"Proposed LabState compiles")
	if failures:quit(1);return
	var lab: Object=lab_script.new();lab.solver=script.new();lab.initialize(terminals,{})
	lab.cables.append({"id":1,"a":"EARTH","b":"IGBT_EARTH","owner":0,"color":0})
	var host_profile := Profile.example("explicit_bond")
	host_profile.faults=[{"id":"line_chassis","a":"P_A","b":"__pe/IGBT","ohms":.5,"enabled":true}]
	check(lab.configure_protective_earth(host_profile).ok,"Host configures explicit educational profile while off")
	lab.powered=true;lab.recalculate()
	check(not lab.powered and lab.readings.fault.begins_with("SUPPLY OVERCURRENT"),"Existing LabState turns power off on actual source trip")
	check(lab.readings.safety.snapshot_kind=="pre_trip" and lab.readings.safety.power_removed,"Trip evidence retained and explicitly historical")
	for volts in lab.readings.voltages.values():near(volts.length(),0,"Post-trip live readings remain zero")
	check(var_to_bytes(lab.protective_earth_recovery())==var_to_bytes(host_profile),"Private host recovery profile preserved")
	lab.powered=true
	check(not lab.configure_protective_earth({}).ok,"Cannot alter fault model while powered")
	print("PE CORE HOOKS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
