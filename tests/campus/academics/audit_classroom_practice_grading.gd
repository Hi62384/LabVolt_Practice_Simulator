extends SceneTree
## Uses private generated keys only inside an isolated grading audit.
const Practice=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")
const Bridge=preload("res://scripts/campus/academics/course_bridge.gd")
func _initialize() -> void:
 var bridge:=Bridge.new();var failures:=[];var forms:={};var checked:=0
 for course in ["DGS266","ETY155","ELM253","MTH147","MTH255"]:
  for week in range(1,bridge.weeks(course,"lecture").size()+1):
   var practice:=Practice.new()
   if not practice.prepare(true,"event",course,week,0,42,30.0,["student"]):
    failures.append("%s week %d preparation"%[course,week]);continue
   var question: Dictionary=practice.private_assignment.questions[practice.question_index]
   var answer: Variant=question.get("answer")
   var form:=str(question.get("expected_form","choice" if not question.get("options",[]).is_empty() else "numeric"))
   forms[course+":"+form]=true
   var response: Variant=answer.duplicate(true) if answer is Dictionary or answer is Array else str(answer)
   if course not in ["MTH147","MTH255"] and question.get("options",[]).is_empty() and not str(question.get("unit","")).is_empty():response+=" "+str(question.unit)
   checked+=1
   var status:=practice.submit(true,"student","event",response,1.0)
   practice.finish(true)
   if status!="accepted" or not practice.result("student").get("correct",false):failures.append("%s week %d form %s"%[course,week,form])
 print("CLASSROOM_GRADING_AUDIT questions=",checked," forms=",forms.size()," failures=",failures.size())
 for failure in failures:print(failure)
 quit(0 if failures.is_empty() else 1)
