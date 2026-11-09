extends SceneTree
const PE=preload("res://scripts/electrical_safety/protective_earth.gd")
const Profile=preload("res://scripts/electrical_safety/profile.gd")
const Network=preload("res://scripts/ac_network.gd")
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func near(actual: float,expected: float,label: String) -> void:check(absf(actual-expected)<=maxf(1e-6,absf(expected)*2e-6),label)
func aliases() -> Dictionary:return {"P_A":"A","P_N":"N","EARTH":"PE","IGBT_EARTH":"IGBT_PE"}
func sources(voltage: float=120) -> Array:
	return [{"id":"source_A","type":"voltage","a":"A","b":"N","value":Vector2(voltage,0)},{"id":"reference_N","type":"voltage","a":"N","b":"0","value":Vector2.ZERO}]
func profile(mode: String,lead: bool=true,fault: bool=true,pe_ohms: float=0.2) -> Dictionary:
	var p := Profile.example(mode)
	if lead:p.paths=[{"id":"actual_lead","a":"EARTH","b":"IGBT_EARTH","ohms":pe_ohms,"enabled":true}]
	if fault:p.faults=[{"id":"insulation","a":"P_A","b":"__pe/IGBT","ohms":0.5,"enabled":true}]
	return p
func compile(p: Dictionary,live: bool=true) -> Dictionary:
	return PE.compile(["0","A","N"],sources() if live else [],aliases(),p)
