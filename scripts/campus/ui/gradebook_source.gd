extends RefCounted
const GradebookAdapter = preload("res://scripts/campus/academics/gradebook_adapter.gd")

static func from_school(school: Object, pending: Dictionary) -> Dictionary:
	var bridge: Object = school.get("course_bridge")
	var model: Dictionary = school.menu_catalog()
	var descriptions := {}
	for definition in bridge.catalog():
		var id := str(definition.get("id", definition.get("course_id", "")))
		descriptions[id] = str(definition.get("description", ""))
	for course in model.courses:
		course.description = descriptions.get(course.course_id, "")
		course.gradebook = GradebookAdapter.from_school(school, course.course_id, pending)
	return model
