extends RefCounted
## Host-side preparation only. Never mutates gradebooks or student profiles.
const ROOMS := {"ac_lab":"ELM253","dc_lab":"ETY155"}
const SAFE_WEEKS := {"ELM253":[1,2,3,4,5,6,7],"ETY155":[1,2,3,4,5,6,7,8,9,10,11]}
const STUDY_WEEKS := {"MTH147":9,"MTH255":10}
static func course_for_room(room_id: String) -> String:
	return str(ROOMS.get(room_id,""))
static func issue_for_room(room_id: String, provider: Object, seed_value: int) -> Dictionary:
	return issue_for_course(course_for_room(room_id),provider,seed_value)
static func issue_for_course(course_id: String, provider: Object, seed_value: int) -> Dictionary:
	if not is_instance_valid(provider) or not provider.has_method("generate"):return {"error":"Unsupported practice provider."}
	var mathematics := STUDY_WEEKS.has(course_id)
	if not mathematics and not SAFE_WEEKS.has(course_id):return {"error":"Unsupported practice course."}
	var choices: Array=SAFE_WEEKS.get(course_id,[])
	var week: int=posmod(seed_value,int(STUDY_WEEKS[course_id]))+1 if mathematics else int(choices[posmod(seed_value,choices.size())])
	var kind := "lecture" if mathematics else "lab"
	var project: Dictionary=provider.call("generate",course_id,week,kind,2,seed_value)
	if project.is_empty() or project.has("error") or project.get("questions",[]).is_empty():return {"error":"No supported practical worksheet was generated."}
	if str(project.get("course_id",""))!=course_id or str(project.get("kind",""))!=kind:return {"error":"Generator returned the wrong course or track."}
	var steps := str(project.get("procedure",""))
	var data := str(project.get("data",""))
	if not mathematics and (steps.is_empty() or data.is_empty() or str(project.get("theory","")).is_empty()):return {"error":"Generated practice lacks required teaching content."}
	project=project.duplicate(true)
	project.title="Practice · "+str(project.get("title",course_id))
	project.practice_scope="ungraded"
	project.practice=true
	project.is_exam=false;project.assessment_type="practice";project.grade_weight=null
	project.assessment_policy={"practice_never_official":true,"gradebook_owner":"none","assessment_seconds":0}
	if mathematics:
		project.learning_objective="Study the generated unit and explain your solution method."
		project.verification="Use optional practice feedback; this worksheet does not count toward a course mark."
	else:
		project.learning_objective="Predict, build, measure and explain the assigned "+course_id+" circuit."
		project.practical_tasks=steps
		project.observations="Record measured voltage/current and compare signed values, units and expected tolerances with your prediction."
		project.verification="Use the generated question targets and the simulator's actual connected instrument readings; explain any difference."
	return project