func _initialize() -> void:
	# Default is an exact netlist pass-through, including a genuinely floating source.
	var floating := [{"id":"isolated","type":"voltage","a":"x","b":"y","value":Vector2(12,0)},{"id":"load","type":"impedance","a":"x","b":"y","value":Vector2(1000,0)}]
	var disabled := PE.compile(["0","x","y"],floating,{}, {})
	check(disabled.ok and not disabled.enabled and var_to_bytes(disabled.branches)==var_to_bytes(floating),"Default adds no bonds/conductance")
	var untouched := Network.new().solve(disabled.nodes,disabled.branches)
	check(untouched.fault=="" and untouched.floating_references.size()==1,"Isolated island remains locally referenced")
	near(untouched.currents.load.length(),.012,"Existing floating differential behavior preserved")
	# Explicit assumed loop:120/(0.5fault+0.05chassis+0.2PE+0.1sourcebond).
	var bonded := compile(profile("explicit_bond"))
	check(bonded.ok,"Explicit profile compiles")
	var solved := Network.new().solve(bonded.nodes,bonded.branches)
	check(solved.fault=="","Bonded actual stamped network solves")
	var evidence := PE.evidence(bonded,solved,true,{"source_A":15.0})
	near(solved.currents["__pe/fault/insulation"].length(),120/.85,"Independent analytical bonded fault current")
	near(evidence.chassis[0].voltage_to_pe_rms,120/.85*.25,"Chassis rise across actual PE path")
	check(evidence.trip_requested and evidence.protection_events.size()==1,"Actual current triggers existing15A threshold evidence")
	check(evidence.chassis[0].pe_continuous,"PE continuity is separate from fault/load path")
	check(not evidence.chassis[0].absolute_earth_voltage_defined and not evidence.certified,"No fabricated absolute earth/touch-safety verdict")
	check(not PE.public_evidence(evidence).has("stamps"),"Public evidence hides injection IDs/topology")
	check(not PE.continuity(bonded,false).ok and not PE.continuity(bonded,true).ok,"Live/stale energized netlist cannot run continuity test")
	var off := compile(profile("explicit_bond"),false)
	var continuity := PE.continuity(off,false)
	near(continuity.chassis[0].resistance_ohms,.25,"Deenergized calculated PE resistance excludes source/fault path")
	check(continuity.chassis[0].status=="within_exercise_bound","Explicit exercise bound only")
	# Open PE with live chassis: no sustained return, no OC trip; chassis still at120V
	# relative to source neutral. No-trip is not presented as safety.
	var opened := compile(profile("explicit_bond",false))
	var open_result := Network.new().solve(opened.nodes,opened.branches)
	var open_evidence := PE.evidence(opened,open_result,true,{"source_A":15.0})
	near(open_result.currents["__pe/fault/insulation"].length(),0,"Open PE no invented leakage return")
	near(open_evidence.chassis[0].voltage_to_source_reference_rms,120,"Open PE chassis energized relative to source neutral")
	check(not open_evidence.chassis[0].pe_continuous and not open_evidence.trip_requested,"Open PE not counterfeited through neutral/source/fault")
	check(PE.continuity(compile(profile("explicit_bond",false),false),false).chassis[0].status=="open","Fault cannot counterfeit continuity")
	# High path resistance can leave current below OC threshold while chassis rises.
	var high := compile(profile("explicit_bond",true,true,10))
	var high_result := Network.new().solve(high.nodes,high.branches)
	var high_evidence := PE.evidence(high,high_result,true,{"source_A":15.0})
	near(high_result.currents["__pe/fault/insulation"].length(),120/10.65,"Independent high-resistance loop current")
	check(not high_evidence.trip_requested and high_evidence.chassis[0].voltage_to_pe_rms>100,"No false safe inference below OC threshold")
	check(PE.continuity(compile(profile("explicit_bond",true,true,10),false),false).chassis[0].status=="above_exercise_bound","High PE path identified as exercise-bound exceedance")
	for mode in ["isolated","unspecified"]:
		var unbonded := compile(profile(mode))
		check(unbonded.stamps.filter(func(edge):return edge.role=="source_bond").is_empty(),"No automatic N-PE bond")
		var state := Network.new().solve(unbonded.nodes,unbonded.branches)
		var report := PE.evidence(unbonded,state,true,{"source_A":15.0})
		near(state.currents["__pe/fault/insulation"].length(),0,"Unbonded first fault has no invented return")
		check(not report.earth_referenced and not report.trip_requested and not report.warnings.is_empty(),"Unknown/isolated modes remain explicit")
	# Resistance graph supports real parallel conductors, not a shortest-path sum.
	var parallel := profile("explicit_bond",true,false)
	parallel.paths.append({"id":"second_pe","a":"EARTH","b":"IGBT_EARTH","ohms":0.2,"enabled":true})
	near(PE.continuity(compile(parallel,false),false).chassis[0].resistance_ohms,.15,"Parallel PE conductors use shared MNA, not shortest path")
	var split := PE.prepare_leads(["P_A","P_N","EARTH","IGBT_EARTH"],[{"a":"P_A","b":"P_N"},{"a":"EARTH","b":"IGBT_EARTH"}],Profile.example())
	check(split.ideal_leads.size()==1 and split.pe_leads.size()==1,"Only actual PE-touching physical leads get finite stamps")
	for invalid in [NAN,INF,-.1,0.0,1e9]:
		var bad := profile("explicit_bond");bad.paths[0].ohms=invalid
		check(not compile(bad).ok,"Invalid/nonfinite path rejected")
	var forged := profile("isolated");forged.source_bond={"confirmed":true,"ohms":.1}
	check(not compile(forged).ok,"Isolated source cannot carry hidden source bond")
	var unknown := profile("explicit_bond");unknown.faults[0].a="unknown_terminal"
	check(not compile(unknown).ok,"Unknown endpoint cannot fabricate a connection")
	var duplicate := profile("explicit_bond");duplicate.paths.append(duplicate.paths[0].duplicate(true))
	check(not compile(duplicate).ok,"Duplicate branch ID rejected")
	var miswired := profile("isolated",false,true)
	miswired.paths=[{"id":"wrong_neutral1","a":"EARTH","b":"P_N","ohms":.2,"enabled":true},{"id":"wrong_neutral2","a":"IGBT_EARTH","b":"P_N","ohms":.2,"enabled":true}]
	var wrong := compile(miswired)
	var wrong_solution := Network.new().solve(wrong.nodes,wrong.branches)
	var wrong_report := PE.evidence(wrong,wrong_solution,true,{"source_A":15.0})
	check(wrong_report.trip_requested,"Explicit wrong neutral wiring is actually stamped, not blocked or ignored")
	check(not wrong_report.chassis[0].pe_continuous,"Neutral return cannot counterfeit dedicated PE continuity")
	check(PE.continuity(compile(miswired,false),false).chassis[0].status=="open","PE-only graph excludes misused neutral leads")
	var numerical_pe := profile("explicit_bond");numerical_pe.pe_bus="0"
	check(not compile(numerical_pe).ok,"Numerical reference cannot masquerade as PE socket")
	var broken_bond := profile("explicit_bond")
	broken_bond.chassis[0].bond_enabled=false
	var broken := compile(broken_bond)
	var broken_result := Network.new().solve(broken.nodes,broken.branches)
	near(broken_result.voltages.IGBT_PE.length(),0,"External PE post can remain at source reference with a broken internal bond")
	near(broken_result.voltages["__pe/IGBT"].length(),120,"Broken internal bond leaves actual chassis energized")
	check(not PE.evidence(broken,broken_result,true).chassis[0].pe_continuous,"Testing socket alone does not fabricate chassis continuity")
	var two_fault := profile("isolated")
	two_fault.faults.append({"id":"second_phase","a":"B","b":"__pe/IGBT","ohms":.5,"enabled":true})
	var both_sources := sources();both_sources.append({"id":"source_B","type":"voltage","a":"B","b":"N","value":Vector2(-60,-103.923048454)})
	var double := PE.compile(["0","A","B","N"],both_sources,aliases(),two_fault)
	var double_result := Network.new().solve(double.nodes,double.branches)
	near(double_result.currents["__pe/fault/insulation"].length(),120*sqrt(3),"Independent two-phase fault loop without any N-PE bond")
	check(PE.evidence(double,double_result,true,{"source_A":15.0,"source_B":15.0}).trip_requested,"Isolated source does not imply no trip for a second fault")
	check(PE.evidence(bonded,{},true).has("solver_error"),"Missing electrical data cannot fabricate zero fault current")
	# Bounded numerical sweep, independent series-loop oracle at varying phase.
	for i in range(1,31):
		var p := profile("explicit_bond",true,true,float(i)/10)
		var built := compile(p)
		var result := Network.new().solve(built.nodes,built.branches)
		near(result.currents["__pe/fault/insulation"].length(),120/(.5+.05+.1+float(i)/10),"Independent loop sweep")
	print("PROTECTIVE EARTH checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
