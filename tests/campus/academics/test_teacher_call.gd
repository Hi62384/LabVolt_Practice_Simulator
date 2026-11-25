extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 game.school.start("Freeplay",0)
 var faculty=game.faculty
 var classes=game.lecture_classes
 for room in ["ac_lab","dc_lab"]:
  var instructor: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
  faculty._sync_lab_teachers()
  assert(instructor.get_child_count()==0 and not faculty.speech_player.active.has(room))
  var guide: Node
  for candidate in classes.get_children():
   if candidate.get_meta("role","")=="lecture_desk" and candidate.get_meta("room","")==room:guide=candidate;break
  assert(is_instance_valid(guide) and guide.get_meta("label","")=="Lab Guide")
  game.player.global_position=classes.signs[room].desk
  assert(classes.interact(guide) and game.paper_ui.open_lab_instructor_visible)
  var host_button: Button
  for button in game.paper_ui.screen.find_children("*","Button",true,false):
   if button.text=="Host a lab class":host_button=button;break
  assert(is_instance_valid(host_button))
  host_button.pressed.emit()
  assert(is_instance_valid(classes.picker) and classes.picker.start.disabled)
  classes.close_picker()
  game.paper_ui.close()
  var course: String="ELM253" if room=="ac_lab" else "ETY155"
  classes._apply(1,"start",room,{"kind":"lab","course_id":course,"week":1,"difficulty":0})
  assert(not classes.classes.has(room),"An unverified host must not start a class")
  assert(classes._start(room,{"kind":"lab","course_id":course,"week":1,"difficulty":0})=="")
  faculty._sync_lab_teachers()
  var model: Node3D=instructor.get_node_or_null("InstructorModel")
  assert(is_instance_valid(model) and model.find_child("ClassInstructorTarget",true,false).collision_layer==4)
  faculty.open_conversation(room)
  assert(faculty.conversation.visible)
  await process_frame
  assert(faculty.conversation.position.y>get_viewport_rect().size.y*.65)
  assert(faculty.close_conversation())
  classes.classes.erase(room)
  faculty._sync_lab_teachers()
  assert(instructor.get_child_count()==0 and not faculty.speech_player.active.has(room))
 if OS.get_environment("LABVOLT_TEST_OPENAI")=="1":
  var client: Node=game.host_openai
  assert(client.set_local_test_endpoint("http://127.0.0.1:28768/v1"))
  assert(client.set_session_key("sk-test-12345678901234567890"))
  assert(client.configure("gpt-5.4-mini",128,"",true)==OK)
  var result: Dictionary=await client.verify_class_connection()
  assert(result.ok and client.verified_for_class())
  game.player.global_position=classes.signs.dc_lab.desk
  classes._apply(1,"start","dc_lab",{"kind":"lab","course_id":"ETY155","week":1,"difficulty":0})
  assert(classes.classes.dc_lab.ai_teaching)
  var activity: Dictionary=classes.classes.dc_lab
  activity.phase="lesson"
  activity.deadline=classes._now()+classes.LessonSeconds
  faculty._maybe_ai_lesson("dc_lab")
  assert(activity.ai_waiting)
  var limit:=Time.get_ticks_msec()+4000
  while activity.ai_waiting and Time.get_ticks_msec()<limit:await process_frame
  assert(not activity.ai_waiting and activity.ai_status=="")
  print("VERIFIED_TEACHER_CLASS PASS")
 print("LAB_GUIDE_AND_TEACHER_PRESENCE PASS")
 game.queue_free();await process_frame;quit(0)

func get_viewport_rect() -> Rect2:
 return root.get_visible_rect()
