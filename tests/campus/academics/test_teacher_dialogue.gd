extends SceneTree
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
func _initialize():call_deferred("run")
func run():
 var expected={"bill_nye":[.65,.90,.75,.50],"mr_apple":[.30,.60,.40,.90],"ms_clocks":[.95,.90,.50,.40],"mr_phillips":[.75,.95,.40,.65],"mr_gusto":[.85,.90,.70,.85],"mr_hamstrings":[.30,.20,.70,.95],"mr_allu":[.20,.10,.20,.10],"bill":[.40,1.0,.90,.50],"chad":[.10,.10,.10,.90],"brian":[.30,.95,.50,.30],"ms_bird_heart":[.20,.50,.80,.90],"dr_volts":[.80,.40,1.0,1.0],"stanley":[.05,.05,.40,.10],"ms_rivera":[.05,.05,.10,.40],"mr_blake":[.70,.20,.50,.90],"mr_stone":[.70,1.0,1.0,.60],"josh_wildes":[.10,.20,.90,.40],"bradley":[.70,.50,.50,.60],"jeff":[1.0,1.0,1.0,.30],"mr_bro":[.30,.10,.30,.90]}
 var all=Dialogue.personalities()
 assert(all.size()==Roster.PEOPLE.size())
 for id in expected:
  var p: Dictionary=all[id]
  assert([p.teaching,p.focus,p.difficulty,p.talkativeness]==expected[id])
  assert(not Dialogue.respond(id,"help",{"course":"ELM253"},0).is_empty())
 assert(all.ms_lunch.teaching==null and all.ms_lunch.focus==null)
 assert(Dialogue.respond("jeff","chat",{"in_class":false},0)!=Dialogue.respond("jeff","chat",{"in_class":true},0))
 var logic_help:=Dialogue.respond("mr_hamstrings","help",{"course":"DGS266","phase":"lesson","title":"Logic gates"},0)
 assert("Logic gates" in logic_help and "truth table" in logic_help)
 var circuit_help:=Dialogue.respond("dr_volts","help",{"course":"ETY155","phase":"lesson"},0)
 assert("polarity" in circuit_help)
 var assessment_help:=Dialogue.respond("dr_volts","help",{"course":"DGS266","phase":"assignment","title":"Secret solution"},0)
 assert(assessment_help.contains("assessment") and not assessment_help.contains("Secret solution") and not assessment_help.contains("truth table"))
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered();game.player.global_position=game.school_world.teacher.global_position
 game.faculty.open_conversation("ac_lab")
 assert(game.faculty.conversation.visible and game.faculty.conversation_text.text!="…")
 assert(game.faculty.conversation_name.text==Roster.PEOPLE[game.faculty.current.ac_lab].name)
 game.faculty.last_dialogue[1]=-1000
 game.faculty._conversation_choice("help")
 assert(not game.faculty.conversation_text.text.is_empty())
 game.faculty.close_conversation();assert(not game.faculty.conversation.visible)
 print("PASS teacher personality values and host-validated conversation")
 game.queue_free();await process_frame;quit()
