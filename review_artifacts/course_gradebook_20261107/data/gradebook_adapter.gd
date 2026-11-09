extends RefCounted
const View = preload("res://review_artifacts/course_gradebook_20261107/data/gradebook_view.gd")
const Progression = preload("res://scripts/campus/academics/course_progression_adapter.gd")
const Weights = preload("res://scripts/campus/academics/grade_weight_policy.gd")
const Explicit = preload("res://review_artifacts/course_gradebook_20261107/data/attempt_selector.gd")

## Maps the real SchoolSession fields to a selected, isolated attempt.
static func from_school(school: Object, course_id: String) -> Dictionary:
	var records: Dictionary = school.get("gradebook")
	var profile := str(school.get("local_identity"))
	var bridge: Object = school.get("course_bridge")
	var tracks := {"lecture": bridge.weeks(course_id, "lecture"), "lab": bridge.weeks(course_id, "lab")}
	var config := Weights.course(course_id)
	var archive: Dictionary = school.get("archive")
	var pending: Dictionary = archive.get(profile, {})
	var has_explicit := false
	for value in records.values():
		if value is Dictionary and str(value.get("profile", "")) == profile and str(value.get("course_id", "")) == course_id and int(value.get("course_attempt", 0)) > 0:
			has_explicit = true
			break
	if has_explicit:
		return Explicit.select(records, profile, course_id, tracks, config, pending)
	var projection: Dictionary = Progression.summary(records, profile, course_id, bridge)
	var attempt: Dictionary = projection.get("current_attempt", {})
	if attempt.get("records", {}).is_empty():
		for candidate in projection.get("completed_attempts", []):
			if int(candidate.get("number", 0)) == int(projection.get("best_attempt", 0)):
				attempt = candidate
				break
	var selected := {}
	for slot in attempt.get("records", {}):
		var record: Dictionary = attempt.records[slot]
		selected[str(record.get("id", slot))] = record
	var result := View.build(selected, profile, course_id, tracks, config, pending)
	result["attempt_number"] = int(attempt.get("number", 0))
	result["best_completed_attempt"] = int(projection.get("best_attempt", 0))
	result["best_completed_mark"] = projection.get("final_mark")
	result["retake_status"] = str(projection.get("status", "not_started"))
	result["ordering_reliable"] = bool(projection.get("ordering_reliable", true))
	result["source_record_count"] = selected.size()
	result["identity_status"] = "legacy_weekly"
	result["ambiguous_legacy_records"] = []
	var known := {}
	for candidate in projection.get("completed_attempts", []) + projection.get("open_attempts", []):
		for slot in candidate.get("records", {}):
			var source: Dictionary = candidate.records[slot]
			known[str(source.get("id", ""))] = true
	for value in records.values():
		if value is Dictionary and str(value.get("profile", "")) == profile and str(value.get("course_id", "")) == course_id and not bool(value.get("lesson", false)) and not bool(value.get("practice", false)) and value.has("score") and not known.has(str(value.get("id", ""))):
			result.ambiguous_legacy_records.append(value.duplicate(true))
	if not result.ambiguous_legacy_records.is_empty():
		result.identity_status = "ambiguous_legacy"
	return result
