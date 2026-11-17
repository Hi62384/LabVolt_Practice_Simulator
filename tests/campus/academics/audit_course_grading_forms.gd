extends SceneTree
## Offline audit of provider grading over generated lecture questions.
const Bridge=preload("res://scripts/campus/academics/course_bridge.gd")
func _initialize() -> void:
 var bridge:=Bridge.new();var checked:=0;var forms:={};var failures:=[]
 for course in ["DGS266","ETY155","ELM253","MTH147","MTH255"]:
  for week in range(1,bridge.weeks(course,"lecture").size()+1):
   var assignment: Dictionary=bridge.generate(course,week,"lecture",0,42)
   if assignment.is_empty() or assignment.has("error"):failures.append("%s week %d generation"%[course,week]);continue
   for index in assignment.questions.size():
    var question: Dictionary=assignment.questions[index];var answer: Variant=question.get("answer")
    var form:=str(question.get("expected_form","choice" if not question.get("options",[]).is_empty() else "numeric"))
    forms[course+":"+form]=true
    var response: Variant=answer.duplicate(true) if answer is Dictionary or answer is Array else str(answer)
    if course not in ["MTH147","MTH255"] and question.get("options",[]).is_empty() and not str(question.get("unit","")).is_empty():response+=" "+str(question.unit)
    var result: Dictionary=bridge.grade(assignment,{str(index):response});checked+=1
    if result.has("error") or result.get("feedback",[]).size()<=index or not result.feedback[index].get("correct",false):failures.append("%s week %d question %d form %s"%[course,week,index,form])
 print("CLASSROOM_FORM_AUDIT questions=",checked," forms=",forms.size()," failures=",failures.size())
 for failure in failures:print(failure)
 quit(0 if failures.is_empty() else 1)
