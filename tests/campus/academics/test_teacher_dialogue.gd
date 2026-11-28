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
  assert(Dialogue.respond(id,"help",{"course":"ELM253"},0).is_empty(),"Ordinary help is generated from the authoritative profile")
 assert(Dialogue.respond("jeff","chat",{"in_class":false},0).is_empty() and Dialogue.respond("jeff","chat",{"in_class":true},0).is_empty())
 var wrap:=Dialogue.lesson_wrap_intention(all.mr_hamstrings,"DGS266")
 assert(wrap.contains("DGS266") and wrap.contains("individual") and wrap.contains("own manner"))
 var critical:=Dialogue.respond("dr_volts","hazard",{"course":"ETY155","phase":"lesson"},0)
 assert(critical.contains("Power is off") and critical.contains("connections"),"Safety-critical verified equipment instructions remain locally available")
 var assessment_help:=Dialogue.respond("dr_volts","help",{"course":"DGS266","phase":"assignment","title":"Secret solution"},0)
 assert(assessment_help.is_empty(),"Legacy entry points cannot expose assessment content or pretend to give character speech")
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.singleplayer_page();game.front._start_play(true)
 game.host_openai.enabled=false
 game.faculty.set_process(false);game.lecture_classes.set_process(false);game.player.set_physics_process(false)
 game.player.global_position=game.faculty._teacher_position("ac_lab")+Vector3(0,0,1)
 var before: int=game.faculty.character_interaction.diagnostics.size()
 game.faculty.open_conversation("ac_lab")
 assert(game.faculty.conversation.visible and game.faculty.conversation_text.text!="…")
 assert(game.faculty.conversation_name.text==Roster.PEOPLE[game.faculty.current.ac_lab].name)
 assert(game.faculty.character_interaction.diagnostics.size()==before,"Opening the character inspector is not a social event or AI request")
 game.faculty.last_dialogue[1]=-1000
 game.faculty._conversation_choice("help")
 assert(not game.faculty.conversation_text.text.is_empty())
 game.faculty.close_conversation();assert(not game.faculty.conversation.visible)
 print("PASS authoritative teacher profiles, intention routing, safety instructions and passive character inspection")
 game.queue_free();await process_frame;quit()
