extends SceneTree
func _initialize():call_deferred("run")
func run():
 var provider=preload("res://scripts/campus_course_provider.gd").new()
 assert(provider.catalog().any(func(c):return c.id=="DGS266"))
 for kind in ["lecture","lab"]:
  assert(provider.weeks("DGS266",kind).size()==8)
  assert(provider.weeks("DGS266",kind)[0].grade_weight==6.25)
  for week in range(1,9):
   var lesson:Dictionary=provider.lesson("DGS266",week,kind)
   var task:Dictionary=provider.generate("DGS266",week,kind,2,266)
   assert(lesson.stages.size()==3 and task.questions.size()>=2 and task.kind==kind)
   if kind=="lab":
    assert(task.questions.size()>=3 and task.lab_validation=={1:"digital_scope",2:"digital_binary",3:"digital_truth_table",4:"digital_simplify",5:"digital_combination",6:"digital_display",7:"digital_flipflop",8:"digital_interlock"}.get(week,"written_only"))
    var wrong_answers:={}
    for i in task.questions.size():wrong_answers[str(i)]=str(task.questions[i].answer)
    wrong_answers[str(task.questions.size()-1)]=str((int(task.questions.back().answer)+1)%4)
    assert(provider.grade(task,wrong_answers).score<100)
   assert(task.grade_weight==6.25)
   var answers:={}
   for i in task.questions.size():answers[str(i)]=str(task.questions[i].answer)
   assert(provider.grade(task,answers).score==100)
   assert(not provider.public_copy(task).questions[0].has("answer"))
 var config=preload("res://scripts/campus/academics/grade_weight_policy.gd").course("DGS266")
 var tracks={"lecture":provider.weeks("DGS266","lecture"),"lab":provider.weeks("DGS266","lab")}
 var view=preload("res://scripts/campus/academics/gradebook_view.gd").build({},"student","DGS266",tracks,config)
 assert(view.policy_valid and view.rows.size()==16 and is_equal_approx(view.total_weight,100.0))
 var bridge=preload("res://scripts/campus/academics/course_bridge.gd").new()
 var progress=preload("res://scripts/campus/academics/course_progression_adapter.gd").summary({},"student","DGS266",bridge)
 assert(progress.weight_policy_valid and is_equal_approx(progress.weight_total,100.0))
 var registry=preload("res://scripts/campus/world/room_registry.gd").new()
 assert(registry.course_room("DGS266","lecture").id=="ety155_lecture")
 assert(registry.course_room("DGS266","lab").id=="dc_lab")
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 for kind in ["lecture","lab"]:
  var result:Dictionary=game.school.start_activity({"mode":"Course","course_id":"DGS266","kind":kind,"week":3,"difficulty":2})
  assert(result.ok)
  assert(game.school.activity.course_id=="DGS266" and game.school.activity.kind==kind)
  if kind=="lab":
   game.school.allocation={}
   assert(game.school.equipment_access(1,0,"ETY155"))
   assert(not game.school.equipment_access(1,0,"ELM253"))
 print("PASS DGS266 lecture and lab weeks, lessons, grading and room routing")
 quit()
