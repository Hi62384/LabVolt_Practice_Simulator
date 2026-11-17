extends SceneTree
## Lightweight workspace compatibility audit; it does not establish visual usability.
const Practice=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")
const PanelScript=preload("res://scripts/campus/academics/classroom_events/practice_panel.gd")
const Bridge=preload("res://scripts/campus/academics/course_bridge.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var bridge:=Bridge.new();var failures:=[];var checked:=0
 for course in ["MTH147","MTH255"]:
  for week in range(1,bridge.weeks(course,"lecture").size()+1):
   var practice:=Practice.new()
   if not practice.prepare(true,"event",course,week,0,42,30.0,["student"]):failures.append("%s week %d preparation"%[course,week]);continue
   var panel:=PanelScript.new();root.add_child(panel)
   if not panel.build(practice.snapshot("student",0.0).question,course):failures.append("%s week %d panel"%[course,week]);panel.queue_free();continue
   checked+=1
   if course=="MTH255" and not panel.math_view.answer() is Dictionary:failures.append("%s week %d structured response"%[course,week])
   panel.queue_free();await process_frame
 print("CLASSROOM_PANEL_FORM_AUDIT questions=",checked," failures=",failures.size())
 for failure in failures:print(failure)
 quit(0 if failures.is_empty() else 1)
