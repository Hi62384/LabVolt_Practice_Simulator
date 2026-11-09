extends RefCounted
const View = preload("res://scripts/campus/academics/gradebook_view.gd")

## Explicit versioned attempt IDs preserve multiple assessments in one week.
## Legacy records are returned separately when mixed with explicit attempts.
static func select(records: Dictionary, profile: String, course_id: String, tracks: Dictionary, config: Dictionary, pending: Dictionary = {}) -> Dictionary:
	var buckets := {}
	var ambiguous: Array = []
	for value in records.values():
		if not value is Dictionary or str(value.get("profile", "")) != profile or str(value.get("course_id", "")) != course_id:
			continue
		if bool(value.get("lesson", false)) or bool(value.get("practice", false)) or bool(value.get("linked_practice", false)):
			continue
		if not value.has("score"):
			continue
		var attempt := int(value.get("course_attempt", 0))
		if attempt <= 0:
			ambiguous.append(value.duplicate(true))
			continue
		if not buckets.has(attempt):
			buckets[attempt] = {}
		var key := str(value.get("id", ""))
		if key.is_empty():
			ambiguous.append(value.duplicate(true))
		else:
			buckets[attempt][key] = value
	var attempts: Array = []
	var numbers: Array = buckets.keys()
	numbers.sort()
	var best: Variant = null
	var best_number := 0
	for number in numbers:
		var view: Dictionary = View.build(buckets[number], profile, course_id, tracks, config)
		view["attempt_number"] = int(number)
		attempts.append(view)
		if view.final_mark != null and (best == null or float(view.final_mark) > float(best)):
			best = view.final_mark
			best_number = int(number)
	var chosen: Dictionary = attempts.back() if not attempts.is_empty() else {}
	for view in attempts:
		if not view.complete:
			chosen = view
	if bool(chosen.get("complete", false)) and best_number > 0:
		for view in attempts:
			if int(view.attempt_number) == best_number:
				chosen = view
				break
	if chosen.is_empty():
		chosen = View.build({}, profile, course_id, tracks, config)
		chosen["attempt_number"] = 0
	var pending_attempt := 0
	for item in pending.values():
		if item is Dictionary and item.has("pending_assessment_version") and str(item.get("profile", "")) == profile and str(item.get("course_id", "")) == course_id and not item.get("practice", false) and not item.get("lesson", false) and not item.get("linked_practice", false):
			pending_attempt = maxi(pending_attempt, int(item.get("course_attempt", 0)))
	if pending_attempt > int(chosen.attempt_number):
		chosen = View.build({}, profile, course_id, tracks, config)
		chosen["attempt_number"] = pending_attempt
	if int(chosen.attempt_number) > 0:
		var chosen_number := int(chosen.attempt_number)
		var selected_pending := {}
		for key in pending:
			var item: Variant = pending[key]
			if item is Dictionary and int(item.get("course_attempt", 0)) == chosen_number:
				selected_pending[key] = item
		chosen = View.build(buckets.get(chosen_number, {}), profile, course_id, tracks, config, selected_pending)
		chosen["attempt_number"] = chosen_number
	chosen["best_completed_attempt"] = best_number
	chosen["best_completed_mark"] = best
	chosen["attempts"] = attempts
	chosen["ambiguous_legacy_records"] = ambiguous
	chosen["identity_status"] = "ambiguous_legacy" if not ambiguous.is_empty() else "explicit"
	return chosen
