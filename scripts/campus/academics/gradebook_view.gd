extends RefCounted
const Weights = preload("res://scripts/campus/academics/grade_weight_policy.gd")
const RecordMetadata = preload("res://scripts/campus/academics/record_metadata.gd")

## Pure projection of one selected course attempt. No persistence or state mutation.
static func build(records: Dictionary, profile: String, course_id: String, tracks: Dictionary, weight_config: Dictionary, pending_records: Dictionary = {}) -> Dictionary:
	var rows: Array = []
	var config := Weights.final_weights(weight_config)
	var errors: Array = config.weight_errors
	var used_ids := {}
	for kind in ["lecture", "lab"]:
		var weeks: Variant = tracks.get(kind, [])
		var weights: Variant = config.get(kind, [])
		if not weeks is Array:
			errors.append("%s weeks unavailable" % kind)
			continue
		if not weights is Array:
			weights = []
		for index in weeks.size():
			var week: Dictionary = weeks[index] if weeks[index] is Dictionary else {}
			var number := int(week.get("week", index + 1))
			var key := "%s:%d" % [kind, number]
			if used_ids.has(key):
				errors.append("duplicate weekly assessment ID: %s" % key)
			used_ids[key] = true
			var weight: Variant = weights[index] if index < weights.size() else null
			rows.append(_row(key, kind, number, str(week.get("title", key)), weight, errors))
		if weights.size() != weeks.size():
			errors.append("%s weight count differs from week count" % kind)
	var extras: Variant = config.get("assessments", [])
	if extras is Array:
		for item in extras:
			if not item is Dictionary:
				errors.append("invalid additional assessment")
				continue
			var key := str(item.get("id", ""))
			var kind := str(item.get("kind", ""))
			if key.is_empty() or key.begins_with("lecture:") or key.begins_with("lab:") or kind not in ["lecture", "lab"] or used_ids.has(key):
				errors.append("invalid or duplicate additional assessment ID")
				continue
			used_ids[key] = true
			var week: Variant = item.get("week")
			if week != null and (not _valid_number(week) or float(week) != floorf(float(week)) or not used_ids.has("%s:%d" % [kind, int(week)])):
				errors.append("invalid week for %s" % key)
				week = null
			rows.append(_row(key, kind, week, str(item.get("title", key)), item.get("weight"), errors))
	elif config.has("assessments"):
		errors.append("additional assessments must be an array")
	var official: Array = []
	for value in records.values():
		if not value is Dictionary:
			continue
		if profile.is_empty() or str(value.get("profile", "")) != profile or str(value.get("course_id", "ELM253")) != course_id:
			continue
		if bool(value.get("lesson", false)) or bool(value.get("practice", false)) or bool(value.get("linked_practice", false)):
			continue
		official.append(value)
	official.sort_custom(RecordMetadata.precedes)
	var unmatched: Array = []
	var historical: Array = []
	for record in official:
		var assessment_id := str(record.get("gradebook_assessment_id", ""))
		var kind := str(record.get("kind", "lecture"))
		var week := int(record.get("week", 0))
		var matches: Array = []
		for index in rows.size():
			var row: Dictionary = rows[index]
			if row.kind == kind and row.id == assessment_id:
				matches.append(index)
		if matches.is_empty() and assessment_id.is_empty():
			# Legacy entries predate extra assessments. They refer to the weekly slot.
			for index in rows.size():
				var row: Dictionary = rows[index]
				if row.id == "%s:%d" % [kind, week]:
					matches.append(index)
		if matches.size() != 1:
			unmatched.append(record.duplicate(true))
			continue
		var row: Dictionary = rows[matches[0]]
		if row.completed:
			if RecordMetadata.is_official_result(record):
				historical.append(record.duplicate(true))
			continue
		var score: Variant = record.get("score")
		var status := str(record.get("status", "graded")).to_lower().replace(" ", "_")
		if status in ["not_started", "in_progress", "submitted", "not_available"]:
			row.status = status
			continue
		if not _valid_number(score) or float(score) < 0.0 or float(score) > 100.0:
			row.status = "not_available"
			continue
		row.completed = true
		row.score = float(score)
		row.status = "zero" if row.score == 0.0 else "graded"
		row.record_id = str(record.get("id", record.get("assessment_id", assessment_id)))
		row.time = str(record.get("time", ""))
		if row.weight != null:
			row.weighted_points = row.score * row.weight / 100.0
		rows[matches[0]] = row
	for pending in pending_records.values():
		if not pending is Dictionary or not pending.has("pending_assessment_version"):
			continue
		if profile.is_empty() or str(pending.get("profile", "")) != profile or str(pending.get("course_id", "")) != course_id:
			continue
		if bool(pending.get("lesson", false)) or bool(pending.get("practice", false)) or bool(pending.get("linked_practice", false)):
			continue
		var kind := str(pending.get("kind", ""))
		var week := int(pending.get("week", 0))
		var pending_id := str(pending.get("gradebook_assessment_id", ""))
		var targets: Array = []
		for index in rows.size():
			var row: Dictionary = rows[index]
			if row.kind == kind and not row.completed and ((not pending_id.is_empty() and row.id == pending_id) or (pending_id.is_empty() and row.week != null and int(row.week) == week)):
				targets.append(index)
		if targets.size() == 1:
			var row: Dictionary = rows[targets[0]]
			if row.status != "submitted":
				row.status = "submitted" if not str(pending.get("submitted_at", "")).is_empty() else "in_progress"
			rows[targets[0]] = row
	var total := 0.0
	var completed_weight := 0.0
	var earned := 0.0
	var complete := not rows.is_empty()
	var grouped := {"lecture": [], "lab": []}
	for row in rows:
		grouped[row.kind].append(row)
		complete = complete and row.completed
		if row.weight != null:
			total += row.weight
			if row.completed:
				completed_weight += row.weight
				earned += row.weighted_points
	if absf(total - 100.0) > 0.001:
		errors.append("course weights must total 100")
	var valid := errors.is_empty()
	return {"schema": "gradebook-view.v1", "course_id": course_id, "profile": profile,
		"rows": rows, "tracks": grouped, "unmatched_records": unmatched, "historical_records": historical,
		"completed_weight": completed_weight, "total_weight": total,
		"current_average": earned * 100.0 / completed_weight if valid and completed_weight > 0.0 else null,
		"earned_final_points": earned if valid else null,
		"final_mark": earned if valid and complete else null,
		"complete": complete, "passed": valid and complete and earned >= 50.0,
		"policy_valid": valid, "policy_errors": errors}

static func _row(id: String, kind: String, week: Variant, title: String, weight: Variant, errors: Array) -> Dictionary:
	var numeric: Variant = null
	if _valid_number(weight) and float(weight) > 0.0 and float(weight) <= 100.0:
		numeric = float(weight)
	else:
		errors.append("missing or invalid weight for %s" % id)
	return {"id": id, "kind": kind, "week": week, "title": title, "weight": numeric,
		"completed": false, "status": "not_started", "score": null, "weighted_points": null, "record_id": "", "time": ""}

static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
