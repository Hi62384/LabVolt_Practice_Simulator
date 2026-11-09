extends RefCounted
## Bounded, optional AC protective-conductor adapter. All electrical solutions,
## including continuity, use the established RMS AC MNA implementation.
const Network=preload("res://scripts/ac_network.gd")
const Profile=preload("res://scripts/electrical_safety/profile.gd")
const PREFIX := "__pe/"
static func prepare_leads(terminals: Array,leads: Array,profile: Dictionary) -> Dictionary:
	var check := Profile.validate(profile)
	if not check.ok:return check
	if not check.enabled:return {"ok":true,"ideal_leads":leads.duplicate(true),"pe_leads":[]}
	var pe_ports: Array=[profile.pe_bus]
	for chassis in profile.chassis:pe_ports.append(chassis.terminal)
	for port in pe_ports:
		if port not in terminals:return Profile.bad("Configured PE terminal does not exist: "+str(port))
	if leads.size()>120:return Profile.bad("Lead budget exceeded")
	var ideal: Array=[];var protective: Array=[];var serial := 0
	for lead in leads:
		if not lead is Dictionary or not lead.get("a") is String or not lead.get("b") is String or lead.a not in terminals or lead.b not in terminals:return Profile.bad("Invalid completed physical lead")
		if lead.a in pe_ports or lead.b in pe_ports:
			protective.append({"id":"lead%d"%serial,"a":lead.a,"b":lead.b,"ohms":profile.pe_lead_ohms,"enabled":true})
		else:ideal.append(lead.duplicate(true))
		serial+=1
	return {"ok":true,"ideal_leads":ideal,"pe_leads":protective}
static func canonical(id: String,aliases: Dictionary) -> String:
	var value := id;var visited := {}
	while aliases.has(value) and str(aliases[value])!=value:
		if visited.has(value):return ""
		visited[value]=true;value=str(aliases[value])
	return value
static func compile(nodes: Array,branches: Array,aliases: Dictionary,profile: Dictionary,pe_leads: Array=[]) -> Dictionary:
	var valid := Profile.validate(profile)
	if not valid.ok:return valid
	if not valid.enabled:return {"ok":true,"enabled":false,"nodes":nodes.duplicate(),"branches":branches.duplicate(true),"stamps":[],"pe_edges":[],"chassis":[],"profile":{}}
	if pe_leads.size()>120 or branches.size()>192 or nodes.size()>192:return Profile.bad("Protective-earth network budget exceeded")
	var output := {"ok":true,"enabled":true,"nodes":nodes.duplicate(),"branches":branches.duplicate(true),"stamps":[],"pe_edges":[],"chassis":[],"profile":profile.duplicate(true),"energized_source":false}
	for branch in branches:
		if str(branch.get("type",""))=="voltage" and (branch.get("value",Vector2.ZERO) as Vector2).length()>1e-9:output.energized_source=true
	var known := {}
	for node in nodes:known[str(node)]=true
	for pin in aliases:
		var root := canonical(str(pin),aliases)
		if root=="":return Profile.bad("Cyclic physical aliases")
		known[root]=true
	var pe := canonical(profile.pe_bus,aliases);var source_reference := canonical(profile.source_reference,aliases)
	if not known.has(pe) or not known.has(source_reference):return Profile.bad("Unknown source reference or PE socket")
	output.pe_bus=pe;output.source_reference=source_reference
	if pe==source_reference:return Profile.bad("PE and neutral were premerged; split PE-touching leads before ideal wire unions")
	var pe_nodes := {pe:true}
	var identifiers := {}
	for branch in branches:
		if str(branch.id).begins_with(PREFIX):return Profile.bad("Reserved protective-earth branch ID collision")
		identifiers[str(branch.id)]=true
	for item in profile.chassis:
		var node := PREFIX+str(item.id)
		if known.has(node):return Profile.bad("Chassis node collision")
		known[node]=true
		var terminal := canonical(item.terminal,aliases)
		if not known.has(terminal):return Profile.bad("Unknown chassis PE terminal")
		output.chassis.append({"id":item.id,"node":node,"terminal":terminal})
		pe_nodes[node]=true;pe_nodes[terminal]=true
		if item.get("bond_enabled",true):stamp(output,"bond/"+str(item.id),node,terminal,float(item.bond_ohms),"pe")
	for edge in profile.paths+pe_leads:
		if not edge is Dictionary or not Profile.name_ok(edge.get("id")) or not Profile.name_ok(edge.get("a")) or not Profile.name_ok(edge.get("b")) or not edge.get("enabled") is bool or not Profile.number(edge.get("ohms"),0.01,1e6):return Profile.bad("Invalid finite PE path")
		if not edge.enabled:continue
		var a := canonical(edge.a,aliases);var b := canonical(edge.b,aliases)
		if not known.has(a) or not known.has(b):return Profile.bad("Unknown PE path endpoint")
		stamp(output,"path/"+str(edge.id),a,b,float(edge.ohms),"pe" if pe_nodes.has(a) and pe_nodes.has(b) else "misused_pe_terminal")
	if profile.topology=="explicit_bond":stamp(output,"source_bond",pe,source_reference,float(profile.source_bond.ohms),"source_bond")
	for edge in profile.faults:
		if not edge.enabled:continue
		var a := canonical(edge.a,aliases);var b := canonical(edge.b,aliases)
		if not known.has(a) or not known.has(b):return Profile.bad("Unknown insulation-fault endpoint")
		stamp(output,"fault/"+str(edge.id),a,b,float(edge.ohms),"insulation_fault")
	var ids := {}
	for edge in output.stamps:
		if ids.has(edge.id):return Profile.bad("Duplicate finite safety stamp")
		ids[edge.id]=true
	return output
