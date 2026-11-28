extends SceneTree
func _initialize():call_deferred("run")
func run():
 create_timer(40.).timeout.connect(func():quit(1))
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.singleplayer_page();game.front._start_play(true)
 game.faculty.set_process(false);game.lecture_classes.set_process(false)
 game.player.set_physics_process(false);game.host_openai.enabled=false
 var identity: String=game.school.identities[1]
 assert(not identity.is_empty() and game.faculty._sync_character_profile())
 game.faculty.current.ac_lab="mr_phillips";game.faculty.rng.seed=1
 game.faculty._sync_lab_teachers()
 game.player.global_position=game.faculty._teacher_position("ac_lab")+Vector3(0,0,1)
 assert(game.campus.registry.locate(game.player.global_position)=="ac_lab")
 var lab=game.session.labs[0]
 lab.cables.append({"id":10001,"a":"PV_A","b":"PV_N","owner":0,"color":0})
 var before: Dictionary=lab.snapshot()
 lab.powered=true;lab.recalculate()
 assert(not lab.powered and not str(lab.readings.get("fault","")).is_empty())
 game.session.academic_equipment_observer.call(1,0,{"op":"power"},before)
 assert(game.faculty.brain.incidents.has("mr_phillips:"+identity))
 assert(game.faculty.speech_player.subtitles.has("ac_lab"))
 assert(game.faculty.reaction_labels.is_empty(),"Fault speech is presented through the subtitle HUD")
 print("PASS teacher reacts to actual AC source-short fault")
 game.queue_free();await process_frame;quit()
