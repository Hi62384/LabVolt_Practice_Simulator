extends RefCounted

## Pure projection of one selected course attempt. No persistence or state mutation.
static func build(records: Dictionary, profile: String, course_id: String, tracks: Dictionary, weight_config: Dictionary, pending_records: Dictionary = {}) -> Dictionary:
	var rows: Array = []
	var errors: Array = []
	var used_ids := {}
	for kind in ["lecture", "lab"]:
		var weeks: Variant = tracks.get(kind, [])
		var weights: Variant = weight_config.get(kind, [])
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
	var extras: Variant = weight_config.get("assessments", [])
	if extras is Array:
		for item in extras:
			if not item is Dictionary:
				errors.append("invalid additional assessment")
				continue
			var key := str(item.get("id", ""))
			var kind := str(item.get("kind", ""))
			if key.is_empty() or kind not in ["lecture", "lab"] or used_ids.has(key):
				errors.append("invalid or duplicate additional assessment ID")
				continue
			used_ids[key] = true
			rows.append(_row(key, kind, item.get("week"), str(item.get("title", key)), item.get("weight"), errors))
	elif weight_config.has("assessments"):
		errors.append("additional assessments must be an array")
	var official: Array = []
	for value in records.values():
		if not value is Dictionary:
			continue
		if str(value.get("profile", "")) != profile or str(value.get("course_id", "")) != course_id:
			continue
		if bool(value.get("lesson", false)) or bool(value.get("practice", false)) or bool(value.get("linked_practice", false)):
			continue
		var score: Variant = value.get("score")
		if not _valid_number(score) or float(score) < 0.0 or float(score) > 100.0:
			continue
		official.append(value)
	official.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("time", "")) < str(b.get("time", "")))
	var unmatched: Array = []
	for record in official:
		var assessment_id := str(record.get("gradebook_assessment_id", ""))
		var kind := str(record.get("kind", ""))
		var week := int(record.get("week", 0))
		var matches: Array = []
		for index in rows.size():
			var row: Dictionary = rows[index]
			if row.kind == kind and row.id == assessment_id:
				matches.append(index)
		if matches.is_empty() and assessment_id.is_empty():
			var sibling_count := 0
			for candidate in rows:
				if candidate.kind == kind and candidate.week != null and int(candidate.week) == week:
					sibling_count += 1
			if sibling_count != 1:
				unmatched.append(record.duplicate(true))
				continue
			for index in rows.size():
				var row: Dictionary = rows[index]
				if row.kind == kind and row.week != null and int(row.week) == week and row.id.begins_with("%s:" % kind):
					matches.append(index)
		if matches.size() != 1:
			unmatched.append(record.duplicate(true))
			continue
		var row: Dictionary = rows[matches[0]]
		if row.completed:
			unmatched.append(record.duplicate(true))
			continue
		row.completed = true
		row.score = float(record.score)
		row.record_id = str(record.get("id", record.get("assessment_id", assessment_id)))
		row.time = str(record.get("time", ""))
		if row.weight != null:
			row.weighted_points = row.score * row.weight / 100.0
		rows[matches[0]] = row
	for pending in pending_records.values():
		if not pending is Dictionary or not pending.has("pending_assessment_version"):
			continue
		if str(pending.get("profile", "")) != profile or str(pending.get("course_id", "")) != course_id:
			continue
		if bool(pending.get("lesson", false)) or bool(pending.get("practice", false)):
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
			row.status = "submitted"
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
	var any_graded := false
	for row in rows:
		any_graded = any_graded or bool(row.completed)
	for index in rows.size():
		var row: Dictionary = rows[index]
		if row.completed:
			row.status = "graded"
		elif row.status != "submitted":
			row.status = "in_progress" if any_graded else "not_available"
		rows[index] = row
	return {"schema": "gradebook-view.v1", "course_id": course_id, "profile": profile,
		"rows": rows, "tracks": grouped, "unmatched_records": unmatched,
		"completed_weight": completed_weight, "total_weight": total,
		"current_average": earned * 100.0 / completed_weight if valid and completed_weight > 0.0 else null,
		"earned_final_points": earned if valid else null,
		"final_mark": earned if valid and complete else null,
		"complete": valid and complete, "passed": valid and complete and earned >= 50.0,
		"policy_valid": valid, "policy_errors": errors}

static func _row(id: String, kind: String, week: Variant, title: String, weight: Variant, errors: Array) -> Dictionary:
	var numeric: Variant = null
	if _valid_number(weight) and float(weight) > 0.0 and float(weight) <= 100.0:
		numeric = float(weight)
	else:
		errors.append("missing or invalid weight for %s" % id)
	return {"id": id, "kind": kind, "week": week, "title": title, "weight": numeric,
		"completed": false, "status": "not_available", "score": null, "weighted_points": null, "record_id": "", "time": ""}

static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
