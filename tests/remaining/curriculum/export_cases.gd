extends SceneTree
const Provider=preload("res://scripts/campus/courses/course_provider.gd")
const Legacy=preload("res://scripts/course_generator.gd")
var failures := 0
func _initialize() -> void:
	var cases: Array=[]
	for course in ["ETY155","ELM253"]:
		for kind in ["lecture","lab"]:
			for meta in Provider.weeks(course,kind):
				for d in range(5):
					for seed_value in [1,7,41,155,253,902]:
						var a := Provider.generate(course,int(meta.week),kind,d,seed_value)
						if a.has("error"):failures+=1;push_error(str(a));continue
						var repeated := Provider.generate(course,int(meta.week),kind,d,seed_value)
						if var_to_bytes(a)!=var_to_bytes(repeated):failures+=1;push_error("Same seed changed")
						var public := Provider.public_copy(a)
						if public.has("scenario") or public.has("reference_parts") or public.has("reference_ac"):failures+=1;push_error("Private scenario exposed")
						for question in public.questions:
							if question.has("answer") or question.has("inputs"):failures+=1;push_error("Answer or hidden context exposed")
						cases.append({"course":course,"kind":kind,"week":meta.week,"difficulty":d,"seed":seed_value,"questions":a.questions,"parts":a.get("reference_parts",[]),"scenario":a.get("scenario",{}),"physical_plan":a.get("physical_ac_plan",{}),"equipment_plan":a.get("equipment_plan",{})})
	# Raw legacy API retains coverage independently of the course wrapper.
	for topic in range(11):
		for d in range(3):
			for seed_value in [1,7,41,155,253,902]:
				var a := Legacy.generate(topic,d,seed_value)
				cases.append({"course":"legacyELM253","kind":"calculation","week":topic+1,"difficulty":d,"seed":seed_value,"questions":a.questions,"parts":[],"scenario":a.scenario})
	var path := OS.get_environment("LABVOLT_CURRICULUM_CASES")
	if path=="":push_error("Set LABVOLT_CURRICULUM_CASES to a task-local output path");quit(2);return
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null:push_error("Cannot open oracle data output");quit(2);return
	file.store_string(JSON.stringify(cases));file.close()
	print("EXPORTED cases=%d determinism/publication_failures=%d"%[cases.size(),failures])
	quit(1 if failures else 0)
