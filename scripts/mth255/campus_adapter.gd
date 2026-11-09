extends RefCounted
## Thin adapter for existing campus academic bridge; lifecycle remains host-owned.
const Provider=preload("res://scripts/mth255/provider.gd")
var provider=Provider.new()
func catalog() -> Array:
	var out=provider.catalog()
	out[0].merge({"course_id":"MTH255","lecture_weeks":10,"lab_weeks":0,"icon":"math","sequence_status":"Requested gameplay organization of five source units; not an official timetable."})
	return out
func weeks(course_id: String,kind: String="lecture") -> Array:
	return provider.weeks(kind) if course_id=="MTH255" else []
func generate(course_id: String,week: int,kind: String,difficulty: int,seed_value: int) -> Dictionary:
	if course_id!="MTH255" or kind!="lecture":return {"error":"MTH255 is lecture-only."}
	var out=provider.generate(week,difficulty,seed_value)
	if out.has("error"):return out
	out.merge({"course_id":"MTH255","kind":"lecture","title":"MTH255 — "+provider.weeks()[week-1].title,"topic":week-1,"data":"Use structured fields and stated angle units. Keep exact answers where requested; otherwise round final values to five decimal places.","theory":"","procedure":"Complete every requested part. Intermediate work is assessed only through explicit structured fields."})
	return out
func lesson(course_id: String,week: int,kind: String="lecture",duration_seconds: int=420) -> Dictionary:
	if course_id!="MTH255" or kind!="lecture":return {"error":"MTH255 is lecture-only."}
	var out=provider.lesson(week,2,255,duration_seconds)
	if out.has("error"):return out
	out.course_id="MTH255";out.kind="lecture";out.duration=out.duration_seconds
	for stage in out.stages:stage.duration=stage.duration_seconds
	return out
func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
	var out=provider.grade(assignment,answers)
	if not out.has("error"):out.merge({"course_id":"MTH255","score":out.percentage,"total":out.maximum})
	return out
func public_copy(assignment: Dictionary,reveal: bool=false) -> Dictionary:
	return provider.public_copy(assignment,reveal)
func practice(week: int,difficulty: int,seed_value: int,focus: String="") -> Dictionary:
	var out=provider.generate(week,difficulty,seed_value,8,focus)
	if not out.has("error"):out.merge({"course_id":"MTH255","kind":"lecture","official":false,"practice":true})
	return out
func ai_context(public_problem: Dictionary,stage: String,assessment_active: bool) -> Dictionary:
	var clean=provider.public_copy({"questions":[public_problem]}).questions[0]
	return {"course":"MTH255","week":clean.get("week",0),"problem":clean,"stage":stage,"assessment_active":assessment_active,"instruction":"Explain concepts using the displayed original problem. The deterministic host engine owns all official solutions and marks. During marked assessments follow host help policy. Never change grades or rewards."}

func practice_unit(unit: int,difficulty: int,seed_value: int,focus: String="") -> Dictionary:
	var out=provider.generate_unit(unit,difficulty,seed_value,8,focus)
	if not out.has("error"):out.merge({"course_id":"MTH255","kind":"lecture","official":false,"practice":true})
	return out
