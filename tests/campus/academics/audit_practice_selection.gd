extends SceneTree
## Exercise production selection and grading without exposing keys to clients.
const Practice=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")
const Bridge=preload("res://scripts/campus/academics/course_bridge.gd")
func _initialize() -> void:
 var bridge:=Bridge.new();var failures:=[];var checked:=0;var diverse:=0
 for course in ["DGS266","ETY155","ELM253","MTH147","MTH255"]:
  for week in range(1,bridge.weeks(course,"lecture").size()+1):
   var indices:={}
   for seed_value in [42,137,761,2026]:
    var practice:=Practice.new()
    if not practice.prepare(true,"event",course,week,0,seed_value,30.0,["student"]):failures.append("%s %d prepare"%[course,week]);continue
    var repeat:=Practice.new()
    if not repeat.prepare(true,"event",course,week,0,seed_value,30.0,["student"]) or repeat.question_index!=practice.question_index:failures.append("%s %d nondeterministic"%[course,week])
    var different:=Practice.new()
    if not different.prepare(true,"event",course,week,0,seed_value,30.0,["student"],[practice.question_index]):failures.append("%s %d history"%[course,week])
    if different.question_index!=practice.question_index:indices[-1]=true
    indices[practice.question_index]=true
    var question: Dictionary=practice.private_assignment.questions[practice.question_index]
    var answer: Variant=question.get("answer")
    var response: Variant=answer.duplicate(true) if answer is Dictionary or answer is Array else str(answer)
    if course not in ["MTH147","MTH255"] and question.get("options",[]).is_empty() and not str(question.get("unit","")).is_empty():response+=" "+str(question.unit)
    var status:=practice.submit(true,"student","event",response,1.0);practice.finish(true);checked+=1
    if status!="accepted" or not practice.result("student").get("correct",false):failures.append("%s %d index %d"%[course,week,practice.question_index])
    if Practice.has_private_fields(practice.snapshot("student",1.0).question):failures.append("%s %d private field"%[course,week])
   if indices.size()>1:diverse+=1
 print("PRACTICE_SELECTION_AUDIT checked=",checked," diverse_weeks=",diverse," failures=",failures.size())
 for failure in failures:print(failure)
 quit(0 if failures.is_empty() and diverse>0 else 1)
