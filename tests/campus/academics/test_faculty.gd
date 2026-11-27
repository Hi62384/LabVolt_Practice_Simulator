extends SceneTree
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var faculty=game.faculty
 game.client_preferences.values.teacher_speech=false
 assert(Roster.PEOPLE.size()==21)
 assert(faculty.current.ac_lab!=faculty.current.dc_lab)
 assert("ELM253" in Roster.PEOPLE[faculty.current.ac_lab].courses)
 assert(Roster.PEOPLE[faculty.current.dc_lab].courses.any(func(c):return c in ["ETY155","DGS266"]))
 for course in ["MTH147","MTH255","ETY155","ELM253","DGS266"]:
  var selected: String=faculty.pick_lecture(course)
  assert(not selected.is_empty() and course in Roster.PEOPLE[selected].courses and selected not in faculty.current.values())
 var before: String=faculty.current.ac_lab
 game.lecture_classes.classes.ac_lab={"teacher":before}
 faculty.remaining.ac_lab=0
 faculty._process(1)
 assert(faculty.current.ac_lab==before)
 game.lecture_classes.classes.erase("ac_lab")
 faculty._process(1)
 if faculty.lab_handoffs.has("ac_lab"):
  var exchange: Dictionary=faculty.lab_handoffs.ac_lab
  assert(exchange.outgoing==before and exchange.incoming!=before)
  faculty._finish_lab_handoffs(int(exchange.due))
 assert(faculty.current.ac_lab!=before)
 assert(is_instance_valid(faculty.lunch))
 print("PASS faculty roster, eligibility and lab rotation lock")
 game.queue_free();await process_frame;quit()
