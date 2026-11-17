extends SceneTree
const PracticePanel=preload("res://scripts/campus/academics/classroom_events/practice_panel.gd")
const Practice=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")
var received: Array=[]
func _initialize() -> void:
 var panel:=PracticePanel.new();root.add_child(panel)
 assert(panel.build({"prompt":"Choose","options":["A","B"]}))
 var hint_requests:=[0]
 panel.hint_requested.connect(func():hint_requests[0]+=1)
 panel.update_state({"mode":"practice","can_submit":true,"can_hint":true,"seconds_left":25.0})
 panel.hint_button.pressed.emit();assert(hint_requests[0]==1)
 panel.update_state({"mode":"practice","can_submit":true,"can_hint":false,"hint":"Compare the choices with the given values.","progress":{"message":"Review the given values and try once more.","attempts_left":1},"seconds_left":25.0})
 assert(panel.hint_button.disabled and panel.hint_label.visible and panel.status_label.text.contains("1 attempt remaining"))
 panel.submitted.connect(func(response):received.append(response))
 panel._submit();assert(received.is_empty())
 panel.options.select(1);panel._submit()
 assert(received==["1"] and panel.submit_button.disabled)
 panel.action_status("submit","retry")
 assert(not panel.submit_button.disabled and not panel.submission_pending)
 var skip_requests:=[0]
 panel.declined.connect(func():skip_requests[0]+=1)
 panel.decline_button.pressed.emit();assert(skip_requests[0]==1)
 panel.update_state({"mode":"practice","can_submit":false,"declined":true,"seconds_left":20.0})
 assert(panel.decline_button.disabled and panel.status_label.text.contains("no grade is recorded"))
 panel.update_state({"mode":"group","can_submit":false,"submitted":false,"seconds_left":0.0,"shared":{"group":"A","count":2},"group_result":{"team":"A","members":2,"answered":1,"correct":1}})
 assert(panel.status_label.text.contains("Group A: 1 correct of 1 answers"))
 var unsupported:=PracticePanel.new();root.add_child(unsupported)
 assert(not unsupported.build({"prompt":"Graph","input":{"kind":"graph"}}))
 var scalar:=PracticePanel.new();root.add_child(scalar)
 assert(scalar.build({"prompt":"Value","options":[]}))
 scalar.submitted.connect(func(response):received.append(response))
 scalar.entry.text=" 12 V ";scalar._submit();assert(received.back()=="12 V")
 var practice:=Practice.new()
 assert(practice.prepare(true,"event","MTH255",1,0,42,30.0,["student"]))
 var math:=PracticePanel.new();root.add_child(math)
 assert(math.build(practice.snapshot("student",0).question,"MTH255"))
 assert(is_instance_valid(math.math_view) and is_instance_valid(math.math_view.workspace))
 var expected: Dictionary=practice.private_assignment.questions[practice.question_index].answer
 for key in expected:
  if key=="points" and is_instance_valid(math.math_view.workspace.graph):
   math.math_view.workspace.graph.points=expected[key].duplicate(true)
  elif math.math_view.workspace.fields.has(key):
   math.math_view.workspace.fields[key].set_value(expected[key])
  else:
   push_error("No answer control for "+str(key));quit(1);return
 math.submitted.connect(func(response):received.append(response))
 math._submit();assert(received.back() is Dictionary)
 assert(practice.submit(true,"student","event",received.back(),1.0)=="accepted")
 assert(practice.finish(true) and practice.result("student").get("correct",false))
 print("CLASSROOM_PRACTICE_PANEL_FIXTURE PASS");quit(0)
