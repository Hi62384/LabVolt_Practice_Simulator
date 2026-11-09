extends RefCounted
## Records are immutable attempts; an unattempted category has no numeric average.
static func summary(records: Dictionary, profile: String, course: String, weights: Dictionary = {}) -> Dictionary:
	var result := {"course_id":course,"lecture":null,"lab":null,"overall":null,"attempts":0,"lecture_count":0,"lab_count":0}
	var sums := {"lecture":0.0,"lab":0.0}
	for record in records.values():
		if not record is Dictionary:continue
		if str(record.get("profile",""))!=profile or bool(record.get("lesson",false)):continue
		if str(record.get("course_id","ELM253"))!=course:continue
		var score=record.get("score")
		if not (score is int or score is float):continue
		var kind := str(record.get("kind","lab"))
		if kind not in sums or not is_finite(float(record.get("score",NAN))):continue
		sums[kind]+=clampf(float(record.score),0,100)
		result[kind+"_count"]+=1
		result.attempts+=1
	var total := 0.0
	var weight_total := 0.0
	for kind in sums:
		if int(result[kind+"_count"])==0:continue
		result[kind]=sums[kind]/int(result[kind+"_count"])
		var weight := maxf(0.0,float(weights.get(kind,1.0)))
		total+=float(result[kind])*weight
		weight_total+=weight
	if weight_total>0:result.overall=total/weight_total
	return result

static func attempt_id(assessment_id: String, identity: String) -> String:
	return "assessment:"+assessment_id+":"+identity
