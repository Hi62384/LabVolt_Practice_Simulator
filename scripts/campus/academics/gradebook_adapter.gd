extends RefCounted
const View = preload("res://scripts/campus/academics/gradebook_view.gd")
const Weights = preload("res://scripts/campus/academics/grade_weight_policy.gd")

static func from_school(school: Object, course_id: String, pending: Dictionary) -> Dictionary:
	var bridge: Object = school.get("course_bridge")
	var tracks := {"lecture": bridge.weeks(course_id, "lecture"), "lab": bridge.weeks(course_id, "lab")}
	return View.build(school.get("gradebook"), str(school.get("local_identity")), course_id, tracks, Weights.course(course_id), pending)