static func stamp(output: Dictionary,id: String,a: String,b: String,ohms: float,role: String) -> void:
	# A zero potential difference across an already joined node creates no new
	# connection; retain metadata but omit a redundant physical branch.
	var edge := {"id":PREFIX+id,"a":a,"b":b,"ohms":ohms,"role":role,"collapsed":a==b}
	output.stamps.append(edge)
	if role=="pe":output.pe_edges.append(edge)
	for node in [a,b]:
		if node not in output.nodes:output.nodes.append(node)
	if a!=b:output.branches.append({"id":edge.id,"type":"impedance","a":a,"b":b,"value":Vector2(ohms,0)})
static func reachable(a: String,b: String,edges: Array) -> bool:
	if a==b:return true
	var seen := {a:true};var queue: Array=[a]
	while not queue.is_empty():
		var node: String=queue.pop_back()
		for edge in edges:
			var next := str(edge.b) if str(edge.a)==node else str(edge.a) if str(edge.b)==node else ""
			if next==b:return true
			if next!="" and not seen.has(next):seen[next]=true;queue.append(next)
	return false
static func continuity(compiled: Dictionary,powered: bool) -> Dictionary:
	if powered or compiled.get("energized_source",false):return {"ok":false,"error":"De-energize every connected source before a PE continuity calculation"}
	if not compiled.get("ok",false):return compiled
	if not compiled.get("enabled",false):return {"ok":true,"enabled":false,"chassis":[]}
	var report: Array=[]
	for item in compiled.chassis:
		if not reachable(item.node,compiled.pe_bus,compiled.pe_edges):report.append({"id":item.id,"status":"open","resistance_ohms":null});continue
		var nodes: Array=["0"];var branches: Array=[]
		for edge in compiled.pe_edges:
			if edge.collapsed:continue
			for node in [edge.a,edge.b]:
				if node not in nodes:nodes.append(node)
			branches.append({"id":edge.id,"type":"impedance","a":edge.a,"b":edge.b,"value":Vector2(edge.ohms,0)})
		branches.append({"id":PREFIX+"continuity_probe","type":"voltage","a":item.node,"b":compiled.pe_bus,"value":Vector2(1,0)})
		var solved := Network.new().solve(nodes,branches)
		if solved.fault!="":return {"ok":false,"error":solved.fault}
		var current: float=solved.currents[PREFIX+"continuity_probe"].length()
		if current<=1e-12:return {"ok":false,"error":"Unresolved PE continuity current"}
		var resistance := 1.0/current
		report.append({"id":item.id,"status":"within_exercise_bound" if resistance<=float(compiled.profile.continuity_bound_ohms) else "above_exercise_bound","resistance_ohms":resistance})
	return {"ok":true,"enabled":true,"chassis":report,"method":"Calculated resistance on PE conductor graph only; computational unit source, not a standardized physical tester","certified":false}
