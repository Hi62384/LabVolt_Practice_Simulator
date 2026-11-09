extends RefCounted
const PATH := "res://assets/campus/courses/grade_weights.json"
static func course(course_id: String) -> Dictionary:
	var root: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not root is Dictionary:return {}
	var value: Variant=root.get("courses",{}).get(course_id,{})
	return value.duplicate(true) if value is Dictionary else {}

## By default all weights are final-course percentages. With "weight_basis":
## "category", lecture and lab arrays and their extra assessments each total
## 100 within the track. "category_weights" gives each track's course share.
static func final_weights(config: Dictionary) -> Dictionary:
	var result := config.duplicate(true)
	var errors: Array[String] = []
	result.weight_errors = errors
	var basis: Variant = config.get("weight_basis", "final")
	if basis == "final":
		return result
	if basis != "category":
		errors.append("Unknown weight basis")
	var shares: Variant = config.get("category_weights", {})
	var totals := {"lecture": 0.0, "lab": 0.0}
	for kind in totals:
		var weights: Variant = result.get(kind, [])
		if weights is Array:
			for index in weights.size():
				var weight: Variant = weights[index]
				if _valid_weight(weight):
					totals[kind] += float(weight)
				weights[index] = _final_weight(weight, shares, kind, basis)
	var extras: Variant = result.get("assessments", [])
	if extras is Array:
		for entry in extras:
			if not entry is Dictionary:
				continue
			var kind := str(entry.get("kind", ""))
			var weight: Variant = entry.get("weight")
			if totals.has(kind) and _valid_weight(weight):
				totals[kind] += float(weight)
			entry.weight = _final_weight(weight, shares, kind, basis)
	if basis == "category":
		for kind in totals:
			var share: Variant = shares.get(kind) if shares is Dictionary else null
			if totals[kind] == 0.0 and (share == null or share == 0):
				continue
			if not _valid_weight(share) or absf(float(totals[kind]) - 100.0) > 0.001:
				errors.append("Invalid %s share or assessment weights" % kind)
		if not shares is Dictionary or shares.keys().any(func(key): return not totals.has(key)):
			errors.append("Unknown or missing grading categories")
	return result

static func _final_weight(weight: Variant, shares: Variant, kind: String, basis: Variant) -> Variant:
	var share: Variant = shares.get(kind) if shares is Dictionary else null
	if basis == "category" and _valid_weight(weight) and _valid_weight(share):
		return float(weight) * float(share) / 100.0
	return null

static func _valid_weight(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0 and float(value) <= 100.0
static func decorate(course_id: String, kind: String, rows: Array) -> Array:
	var result := rows.duplicate(true);var values: Variant=final_weights(course(course_id)).get(kind,[])
	for i in result.size():
		result[i].is_exam=i==result.size()-1
		result[i].assessment_type="exam" if result[i].is_exam else "assignment"
		result[i].grade_weight=float(values[i]) if values is Array and i<values.size() and (values[i] is int or values[i] is float) else null
		if result[i].is_exam and not str(result[i].get("title","")).ends_with(" exam"):result[i].title="%s exam"%str(result[i].title)
	return result
