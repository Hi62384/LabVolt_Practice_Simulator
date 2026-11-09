extends RefCounted
const Catalog = preload("res://scripts/campus/academics/course_progression_adapter.gd")
const GradebookAdapter = preload("res://scripts/campus/academics/gradebook_adapter.gd")

static func from_school(school: Object) -> Dictionary:
	var records: Dictionary=school.get("gradebook")
	var profile := str(school.get("local_identity"))
	var bridge: Object=school.get("course_bridge")
	var model: Dictionary=Catalog.menu_catalog(records,profile,bridge)
	for course in model.get("courses",[]):
		var id := str(course.get("course_id",""))
		for definition in bridge.catalog():
			if str(definition.get("id",definition.get("course_id","")))==id:
				course["description"]=str(definition.get("description",""));break
		course["gradebook"]=GradebookAdapter.from_school(school,id)
		var required := course.gradebook.rows.size();var completed := 0
		for row in course.gradebook.rows:
			if bool(row.get("completed",false)):completed+=1
		course["progress"]={"required":required,"completed":completed}
	return model
