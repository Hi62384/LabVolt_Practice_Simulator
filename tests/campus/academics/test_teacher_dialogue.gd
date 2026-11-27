extends SceneTree
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
func _initialize():call_deferred("run")
func run():
 var all=Dialogue.personalities()
 assert(all.size()==Roster.PEOPLE.size())
 for id in Roster.PEOPLE:
  var p: Dictionary=all[id]
  # The classroom adapter must use the full authoritative character, not a
  # second table of legacy numbers that contradicts current authored traits.
  assert(p==Profiles.classroom(id))
  assert(not Dialogue.respond(id,"help",{"course":"ELM253"},0).is_empty())
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
