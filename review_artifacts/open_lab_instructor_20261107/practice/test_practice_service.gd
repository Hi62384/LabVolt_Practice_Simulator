extends SceneTree
const Service=preload("res://review_artifacts/open_lab_instructor_20261107/practice/practice_service.gd")
class ProviderFixture:
	extends RefCounted
	var calls: Array=[]
	func generate(course: String,week: int,kind: String,difficulty: int,seed_value: int) -> Dictionary:
		calls.append([course,week,kind,difficulty,seed_value])
		return {"course_id":course,"week":week,"kind":kind,"title":"Fixture experiment","theory":"V = IR","data":"Vs = 12 V; R1 = 1 kΩ","procedure":"Power off, connect the circuit, then measure voltage and current.","diagram":{"kind":"netlist","parts":[{"id":"Vs","kind":"V","a":"p","b":"g","value":12.0},{"id":"R1","kind":"R","a":"p","b":"g","value":1000.0}]},"questions":[{"prompt":"Current","unit":"A","answer":0.012,"options":[]}],"seed":seed_value}
var failures: Array[String]=[]
func check(value: bool,label: String) -> void:
	if not value:failures.append(label)
func _initialize() -> void:
	var provider := ProviderFixture.new()
	check(Service.course_for_room("ac_lab")=="ELM253" and Service.course_for_room("dc_lab")=="ETY155","stable room ID mapping")
	check(Service.course_for_room("math_class").is_empty(),"unknown classroom cannot issue electrical practice")
	var ac: Dictionary=Service.issue_for_room("ac_lab",provider,11)
	var dc: Dictionary=Service.issue_for_room("dc_lab",provider,12)
	check(ac.get("course_id")=="ELM253" and dc.get("course_id")=="ETY155","room chooses corresponding generator")
	check(ac.get("kind")=="lab" and ac.get("practice_scope")=="ungraded" and not bool(ac.get("is_exam",true)) and ac.get("grade_weight")==null,"practice never carries official exam weight")
	check(ac.has("diagram") and not ac.questions.is_empty() and not str(ac.practical_tasks).is_empty() and not str(ac.verification).is_empty(),"physical worksheet retains circuit and teaching structure")
	check(Service.issue_for_room("math_class",provider,1).has("error") and provider.calls.size()==2,"unknown room never reaches generator")
	var math147: Dictionary=Service.issue_for_course("MTH147",provider,1)
	var math255: Dictionary=Service.issue_for_course("MTH255",provider,2)
	check(math147.get("kind")=="lecture" and math255.get("kind")=="lecture" and math147.get("practice_scope")=="ungraded" and math255.get("practice_scope")=="ungraded","study entry serves existing math courses as private practice")
	check(math147.get("practice",false) and math147.get("assessment_type")=="practice" and math147.get("grade_weight")==null,"math worksheet excludes official grading")
	check(Service.issue_for_course("UNKNOWN",provider,1).has("error"),"unknown study course rejected")
	check(Service.issue_for_course("ETY155",provider,13).week!=dc.week,"seed varies practical topic")
	print("OPEN_LAB_PRACTICE_RESULT failures=%d"%failures.size())
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
