extends RefCounted
signal navigation_requested(room_id: String)
var school: Object
var registry: Object
var provider: Object
func configure(academic: Object, rooms: Object, courses_provider: Object) -> void:
	school=academic; registry=rooms; provider=courses_provider
func courses() -> Array:
	return provider.call("catalog") if is_instance_valid(provider) and provider.has_method("catalog") else []
func weeks(course_id: String, kind: String) -> Array:
	return provider.call("weeks",course_id,kind) if is_instance_valid(provider) and provider.has_method("weeks") else []
func rooms(query := "") -> Array:
	return registry.call("search",query) if is_instance_valid(registry) and registry.has_method("search") else []
func assigned_room(course_id: String, kind: String) -> Dictionary:
	return registry.call("course_room",course_id,kind) if is_instance_valid(registry) and registry.has_method("course_room") else {}
func progress(course_id: String) -> Dictionary:
	return school.call("course_summary",course_id) if is_instance_valid(school) and school.has_method("course_summary") else {}
func course_record(course_id: String) -> Dictionary:
	if not is_instance_valid(school) or not is_instance_valid(provider):return {}
	var records: Variant=school.get("gradebook")
	if not records is Dictionary:return {}
	var attendance := {}
	for property in school.get_property_list():
		if str(property.name)=="local_attendance":
			var stored: Variant=school.get("local_attendance")
			if stored is Dictionary:attendance=stored
	var query=preload("res://scripts/campus/academics/course_progression_adapter.gd").menu_catalog(records,str(school.get("local_identity")),provider,attendance)
	for course in query.courses:
		if str(course.course_id)==course_id:return course
	return {}
func request_activity(config: Dictionary) -> Dictionary:
	if not is_instance_valid(school) or not school.has_method("start_activity"): return {"ok":false,"error":"Campus activities are not connected yet."}
	return school.call("start_activity",config)
func navigate(room_id: String) -> void:
	if room_id.is_empty() or (is_instance_valid(registry) and not registry.call("get_room",room_id).is_empty()): navigation_requested.emit(room_id)

func week_progress(course_id: String, week_number: int) -> Dictionary:
	var result := {"lecture":{"count":0,"best":null,"recent":null,"recent_time":""},"lab":{"count":0,"best":null,"recent":null,"recent_time":""}}
	if not is_instance_valid(school): return result
	var records: Variant=school.get("gradebook")
	var identity := str(school.get("local_identity"))
	if not records is Dictionary: return result
	for record in records.values():
		if str(record.get("profile",""))!=identity or bool(record.get("lesson",false)) or str(record.get("course_id","ELM253"))!=course_id or int(record.get("week",1))!=week_number: continue
		var category := str(record.get("kind","lab"))
		if not result.has(category): continue
		var score := float(record.get("score",NAN))
		if not is_finite(score): continue
		result[category].count+=1
		result[category].best=score if result[category].best==null else maxf(float(result[category].best),score)
		var stamp := str(record.get("time",""))
		if result[category].recent==null or stamp>=str(result[category].recent_time):
			result[category].recent=score; result[category].recent_time=stamp
	return result

func can_start() -> bool:
	return is_instance_valid(school) and school.has_method("start_activity") and school.get_multiplayer().is_server()
