extends RefCounted

## Additive producer hook. Copy result into pending and marked records; never
## derive an attempt or curriculum ID from the random classroom assessment ID.
static func from_project(project: Dictionary) -> Dictionary:
	var attempt: Variant = project.get("course_attempt")
	var assessment_id := str(project.get("gradebook_assessment_id", ""))
	if not attempt is int or int(attempt) <= 0 or assessment_id.is_empty():
		return {}
	return {"course_attempt": int(attempt), "gradebook_assessment_id": assessment_id,
		"gradebook_identity_version": 1}
