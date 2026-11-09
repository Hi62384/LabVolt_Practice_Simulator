extends RefCounted
## Save-compatible projection of immutable official records into weighted course attempts.
const PASS_MARK := 50.0
static func summarize(records: Dictionary, profile: String, course: String, requirements: Dictionary, configured_weights: Dictionary) -> Dictionary:
	var slots := _required_slots(requirements);var policy := _validate_weights(slots,configured_weights);var grading_total := float(policy.total) if policy.errors.is_empty() else -1.0
	var buckets: Array=[];var ordered := _official_records(records,profile,course,slots);var ordering_reliable := true
	for record in ordered:
		ordering_reliable=ordering_reliable and bool(record.get("_time_valid",false))
		var slot := _slot(record);var target := -1
		record.is_exam=_is_exam_slot(slot,requirements)
		var explicit := int(record.get("course_attempt",0))-1
		if explicit>=0:
			while buckets.size()<=explicit:buckets.append(_empty_attempt(slots))
			if buckets[explicit].records.has(slot):continue
			target=explicit
		else:
			for i in buckets.size():
				if not bool(buckets[i].complete) and not buckets[i].records.has(slot):target=i;break
		if target<0:buckets.append(_empty_attempt(slots));target=buckets.size()-1
		buckets[target].records[slot]=record.duplicate(true);buckets[target].completed_slots[slot]=true
		buckets[target].complete=buckets[target].completed_slots.size()==slots.size() and not slots.is_empty()
	var attempts: Array=[];var open_attempts: Array=[]
	for bucket in buckets:
		var finished := _finish(bucket,policy.weights,attempts.size()+open_attempts.size()+1,grading_total)
		if finished.complete:attempts.append(finished)
		else:open_attempts.append(finished)
	var current: Dictionary=open_attempts[-1] if not open_attempts.is_empty() else _empty_attempt(slots)
	var best: Variant=null;var best_attempt := 0
	for attempt in attempts:
		if attempt.final_mark!=null and (best==null or float(attempt.final_mark)>float(best)):best=attempt.final_mark;best_attempt=int(attempt.number)
	return {"course_id":course,"pass_mark":PASS_MARK,"required_slots":slots.size(),"completed_attempts":attempts,"open_attempts":open_attempts,"current_attempt":current,"final_mark":best,"best_attempt":best_attempt,"passed":best!=null and float(best)>=PASS_MARK,"status":"in_progress" if not open_attempts.is_empty() else ("passed" if best!=null and float(best)>=PASS_MARK else ("failed" if best!=null else "not_started")),"weight_total":policy.total,"weight_errors":policy.errors,"weight_policy_valid":policy.errors.is_empty(),"exam_weight_policy":"configured_per_assessment","ordering_reliable":ordering_reliable,"ordering_fallback":"stable_record_id" if not ordering_reliable else "stored_timestamp"}
static func weights_from_tracks(tracks: Dictionary) -> Dictionary:
	var result := {}
	for kind in ["lecture","lab"]:
		var values: Variant=tracks.get(kind,[])
		if not values is Array:continue
		for i in values.size():result["%s:%d"%[kind,i+1]]=values[i]
	return result
static func _required_slots(requirements: Dictionary) -> Array:
	var slots: Array=[]
	for kind in ["lecture","lab"]:
		for week in range(1,maxi(0,int(requirements.get(kind,0)))+1):slots.append("%s:%d"%[kind,week])
	return slots
static func _official_records(records: Dictionary, profile: String, course: String, slots: Array) -> Array:
	var result: Array=[]
	for key in records:
		var record: Variant=records[key]
		if not record is Dictionary:continue
		if str(record.get("profile",""))!=profile or str(record.get("course_id","ELM253"))!=course:continue
		var curriculum_id := str(record.get("gradebook_assessment_id", ""))
		if not curriculum_id.is_empty() and curriculum_id != _slot(record):continue
		if bool(record.get("lesson",false)) or bool(record.get("practice",false)) or bool(record.get("linked_practice",false)):continue
		if not (record.get("score") is int or record.get("score") is float) or not is_finite(float(record.score)) or _slot(record) not in slots:continue
		var stable_id := str(record.get("assessment_id",record.get("id",key)))
		var copy: Dictionary=record.duplicate(true);copy["_stable_id"]=stable_id;copy["_time_valid"]=Time.get_unix_time_from_datetime_string(str(record.get("time","")))>0;result.append(copy)
	result.sort_custom(func(a,b):return str(a.get("time",""))+"|"+str(a.get("_stable_id",""))<str(b.get("time",""))+"|"+str(b.get("_stable_id","")))
	var unique: Array=[];var seen := {}
	for record in result:
		if str(record._stable_id) in seen:continue
		seen[str(record._stable_id)]=true;unique.append(record)
	return unique
static func _empty_attempt(slots: Array) -> Dictionary:
	return {"number":0,"records":{},"completed_slots":{},"required_slots":slots.size(),"complete":false,"lecture":null,"lab":null,"running_mark":null,"earned_to_date":0.0,"completed_weight":0.0,"final_mark":null,"passed":false,"exams":{}}
static func _finish(attempt: Dictionary, weights: Dictionary, number: int, total_weight: float) -> Dictionary:
	attempt.number=number;var sums := {"lecture":0.0,"lab":0.0};var weight_sums := {"lecture":0.0,"lab":0.0}
	for slot in attempt.records:
		var record: Dictionary=attempt.records[slot];var kind := str(record.get("kind","lecture"));var weight := float(weights.get(slot,0.0))
		sums[kind]+=clampf(float(record.score),0.0,100.0)*weight;weight_sums[kind]+=weight
		if bool(record.get("is_exam",false)):attempt.exams[kind]=record.duplicate(true)
	var weighted := 0.0;var completed_weight := 0.0
	for kind in ["lecture","lab"]:
		if weight_sums[kind]<=0:continue
		attempt[kind]=sums[kind]/weight_sums[kind];weighted+=sums[kind];completed_weight+=weight_sums[kind]
	attempt.completed_weight=completed_weight;attempt.running_mark=weighted/completed_weight if completed_weight>0 else null
	attempt.earned_to_date=weighted/total_weight if total_weight>0 else 0.0
	if bool(attempt.complete) and is_equal_approx(completed_weight,total_weight):attempt.final_mark=weighted/total_weight
	attempt.passed=attempt.final_mark!=null and float(attempt.final_mark)>=PASS_MARK
	return attempt
static func _slot(record: Dictionary) -> String:return "%s:%d"%[str(record.get("kind","lecture")),int(record.get("week",0))]
static func _is_exam_slot(slot: String, requirements: Dictionary) -> bool:
	for kind in ["lecture","lab"]:
		if int(requirements.get(kind,0))>0 and slot=="%s:%d"%[kind,int(requirements[kind])]:return true
	return false
static func _validate_weights(slots: Array, configured: Dictionary) -> Dictionary:
	var result := {"weights":{},"total":0.0,"errors":[]}
	for slot in slots:
		var value: Variant=configured.get(slot)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<=0:result.errors.append("Missing or invalid positive weight for "+slot);continue
		result.weights[slot]=float(value);result.total+=float(value)
	if not is_equal_approx(float(result.total),100.0):result.errors.append("Course weights must total 100%%; got %.6f%%"%float(result.total))
	return result
