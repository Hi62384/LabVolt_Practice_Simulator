extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 game.school.identities[1]="0123456789abcdef0123456789abcdef0123456789abcdef"
 game.faculty.current.ac_lab="mr_phillips";game.faculty.rng.seed=1
 game.player.global_position=game.school_world.teacher.global_position+Vector3(0,0,1)
 var lab=game.session.labs[0]
 lab.cables.append({"id":10001,"a":"PV_A","b":"PV_N","owner":0,"color":0})
 var before: Dictionary=lab.snapshot()
 lab.powered=true;lab.recalculate()
 assert(not lab.powered and not str(lab.readings.get("fault","")).is_empty())
 game.session.academic_equipment_observer.call(1,0,{"op":"power"},before)
 assert(game.faculty.reaction_labels.has("ac_lab"))
 print("PASS teacher reacts to actual AC source-short fault")
 game.queue_free();await process_frame;quit()
