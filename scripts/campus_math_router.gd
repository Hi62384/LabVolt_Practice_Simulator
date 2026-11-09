extends RefCounted
## Integrator-facing trusted course router. No arbitrary plugin path from peers.
const PATHS = {"MTH147":"res://scripts/mth147/provider.gd","MTH255":"res://scripts/mth255/provider.gd"}

static func provider(course_id: String) -> Variant:
	if not PATHS.has(course_id):return null
	var path := str(PATHS[course_id])
	if not ResourceLoader.exists(path):return null
	var script=load(path)
	return script.new() if course_id=="MTH255" else script

static func catalog() -> Array:
	var result: Array=[]
	for code in PATHS:
		var plugin: Variant=provider(code)
		if plugin!=null:result.append_array(plugin.catalog())
	return result

static func weeks(course_id: String,kind: String="lecture") -> Array:
	var plugin: Variant=provider(course_id)
	var result: Array=plugin.weeks(kind) if plugin!=null else []
	return preload("res://scripts/campus/academics/grade_weight_policy.gd").decorate(course_id,kind,result)

static func generate(course_id: String,week: int,kind: String,difficulty: int,seed_value: int,count: int=8,focus: String="") -> Dictionary:
	if kind!="lecture":return {"error":"Mathematics courses are lecture-only."}
	var plugin: Variant=provider(course_id)
	if plugin==null:return {"error":"Mathematics provider unavailable."}
	var result: Dictionary=plugin.generate(week,difficulty,seed_value,count,focus)
	var rows := weeks(course_id,kind)
	if not result.has("error") and week>0 and week<=rows.size():result.merge({"is_exam":rows[week-1].is_exam,"assessment_type":rows[week-1].assessment_type,"grade_weight":rows[week-1].grade_weight},true)
	return result

static func lesson(course_id: String,week: int,kind: String,difficulty: int=2,seed_value: int=147,duration_seconds: int=420,focus: String="") -> Dictionary:
	if kind!="lecture":return {"error":"No mathematics laboratory."}
	var plugin: Variant=provider(course_id)
	if plugin==null:return {"error":"Mathematics provider unavailable."}
	var result: Dictionary=plugin.lesson(week,difficulty,seed_value,duration_seconds,focus)
	if result.has("error") or course_id!="MTH255":return result
	var stages: Array=result.get("stages",[]).duplicate(true)
	for example in result.get("worked_examples",[]).slice(0,1):
		stages.append({"title":"Worked example","text":example.prompt,"problem":plugin.public_problem(example)})
		for step in example.get("steps",[]).slice(0,12):
			stages.append({"title":"Worked step","text":str(step.get("text","")),"math":step.get("math",{}),"diagram":step.get("diagram",{})} if step is Dictionary else {"title":"Worked step","text":str(step)})
	for index in stages.size():
		stages[index].duration_seconds=float(result.duration_seconds)/maxi(1,stages.size())
		stages[index].duration=stages[index].duration_seconds
	result.stages=stages
	return result

static func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
	var plugin: Variant=provider(str(assignment.get("course_id","")))
	if plugin==null:return {"error":"Unknown mathematics course."}
	var result: Dictionary=plugin.grade(assignment,answers)
	if result.has("error"):return result
	if assignment.get("course_id","")=="MTH255":result.score=float(result.percentage)
	for item in result.get("feedback",[]):
		item.total=item.get("possible",item.get("maximum",1))
		if item.has("accepted"):item.expected=item.accepted
	return result

static func public_copy(assignment: Dictionary,reveal: bool=false) -> Dictionary:
	var plugin: Variant=provider(str(assignment.get("course_id","")))
	return plugin.public_copy(assignment,reveal) if plugin!=null else {}
