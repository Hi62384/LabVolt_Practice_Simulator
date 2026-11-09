extends RefCounted

## Additive producer hook. Copy result into pending and marked records; never
## derive an attempt or curriculum ID from the random classroom assessment ID.
static func from_project(project: Dictionary) -> Dictionary:
	var attempt: Variant = project.get("course_attempt")
	var assessment_id := str(project.get("gradebook_assessment_id", ""))
	if not (attempt is int or attempt is float) or float(attempt) != floor(float(attempt)) or int(attempt) <= 0 or assessment_id.is_empty():
		return {}
	return {"course_attempt": int(attempt), "gradebook_assessment_id": assessment_id,
		"gradebook_identity_version": 1}

## Both the class authority and gradebook use the original saved result.
static func is_official_result(record: Dictionary) -> bool:
	var score: Variant = record.get("score")
	return not record.has("pending_assessment_version") and not record.get("lesson", false) and not record.get("practice", false) and not record.get("linked_practice", false) and (score is int or score is float) and is_finite(float(score)) and float(score) >= 0 and float(score) <= 100 and str(record.get("status", "graded")).to_lower() in ["graded", "zero"]

static func precedes(a: Dictionary, b: Dictionary) -> bool:
	var time_a := str(a.get("time", ""))
	var time_b := str(b.get("time", ""))
	return time_a < time_b if time_a != time_b else str(a.get("id", "")) < str(b.get("id", ""))

static func first_result(records: Dictionary, profile: String, course: String, kind: String, assessment: String) -> Dictionary:
	var first := {}
	if profile.is_empty() or assessment.is_empty():
		return first
	for record in records.values():
		if not record is Dictionary or record.get("profile", "") != profile or record.get("course_id", "ELM253") != course:
			continue
		if record.get("kind", "lecture") != kind or not is_official_result(record):
			continue
		var id := str(record.get("gradebook_assessment_id", ""))
		if id.is_empty():
			id = "%s:%d" % [kind, int(record.get("week", 0))]
		if id == assessment and (first.is_empty() or precedes(record, first)):
			first = record
	return first

## Definitions supply an existing curriculum content week even for nonweekly grading rows.
static func extra_options(config: Dictionary, bridge: Object, course: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var definitions: Variant = config.get("assessments", [])
	if not definitions is Array:
		return options
	var ids := {}
	for definition in definitions:
		if definition is Dictionary:
			var id := str(definition.get("id", ""))
			ids[id] = int(ids.get(id, 0)) + 1
	for definition in definitions:
		if not definition is Dictionary:
			continue
		var id := str(definition.get("id", ""))
		var kind := str(definition.get("kind", ""))
		var week := int(definition.get("content_week", definition.get("week", 0)))
		var weight: Variant = definition.get("weight")
		if id.is_empty() or ids[id] != 1 or id.begins_with("lecture:") or id.begins_with("lab:"):
			continue
		if kind not in ["lecture", "lab"] or week < 1 or week > bridge.weeks(course, kind).size():
			continue
		if not (weight is int or weight is float) or not is_finite(float(weight)) or float(weight) <= 0:
			continue
		options.append({"id": id, "kind": kind, "content_week": week, "title": str(definition.get("title", id))})
	return options

## The earliest attempt with an available slot wins, as in legacy weekly progression.
## Pending obligations reserve their slots. The durable round record owns retry identity.
static func next_attempt(records: Dictionary, profile: String, course: String, assessment: String) -> int:
	var occupied := {}
	for record in records.values():
		if not record is Dictionary or str(record.get("profile", "")) != profile or str(record.get("course_id", "")) != course:
			continue
		if record.get("lesson", false) or record.get("practice", false) or record.get("linked_practice", false):
			continue
		if not record.has("score") and not record.has("pending_assessment_version"):
			continue
		var metadata := from_project(record)
		if metadata.get("gradebook_assessment_id", "") == assessment:
			occupied[int(metadata.course_attempt)] = true
	var attempt := 1
	while occupied.has(attempt):
		attempt += 1
	return attempt
