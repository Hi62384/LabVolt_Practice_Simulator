extends RefCounted
## Optional adapter around the SAME integrated host grader. The caller must own
## equipment capture; this function is never an RPC or a client authority check.
const Evidence=preload("res://scripts/campus/academics/equipment_evidence.gd")
static func validate(assignment: Dictionary,captured: Dictionary) -> Dictionary:
	if assignment.get("course_id","")!="ETY155":return {"ok":false,"error":"Use the integrated campus AC equipment adapter"}
	if not captured.get("parts") is Array or not captured.get("wires",[]) is Array:return {"ok":false,"error":"Host-captured actual parts and wires required"}
	var actual: Array=captured.parts
	if actual.size()>96:return {"ok":false,"error":"Equipment solver budget exceeded"}
	var expected_sources: int=assignment.get("reference_parts",[]).filter(func(part):return part.kind=="I").size()
	if expected_sources>0 and actual.filter(func(part):return part.kind=="current_source").size()<expected_sources:return {"ok":false,"error":"Actual physical current-source modules required"}
	var adapter := Evidence.new()
	var verified := adapter.snapshot(actual,captured.get("wires",[]),assignment)
	if verified.has("error"):return {"ok":false,"error":verified.error}
	for source in actual:
		if source.kind=="current_source" and verified.get("result",{}).get("mode",{}).get(source.id,"")!="CC":return {"ok":false,"error":"Physical current source is outside compliance"}
	verified.observations=captured.get("observations",{}).duplicate(true)
	verified.verified_procedure=captured.get("verified_procedure",[]).duplicate()
	var marked := adapter.grade(assignment,verified)
	marked.ok=true;marked.scope="practical_only";marked.solver="shared electronics_solver.gd"
	return marked
