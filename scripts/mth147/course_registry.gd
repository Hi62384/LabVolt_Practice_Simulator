extends RefCounted
## Integrator-facing trusted course router. No arbitrary plugin path from peers.
const PATHS = {"MTH147":"res://scripts/mth147/provider.gd","MTH255":"res://scripts/mth255/provider.gd"}

static func provider(course_id: String) -> Variant:
	if not PATHS.has(course_id):return null
	var path := str(PATHS[course_id])
	return load(path) if ResourceLoader.exists(path) else null

static func catalog() -> Array:
	var result: Array=[]
	for code in PATHS:
		var plugin: Variant=provider(code)
		if plugin!=null:result.append_array(plugin.catalog())
	return result

static func weeks(course_id: String,kind: String="lecture") -> Array:
	var plugin: Variant=provider(course_id)
	return plugin.weeks(kind) if plugin!=null else []

static func generate(course_id: String,week: int,kind: String,difficulty: int,seed_value: int,count: int=8,focus: String="") -> Dictionary:
	if kind!="lecture":return {"error":"Mathematics courses are lecture-only."}
	var plugin: Variant=provider(course_id)
	return plugin.generate(week,difficulty,seed_value,count,focus) if plugin!=null else {"error":"Mathematics provider unavailable."}

static func lesson(course_id: String,week: int,kind: String,difficulty: int=2,seed_value: int=147,duration_seconds: int=420,focus: String="") -> Dictionary:
	if kind!="lecture":return {"error":"No mathematics laboratory."}
	var plugin: Variant=provider(course_id)
	return plugin.lesson(week,difficulty,seed_value,duration_seconds,focus) if plugin!=null else {"error":"Mathematics provider unavailable."}

static func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
	var plugin: Variant=provider(str(assignment.get("course_id","")))
	return plugin.grade(assignment,answers) if plugin!=null else {"error":"Unknown mathematics course."}

static func public_copy(assignment: Dictionary,reveal: bool=false) -> Dictionary:
	var plugin: Variant=provider(str(assignment.get("course_id","")))
	return plugin.public_copy(assignment,reveal) if plugin!=null else {}
