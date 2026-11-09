extends RefCounted
## Host-authored exercise data only. No unknown topology is silently completed.
const MAX_CHASSIS := 8
const MAX_PATHS := 24
const MAX_FAULTS := 8
static func number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high
static func name_ok(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length()<=64 and not value.contains("\n") and not value.contains("\r")
static func validate(profile: Dictionary) -> Dictionary:
	if profile.is_empty():return {"ok":true,"enabled":false}
	for key in profile:
		if key not in ["schema","enabled","topology","pe_bus","source_reference","pe_lead_ohms","continuity_bound_ohms","chassis","paths","faults","source_bond","assumptions"]:return bad("Unknown protective-earth field")
	if not profile.get("schema") is int or profile.schema!=1 or not profile.get("enabled") is bool:return bad("Invalid protective-earth schema or switch")
	if profile.has("assumptions") and (not profile.assumptions is String or profile.assumptions.length()>1024):return bad("Invalid assumption label")
	if profile.get("topology","") not in ["unspecified","isolated","explicit_bond"]:return bad("Select an explicit supply-topology status")
	for field in ["pe_bus","source_reference"]:
		if not name_ok(profile.get(field)):return bad("Invalid "+field)
	if profile.pe_bus=="0":return bad("Numerical reference0 is not a physical PE socket")
	if not number(profile.get("pe_lead_ohms"),0.01,1e6):return bad("PE lead resistance must be explicitly bounded")
	if not number(profile.get("continuity_bound_ohms"),0.01,100):return bad("Invalid exercise continuity bound")
	for field in ["chassis","paths","faults"]:
		if not profile.get(field) is Array:return bad("Missing "+field+" list")
	if profile.chassis.size()>MAX_CHASSIS or profile.paths.size()>MAX_PATHS or profile.faults.size()>MAX_FAULTS:return bad("Protective-earth model budget exceeded")
	var names := {}
	for chassis in profile.chassis:
		if not chassis is Dictionary or not name_ok(chassis.get("id")) or not name_ok(chassis.get("terminal")) or not number(chassis.get("bond_ohms"),0.01,1e6):return bad("Invalid declared chassis bond")
		for key in chassis:
			if key not in ["id","terminal","bond_ohms","bond_enabled"]:return bad("Unknown chassis field")
		if chassis.has("bond_enabled") and not chassis.bond_enabled is bool:return bad("Invalid internal-bond switch")
		if names.has(chassis.id):return bad("Duplicate chassis ID")
		names[chassis.id]=true
	var ids := {}
	for list in [profile.paths,profile.faults]:
		for edge in list:
			if not edge is Dictionary or not name_ok(edge.get("id")) or not name_ok(edge.get("a")) or not name_ok(edge.get("b")) or not edge.get("enabled") is bool or not number(edge.get("ohms"),0.01,1e6):return bad("Invalid path/fault stamp")
			if ids.has(edge.id):return bad("Duplicate path/fault ID")
			for key in edge:
				if key not in ["id","a","b","ohms","enabled"]:return bad("Unknown path/fault field")
			ids[edge.id]=true
	var bond: Variant=profile.get("source_bond",{})
	if not bond is Dictionary:return bad("Invalid source bond")
	for key in bond:
		if key not in ["confirmed","ohms"]:return bad("Unknown source-bond field")
	if profile.topology=="explicit_bond":
		if not bond.get("confirmed") is bool or bond.confirmed!=true or not number(bond.get("ohms"),0.01,1e6):return bad("Source bond requires explicit host confirmation and resistance")
	elif not bond.is_empty():return bad("No source bond is permitted for isolated/unspecified topology")
	return {"ok":true,"enabled":profile.enabled}
static func bad(reason: String) -> Dictionary:return {"ok":false,"enabled":false,"error":reason}
static func example(topology: String="unspecified") -> Dictionary:
	# Explicit pedagogical assumptions, not verified trainer internal wiring.
	var data := {"schema":1,"enabled":true,"topology":topology,"pe_bus":"EARTH","source_reference":"P_N","pe_lead_ohms":0.2,"continuity_bound_ohms":0.5,"chassis":[{"id":"IGBT","terminal":"IGBT_EARTH","bond_ohms":0.05}],"paths":[],"faults":[],"source_bond":{},"assumptions":"Educational conductive chassis; finite resistive loop only. No verified rack bond or touch-safety conclusion."}
	if topology=="explicit_bond":data.source_bond={"confirmed":true,"ohms":0.1}
	return data
