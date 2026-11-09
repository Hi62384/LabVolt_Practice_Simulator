extends SceneTree
const P=preload("res://scripts/mth255/provider.gd")
const Adapter=preload("res://scripts/mth255/campus_adapter.gd")
var failures=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;print("FAIL "+message)
func significant(value: float) -> String:
	var places=3-int(floor(log(value)/log(10)));var scale=pow(10,places);var out=String.num(round(value*scale)/scale,maxi(0,places))
	if out.contains("."):
		while out.get_slice(".",1).length()<places:out+="0"
	return out
func _initialize() -> void:
	var p=P.new();var adapter=Adapter.new();var count=0
	for week in range(1,11):
		for d in range(5):
			var assignment=adapter.generate("MTH255",week,"lecture",d,25500+week*10+d)
			check(not assignment.has("error"),"weekly preparation "+str(week)+"."+str(d))
			if assignment.has("error"):continue
			check(assignment.questions.size()==8 and assignment.assessment_seconds==1800,"assessment configuration")
			var restored=p.restore(JSON.parse_string(JSON.stringify(assignment)));check(not restored.has("error"),"weekly reconnect validation")
			var answers={}
			for problem in assignment.questions:
				var answer=problem.answer.duplicate(true)
				for field in problem.rubric.get("field_forms",{}):answer[field]=significant(float(answer[field]))
				answers[problem.id]=answer
			var marked=adapter.grade(assignment,answers);check(marked.score==100 and marked.percentage==100 and not marked.rewards_issued and not marked.mutates_profile,"host score-only interface")
			answers.erase(assignment.questions[0].id);var partial=adapter.grade(assignment,answers);check(partial.score==87.5,"partial timeout scoring")
			var public_assignment=adapter.public_copy(assignment);check(public_assignment.course_id=="MTH255" and not public_assignment.has("seed"),"weekly public metadata")
			count+=1
	for week in range(1,11):
		var lesson=p.lesson(week,2,week*313,420);check(not lesson.has("error"),"lesson preparation "+str(week))
		if lesson.has("error"):continue
		check(lesson.stages.size()==5 and not lesson.practice.official,"staged lesson and ungraded checkpoint")
		var duration=0.0
		for stage in lesson.stages:duration+=stage.duration_seconds;check(not stage.text.is_empty() and not stage.math.is_empty(),"meaningful stage")
		check(absf(duration-420)<0.001,"lesson duration")
	for unit in range(1,6):
		var practice=adapter.practice_unit(unit,4,unit*155)
		check(not practice.has("error") and not practice.official and practice.practice and practice.unit==unit,"ungraded unit practice")
	var mixed=adapter.practice(10,4,891,"mixed");check(not mixed.has("error") and mixed.mode=="mixed" and not mixed.official,"mixed-course practice")
	print("MTH255_COURSE_FLOW weekly_configurations=%d lessons=10 units=5 failures=%d"%[count,failures]);quit(0 if failures==0 else 1)
