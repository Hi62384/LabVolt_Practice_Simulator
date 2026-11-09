extends RefCounted
const Legacy = preload("res://scripts/course_generator.gd")
var provider: Object

func _init(injected: Object = null) -> void:
	provider=injected
	if provider==null and ResourceLoader.exists("res://scripts/campus_course_provider.gd"):
		var course_script := load("res://scripts/campus_course_provider.gd") as Script
		if course_script != null and course_script.can_instantiate():
			provider=course_script.new()
		else:
			push_error("Campus course provider failed to load. The legacy course fallback is active.")

func catalog() -> Array:
	if provider!=null and provider.has_method("catalog"):return provider.call("catalog")
	return [{"id":"ELM253","title":"AC Electrical Systems"},{"id":"ETY155","title":"Basic DC Electricity"}]

func generate(course: String, week: int, kind: String, difficulty: int, seed_value: int) -> Dictionary:
	if provider!=null and provider.has_method("generate"):
		return provider.call("generate",course,week,kind,difficulty,seed_value)
	if course!="ELM253":return {}
	var assignment := Legacy.generate(week-1,mini(2,difficulty),seed_value)
	assignment.merge({"course_id":course,"week":week,"kind":kind},true)
	return assignment

func lesson(course: String, week: int, kind: String, duration: float) -> Dictionary:
	if provider!=null and provider.has_method("lesson"):
		return provider.call("lesson",course,week,kind,int(duration))
	var assignment := generate(course,week,kind,0,1)
	if assignment.is_empty():return {}
	var stages: Array=[]
	for field in ["theory","data","procedure"]:
		stages.append({"title":field.capitalize(),"text":assignment.get(field,""),"duration":duration/3.0})
	return {"title":assignment.title,"stages":stages,"duration":duration}

func grade(assignment: Dictionary, answers: Dictionary) -> Dictionary:
	if provider!=null and provider.has_method("grade") and assignment.has("course_id"):
		return provider.call("grade",assignment,answers)
	return Legacy.grade(assignment,answers)

func lesson_for_assignment(assignment: Dictionary,duration: float=420) -> Dictionary:
	if provider!=null and provider.has_method("lesson_for_assignment"):return provider.call("lesson_for_assignment",assignment,int(duration))
	return lesson(str(assignment.get("course_id","ELM253")),int(assignment.get("week",1)),str(assignment.get("kind","lecture")),duration)

func public_copy(assignment: Dictionary,marked := false) -> Dictionary:
	if provider!=null and provider.has_method("public_copy"):return provider.call("public_copy",assignment,marked)
	return Legacy.public_copy(assignment,marked)

func weeks(course: String, kind: String) -> Array:
	if provider!=null and provider.has_method("weeks"):return provider.call("weeks",course,kind)
	var result: Array=[]
	if course=="ELM253":
		for i in Legacy.TOPICS.size():result.append({"week":i+1,"title":Legacy.TOPICS[i]})
	return result

func paper_policy(assignment: Dictionary,practice := false) -> Dictionary:
	if provider!=null and provider.has_method("paper_policy"):return provider.call("paper_policy",assignment,practice)
	return {"formula_allowed":practice,"calculator_allowed":practice,"formula_sections":[]}