static func evidence(compiled: Dictionary,result: Dictionary,powered: bool,source_limits: Dictionary={}) -> Dictionary:
	if not compiled.get("ok",false):return compiled
	if not compiled.get("enabled",false):return {"enabled":false}
	var report := {"enabled":true,"model":"educational_resistive_PE.v1","powered":powered,"topology":compiled.profile.topology,"source_bond_declared":compiled.profile.topology=="explicit_bond","earth_referenced":false,"certified":false,"stamps":[],"chassis":[],"protection_events":[],"warnings":[],"trip_requested":false}
	report.assumptions=compiled.profile.get("assumptions","Host-configured finite-resistance teaching model; not equipment certification or a touch-safety calculation.")
	if not powered:
		report.continuity=continuity(compiled,false)
		return report
	if result.get("fault","")!="":report.solver_error=result.fault;return report
	if not result.get("currents") is Dictionary or not result.get("voltages") is Dictionary:report.solver_error="Missing actual electrical result";return report
	for edge in compiled.stamps:
		if not edge.collapsed and not result.currents.has(edge.id):report.solver_error="Missing actual safety-branch current";return report
	if compiled.profile.topology!="explicit_bond":report.warnings.append("No source-to-PE bond was added. A zero fault current or absent trip is not a touch-safety conclusion.")
	for edge in compiled.stamps:
		var current: Vector2=Vector2.ZERO if edge.collapsed else result.currents.get(edge.id,Vector2.ZERO)
		report.stamps.append({"id":edge.id,"role":edge.role,"a":edge.a,"b":edge.b,"current_rms_amperes":current.length(),"ohms":edge.ohms})
		if edge.role=="misused_pe_terminal":report.warnings.append("A PE terminal is connected to a circuit terminal. The connection is modeled electrically but cannot count as dedicated PE continuity.")
	for item in compiled.chassis:
		var comparable := reachable(item.node,compiled.pe_bus,compiled.branches)
		var reference_comparable := reachable(item.node,compiled.source_reference,compiled.branches)
		var pe_continuous := reachable(item.node,compiled.pe_bus,compiled.pe_edges)
		var difference: Variant=(result.voltages[item.node]-result.voltages[compiled.pe_bus]).length() if comparable else null
		report.chassis.append({"id":item.id,"pe_continuous":pe_continuous,"pe_status":"connected_not_certified" if pe_continuous else "open","voltage_to_pe_rms":difference,"voltage_to_source_reference_rms":(result.voltages[item.node]-result.voltages[compiled.source_reference]).length() if reference_comparable else null,"absolute_earth_voltage_defined":false})
		if not pe_continuous:report.warnings.append("PE path open for "+str(item.id)+". No trip does not establish safety.")
		if difference!=null and float(difference)>1e-6:report.warnings.append("Chassis %s differs from PE by %.3f V RMS in this solved model. This is not a human touch-safety assessment."%[item.id,float(difference)])
	for id in source_limits:
		if not result.currents.has(id) or not Profile.number(source_limits[id],0.01,1e6):continue
		var amps: float=result.currents[id].length()
		if amps>float(source_limits[id]):report.protection_events.append({"source_branch":id,"current_rms_amperes":amps,"limit_amperes":float(source_limits[id]),"model":"existing instantaneous game overcurrent threshold"});report.trip_requested=true
	return report
static func public_evidence(report: Dictionary) -> Dictionary:
	var copy := report.duplicate(true)
	# Hide instructor fault-injection IDs and individual hidden path topology.
	copy.erase("stamps")
	return copy
