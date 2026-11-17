extends SceneTree
const Bridge=preload("res://scripts/campus/academics/course_bridge.gd")
const PracticePanel=preload("res://scripts/campus/academics/classroom_events/practice_panel.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var bridge:=Bridge.new();var checked:=0;var correct:=0;var wrong_rejected:=0;var malformed_rejected:=0;var failures: Array=[];var forms:={}
 for course in ["MTH147","MTH255"]:
  for week in range(1,bridge.weeks(course,"lecture").size()+1):
   for difficulty in [0,4]:
    for seed_value in [42,137]:
     await check_assignment(bridge,course,week,difficulty,seed_value,forms,failures)
     var counts: Dictionary=last_counts
     checked+=int(counts.checked);correct+=int(counts.correct);wrong_rejected+=int(counts.wrong_rejected);malformed_rejected+=int(counts.malformed_rejected)
 var failed_forms:={}
 for failure in failures:
  var parts: PackedStringArray=str(failure).split(" ")
  var label: String=parts[6] if parts.size()>6 else "unknown"
  failed_forms[label]=int(failed_forms.get(label,0))+1
 print("CLASSROOM_MATH_FORMS checked=",checked," correct=",correct," wrong_rejected=",wrong_rejected," malformed_rejected=",malformed_rejected," forms=",forms," failed_forms=",failed_forms," examples=",failures.slice(0,8))
 quit(0 if failures.is_empty() else 1)

var last_counts:={}
func check_assignment(bridge: Object,course: String,week: int,difficulty: int,seed_value: int,forms: Dictionary,failures: Array) -> void:
 var checked:=0;var correct:=0;var wrong_rejected:=0;var malformed_rejected:=0
 var assignment: Dictionary=bridge.generate(course,week,"lecture",difficulty,seed_value)
 var public: Dictionary=bridge.public_copy(assignment,false)
 for index in public.get("questions",[]).size():
    var question: Dictionary=public.questions[index]
    var kind:=str(question.get("input",{}).get("kind",question.get("expected_form","expression")))
    forms[kind]=int(forms.get(kind,0))+1
    var panel:=PracticePanel.new();root.add_child(panel)
    if not panel.build(question,course):failures.append("%s week %d question %d build"%[course,week,index]);panel.queue_free();continue
    var expected: Variant=assignment.questions[index].get("answer")
    var workspace: Control=panel.math_view.workspace if course=="MTH255" else panel.math_view
    if expected is Dictionary:
     if kind in ["graph","complex_plane"]:
      workspace.graph.restore(expected)
      for key in expected.get("function",{}):
       if workspace.graph_parameter_entries.has(key):workspace.graph_parameter_entries[key].text=str(expected.function[key])
      if workspace.graph_parameter_entries.has("period") and expected.has("period"):workspace.graph_parameter_entries.period.text=str(expected.period)
      if is_instance_valid(workspace.graph_function_kind):workspace.graph_function_kind.select(1 if expected.get("function",{}).get("kind","")=="cos" else 0)
     elif kind=="choice":workspace.values.choice=expected
     elif kind=="table":workspace.table.configure({"columns":workspace.table.columns,"rows":expected.get("rows",[])},true)
     elif kind=="triangle":
      if expected.get("solutions",[]).is_empty():workspace.empty_set_check.set_pressed(true)
      for i in expected.get("solutions",[]).size():
       if i>=workspace.triangle_editors.size():workspace._add_triangle()
       for key in expected.solutions[i]:
        if workspace.triangle_editors[i].fields.has(key):workspace.triangle_editors[i].fields[key].text=str(expected.solutions[i][key])
     elif kind=="complex_roots":
      for i in expected.get("values",[]).size():
       if i>=workspace.roots_editors.size():workspace._add_root()
       workspace.roots_editors[i].real.set_value(str(expected.values[i].real))
       workspace.roots_editors[i].imag.set_value(str(expected.values[i].imag))
     elif kind=="system" and expected.has("classification"):
      workspace.classification.select(1 if expected.classification=="none" else 2)
     elif kind=="structured" and expected.has("points"):
      for i in expected.points.size():
       for axis in ["x","y"]:workspace.fields[axis+str(i+1)].set_value(str(expected.points[i][axis]))
     else:
      if kind=="complex" and expected.has("magnitude"):
       workspace.complex_form.select(2 if assignment.questions[index].get("expected_form","")=="exponential" else 1)
       workspace._complex_visibility()
      for key in expected:
       if workspace.fields.has(key):
        var value: Variant=expected[key]
        if key=="output" and value is float:
         var decimals:=maxi(0,3-floori(log(absf(value))/log(10.0))) if absf(value)>0 else 3
         workspace.fields[key].set_value(String.num(value,decimals))
        else:workspace.fields[key].set_value(", ".join(value) if value is Array else str(value))
    elif expected is Array:
     if expected.is_empty() and is_instance_valid(workspace.empty_set_check):workspace.empty_set_check.set_pressed(true)
     elif workspace.fields.has("values"):workspace.fields.values.set_value(", ".join(expected))
    elif kind=="choice":workspace.values.choice=str(expected)
    elif workspace.fields.has("answer"):workspace.fields.answer.set_value(str(expected))
    if is_instance_valid(workspace.empty_set_check) and workspace.empty_set_check.button_pressed:
     var saved: Dictionary=workspace.snapshot()
     workspace.empty_set_check.set_pressed(false)
     if not workspace.restore(saved) or not workspace.empty_set_check.button_pressed:failures.append("%s week %d question %d empty set restore"%[course,week,index])
    var response: Variant=panel.math_view.answer()
    var marked: Dictionary=bridge.grade(assignment,{str(index):response})
    if marked.has("error") or marked.get("feedback",[]).size()<=index:failures.append("%s week %d question %d grade %s"%[course,week,index,kind])
    elif marked.feedback[index].get("correct",false):correct+=1
    else:failures.append("%s week %d question %d incorrect %s expected=%s response=%s"%[course,week,index,kind,str(expected),str(response)])
    var wrong: Dictionary=bridge.grade(assignment,{str(index):"__definitely_wrong__"})
    if wrong.has("error") or wrong.get("feedback",[]).size()<=index or not wrong.feedback[index].get("correct",false):wrong_rejected+=1
    else:failures.append("%s week %d question %d wrong accepted"%[course,week,index])
    var malformed: Dictionary=bridge.grade(assignment,{str(index):{"not_a_valid_answer":true}})
    if malformed.has("error") or malformed.get("feedback",[]).size()<=index or not malformed.feedback[index].get("correct",false):malformed_rejected+=1
    else:failures.append("%s week %d question %d malformed accepted"%[course,week,index])
    checked+=1;panel.queue_free();await process_frame
 last_counts={"checked":checked,"correct":correct,"wrong_rejected":wrong_rejected,"malformed_rejected":malformed_rejected}
