extends SceneTree
## Offline key audit, not a semantic proof that generated prompts hide answers.
const Bridge=preload("res://scripts/campus/academics/course_bridge.gd")
const Round=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")
func _initialize() -> void:
 var bridge:=Bridge.new();var failures:=[];var count:=0
 for course in ["DGS266","ETY155","ELM253","MTH147","MTH255"]:
  var weeks: Array=bridge.weeks(course,"lecture")
  for week in range(1,weeks.size()+1):
   for difficulty in [0,4]:
    for seed_value in [42,137]:
     var assignment: Dictionary=bridge.generate(course,week,"lecture",difficulty,seed_value)
     if assignment.is_empty() or assignment.has("error"):
      failures.append("%s week %d difficulty %d seed %d generation"%[course,week,difficulty,seed_value]);continue
     var safe: Dictionary=bridge.public_copy(assignment,false)
     if not safe.get("questions",null) is Array or safe.questions.is_empty():
      failures.append("%s week %d difficulty %d seed %d no questions"%[course,week,difficulty,seed_value]);continue
     for index in safe.questions.size():
      count+=1
      if Round.has_private_fields(safe.questions[index]):failures.append("%s week %d difficulty %d seed %d question %d private field"%[course,week,difficulty,seed_value,index])
 print("CLASSROOM_PAYLOAD_AUDIT questions=",count," failures=",failures.size())
 for item in failures:print(item)
 quit(0 if failures.is_empty() else 1)
