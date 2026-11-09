extends RefCounted
## Pure owner-bound attempt state. Integrator persists `state` atomically using its
## existing host save system; this module never pays rewards or writes profiles.
const Provider = preload("res://scripts/mth147/provider.gd")
const Grader = preload("res://scripts/mth147/grader.gd")

static func issue(state: Dictionary,attempt_id: String,owner_id: String,request: Dictionary,now_seconds: int,practice: bool=false) -> Dictionary:
	if attempt_id.is_empty() or attempt_id.length()>96 or owner_id.is_empty() or owner_id.length()>96:return {"error":"Invalid attempt identity."}
	if state.has(attempt_id):return reopen(state,attempt_id,owner_id)
	var assignment := Provider.generate(int(request.get("week",1)),int(request.get("difficulty",2)),int(request.get("seed",147)),int(request.get("count",8)),str(request.get("focus","")))
	if assignment.has("error"):return assignment
	var timer := clampi(int(request.get("seconds",assignment.assessment_policy.default_seconds)),60,7200)
	state[attempt_id]={"version":1,"id":attempt_id,"owner":owner_id,"assignment":assignment,"answers":{},"workspace":{},"issued_at":now_seconds,"deadline":now_seconds+timer,"practice":practice,"status":"active","result":{},"academic_event_id":"MTH147:"+attempt_id}
	return reopen(state,attempt_id,owner_id)

static func reopen(state: Dictionary,attempt_id: String,owner_id: String) -> Dictionary:
	if not state.has(attempt_id) or str(state[attempt_id].owner)!=owner_id:return {"error":"Attempt owner mismatch."}
	var entry: Dictionary=state[attempt_id]
	return {"id":attempt_id,"assignment":Provider.public_copy(entry.assignment,entry.status!="active"),"answers":entry.answers.duplicate(true),"workspace":entry.workspace.duplicate(true),"deadline":entry.deadline,"status":entry.status,"practice":entry.practice,"result":entry.result.duplicate(true)}

static func save_answers(state: Dictionary,attempt_id: String,owner_id: String,answers: Dictionary,workspace: Dictionary,now_seconds: int) -> Dictionary:
	if not state.has(attempt_id) or str(state[attempt_id].owner)!=owner_id:return {"error":"Attempt owner mismatch."}
	var entry: Dictionary=state[attempt_id]
	if entry.status!="active" or now_seconds>int(entry.deadline):return {"error":"Assessment is closed or its original deadline passed."}
	if not Grader.safe_answer(answers) or JSON.stringify(workspace).length()>262144:return {"error":"Answers or saved worksheet exceed bounded limits."}
	var accepted := {}
	for i in range(entry.assignment.questions.size()):
		var id := str(entry.assignment.questions[i].id)
		if answers.has(id):accepted[id]=answers[id]
		elif answers.has(str(i)):accepted[id]=answers[str(i)]
	entry.answers=accepted.duplicate(true);entry.workspace=workspace.duplicate(true)
	return {"ok":true,"deadline":entry.deadline}

static func finish(state: Dictionary,attempt_id: String,owner_id: String,reason: String,now_seconds: int) -> Dictionary:
	if not state.has(attempt_id) or str(state[attempt_id].owner)!=owner_id:return {"error":"Attempt owner mismatch."}
	var entry: Dictionary=state[attempt_id]
	if entry.status!="active":return {"ok":true,"duplicate":true,"result":entry.result.duplicate(true),"academic_event":{}}
	if reason not in ["submit","timeout","abandon_confirmed","dispose_confirmed","host_cancel"]:return {"error":"Use the existing academic policy to authorize an assessment end reason."}
	if reason=="timeout" and now_seconds<int(entry.deadline):return {"error":"Original deadline has not elapsed."}
	if reason=="submit" and now_seconds>int(entry.deadline):reason="timeout"
	var result := Provider.grade(entry.assignment,entry.answers)
	if result.has("error"):return result
	if reason in ["abandon_confirmed","dispose_confirmed"]:result.score=0.0;result.policy_zero=true
	entry.result=result;entry.status="cancelled" if reason=="host_cancel" else "completed";entry.finished_at=now_seconds;entry.reason=reason
	var event := {}
	if not bool(entry.practice) and reason!="host_cancel":event={"id":entry.academic_event_id,"course_id":"MTH147","kind":"lecture","lesson":false,"attempt_id":attempt_id,"owner":owner_id,"score":result.score,"week":entry.assignment.week,"difficulty":entry.assignment.difficulty,"date_seconds":now_seconds,"reason":reason,"reward_policy":"existing academic ledger consumes this id once; this module never pays"}
	return {"ok":true,"duplicate":false,"result":result.duplicate(true),"academic_event":event}

static func validate_saved(state: Dictionary) -> Dictionary:
	if state.size()>256:return {"error":"Too many active saved attempt entries."}
	for id in state:
		var entry: Variant=state[id]
		if not entry is Dictionary or str(entry.get("id",""))!=str(id) or entry.get("owner","")=="":return {"error":"Corrupt attempt identity."}
		var assignment := Provider.restore(entry.get("assignment",{}))
		if assignment.has("error"):return assignment
	return {"ok":true}
