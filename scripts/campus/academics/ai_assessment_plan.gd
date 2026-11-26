extends RefCounted
## The model authors the focus and variation of a class assessment. The course
## provider compiles that plan into verified questions, instruments and keys.
const FOCUS := {
	"method":"Show the method you used and check your result against the data.",
	"evidence":"Use the given data and label the evidence that supports each result.",
	"comparison":"Compare your result with the given conditions and explain any differences in your working."
}
const KEPT_FIELDS := ["assessment_id","official_curriculum_id","official_assessment_title","assessment_policy","course_attempt","gradebook_assessment_id","gradebook_identity_version"]

static func prompt(project: Dictionary, board: Dictionary) -> String:
	var context := {
		"course":project.get("course_id",""),"week":project.get("week",0),
		"format":project.get("kind",""),"difficulty":project.get("difficulty",0),
		"title":str(project.get("title","")).left(160),
		"lesson":str(board.get("title","")).left(120),
		"worked_material":str(board.get("text","")).left(600)
	}
	return "Prepare a new classroom assessment plan based on this lesson. The game's course engine builds and checks the actual problems. Select a focus: method for solving and checking, evidence for observation and lab work, or comparison for interpretation. Choose three distinct scenario integers from 1 through 4096 for varied problems. Reply with exactly one JSON object like {\"focus\":\"evidence\",\"scenarios\":[37,526,1044]}. No markdown, keys, grades or measurements beyond that object. Course context: %s" % JSON.stringify(context)

static func parse(text: String) -> Dictionary:
	if text.length()>256:return {}
	var raw: Variant=JSON.parse_string(text)
	if not raw is Dictionary or raw.size()!=2 or not raw.get("focus") is String or not FOCUS.has(raw.focus):
		return {}
	var scenarios: Variant=raw.get("scenarios")
	if not scenarios is Array or scenarios.size()!=3:return {}
	var selected: Array[int]=[]
	for value in scenarios:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floorf(float(value)) or value<1 or value>4096 or int(value) in selected:
			return {}
		selected.append(int(value))
	return {"focus":raw.focus,"scenarios":selected}

static func plan(client: Node, state: Dictionary, project: Dictionary, board: Dictionary, current: Callable) -> Dictionary:
	var accepted: Dictionary=state.get("approved",{})
	if not accepted.is_empty():return accepted
	var now:=Time.get_ticks_msec()
	var started: int=state.get_or_add("started_at",now)
	if not is_instance_valid(client) or not client.verified_for_class() or now-started>=22000:
		return _approve(state,_standard_plan(project))
	if state.get("pending",false):return {}
	state.status="Preparing the assessment…"
	if not client.busy:
		state.pending=true
		_request(client,state,project,board,current)
	return {}

static func _request(client: Node, state: Dictionary, project: Dictionary, board: Dictionary, current: Callable) -> void:
	var result: Dictionary=await client.respond(prompt(project,board),18.0)
	if not current.is_valid() or not current.call() or not state.get("pending",false):return
	var accepted:=parse(str(result.get("text",""))) if result.get("ok",false) else {}
	_approve(state,_standard_plan(project) if accepted.is_empty() else accepted)

static func _standard_plan(project: Dictionary) -> Dictionary:
	return {"focus":"evidence" if project.get("kind","")=="lab" else "method","scenarios":[37,526,1044]}

static func _approve(state: Dictionary,accepted: Dictionary) -> Dictionary:
	accepted.salt=Crypto.new().generate_random_bytes(16).hex_encode()
	state.approved=accepted
	state.pending=false
	state.status=""
	return accepted

static func compile(provider: Object, original: Dictionary, plan: Dictionary, salt: String) -> Dictionary:
	for scenario in plan.scenarios:
		var seed_value := ("%s:%s:%d"%[plan.salt,salt,scenario]).sha256_text().left(7).hex_to_int()
		var generated: Dictionary=provider.generate(str(original.course_id),int(original.week),str(original.kind),int(original.get("difficulty",0)),seed_value)
		if generated.is_empty() or generated.has("error") or generated.get("questions",[]).is_empty() or generated.get("practical",{}).get("blocked",false):
			continue
		# A lab's assessed evidence type and an official course's progression never
		# depend on model output.
		var original_practical: Dictionary=original.get("practical",{})
		var practical: Dictionary=generated.get("practical",{})
		if original_practical.is_empty()!=practical.is_empty() or original_practical.get("type","")!=practical.get("type",""):
			continue
		for field in KEPT_FIELDS:
			if original.has(field):generated[field]=original[field]
		if original.has("official_assessment_title"):generated.title=original.official_assessment_title
		generated.assessment_focus=FOCUS[plan.focus]
		return generated
	return {}
