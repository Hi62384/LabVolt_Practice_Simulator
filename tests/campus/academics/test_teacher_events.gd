extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
func _initialize():call_deferred("run")
func run():
 create_timer(40.).timeout.connect(func():quit(1))
 var brain=Brain.new();var p: Dictionary=Dialogue.personalities().mr_stone
 assert(Brain.audibility("class_message",0.0,false)==1.0)
 assert(Brain.audibility("class_message",7.0,false)==0.0)
 assert(Brain.audibility("lab_hazard",8.0,false)>0.0)
 assert(Brain.audibility("lab_hazard",2.0,true)<Brain.audibility("lab_hazard",2.0,false))
 assert(Brain.visibility(Vector3.ZERO,Vector3.FORWARD,Vector3.FORWARD*2,false)>0.0)
 assert(Brain.visibility(Vector3.ZERO,Vector3.FORWARD,Vector3.BACK*2,false)==0.0)
 assert(Brain.visibility(Vector3.ZERO,Vector3.FORWARD,Vector3.FORWARD*2,true)==0.0)
 assert(Brain.visibility(Vector3.ZERO,Vector3.FORWARD,Vector3.FORWARD*11,false)==0.0)
 assert(brain.consider("mr_stone","inaudible","lab_hazard",1.0,p,1000,.5,0.0).is_empty())
 assert(not brain.incidents.has("mr_stone:inaudible"))
 assert(brain.consider("mr_stone","student","class_message",.25,p,1000,1.0).is_empty())
 assert(brain.incidents.is_empty())
 var first: Dictionary=brain.consider("mr_stone","student","lab_hazard",1.0,p,2000,0.0)
 assert(first.intent=="hazard" and first.student=="student")
 assert(brain.consider("mr_stone","student","lab_hazard",1.0,p,2500,0.0).is_empty())
 assert(brain.incidents["mr_stone:student"].count==2)
 var before_duplicate:=int(brain.incidents["mr_stone:student"].count)
 assert(brain.consider("mr_stone","student","voice_noise",1.0,p,2600,0.0).is_empty())
 assert(int(brain.incidents["mr_stone:student"].count)==before_duplicate+1)
 var overlap:=Brain.new()
 overlap.consider("mr_stone","speaker","voice_noise",1.0,p,5000,0.0)
 assert(overlap.incidents["mr_stone:speaker"].count==1)
 overlap.consider("mr_stone","speaker","class_message",1.0,p,5100,0.0)
 assert(overlap.incidents["mr_stone:speaker"].count==1)
 assert(not brain.consider("mr_stone","student","lab_hazard",1.0,p,15000,0.0).is_empty())
 assert(Dialogue.message_intent("Mr Stone, can you help me?")=="help")
 assert(Dialogue.message_intent("I'm sorry, Mr Stone")=="apology")
 assert(Dialogue.message_intent("Hi, Mr Stone")=="greeting")
 assert(Dialogue.message_intent("Which topic is next?")=="question")
 assert(Dialogue.message_intent("This is a shipment")=="chat")
 assert(Dialogue.respond("mr_stone","help",{},0).is_empty() and Dialogue.respond("mr_stone","apology",{},0).is_empty(),"Ordinary event intents require the character pipeline, not scripted speech")
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.singleplayer_page();game.front._start_play(true)
 game.faculty.set_process(false);game.lecture_classes.set_process(false)
 game.player.set_physics_process(false)
 game.host_openai.enabled=false
 var identity: String=game.school.identities[1]
 game.faculty.current.ac_lab="mr_phillips"
 game.faculty._sync_lab_teachers()
 # Office-hours instructors can still be walking in from the door. Perception
 # is measured from their actual model, not the old fixed teacher root.
 game.player.global_position=game.faculty._teacher_position("ac_lab")+Vector3(0,0,1)
 assert(game.campus.registry.locate(game.player.global_position)=="ac_lab")
 var far: Vector3=game.player.global_position+Vector3(30,0,0)
 game.faculty.report_event(1,"ac_lab","lab_hazard",far,1.0)
 assert(game.faculty.brain.incidents.is_empty())
 game.faculty.rng.seed=1
 assert(not game.faculty.report_event(1,"ac_lab","lab_hazard",game.player.global_position,1.0),"An unverified claimed fault cannot trigger discipline")
 var lab=game.session.labs[0]
 lab.cables.append({"id":10001,"a":"PV_A","b":"PV_N","owner":0,"color":0})
 var before_fault: Dictionary=lab.snapshot()
 lab.powered=true;lab.recalculate()
 assert(not lab.powered and not str(lab.readings.get("fault","")).is_empty())
 game.session.academic_equipment_observer.call(1,0,{"op":"power"},before_fault)
 assert(game.faculty.brain.incidents.has("mr_phillips:"+identity))
 assert(game.faculty.reaction_labels.has("ac_lab"))
 assert(game.faculty.attention.has("ac_lab"))
 var model: Node3D=game.faculty.attention.ac_lab.model
 var before: float=model.rotation.y
 game.faculty._process(.1)
 assert(not is_equal_approx(before,model.rotation.y))
 game.faculty.attention.ac_lab.until=0
 for i in 40:game.faculty._process(.1)
 assert(not game.faculty.attention.has("ac_lab"))
 assert(game.faculty.reaction_labels.ac_lab.text.contains("circuit") or game.faculty.reaction_labels.ac_lab.text.contains("fault"))
 var room="elm253_lecture"
 # This fixture supplies a synthetic class only for faculty perception; do not
 # let the real class scheduler advance or publish it between assertions.
 game.lecture_classes.set_process(false)
 game.lecture_classes.classes[room]={"teacher":"mr_stone","phase":"lesson","course":"MTH147","id":"teacher-event-fixture","deadline":Time.get_ticks_msec()/1000.0+120.0,"students":{identity:{"peer":1,"done":false,"failure":"","project":{}}}}
 game.lecture_classes.public_classes[room]={"teacher":"mr_stone","phase":"lesson","course":"MTH147","signed":true,"done":false,"seconds":120.0,"id":"teacher-event-fixture","stage":{},"number":"M201","week":1}
 game.faculty._sync_lectures()
 game.player.global_position=game.faculty._teacher_position(room)+Vector3(1,0,1)
 assert(game.campus.registry.locate(game.player.global_position)==room)
 game.faculty.rng.seed=1
 game.faculty._on_player_message(1,"Student","private contents are not stored")
 for frame in 2:await process_frame
 assert(game.faculty.brain.incidents.has("mr_stone:"+identity))
 assert(not str(game.faculty.brain.incidents).contains("private contents"))
 game.faculty.brain.teachers.clear();game.faculty.brain.reaction_times.clear()
 game.faculty._on_player_message(1,"Student","Mr Stone, I'm sorry")
 for frame in 2:await process_frame
 var apology: Dictionary=game.faculty.character_interaction.diagnostics.back()
 assert(apology.character=="mr_stone" and apology.interpretation.event=="apology")
 assert(game.faculty.brain.recall("mr_stone",identity).any(func(turn):return str(turn.get("student","")).contains("sorry")),"A perceived apology is remembered even if forgiveness is withheld")
 game.faculty.brain.teachers.clear();game.faculty.brain.reaction_times.clear();game.faculty.brain.incidents.clear();game.faculty.rng.seed=1
 game.lecture_classes.classes[room].phase="assignment"
 game.lecture_classes.public_classes[room].phase="assignment"
 game.faculty._on_player_message(1,"Student","ordinary classroom conversation")
 for frame in 2:await process_frame
 assert(game.faculty.brain.incidents.has("mr_stone:"+identity))
 assert(game.lecture_classes.classes[room].phase=="assignment")
 game.faculty.brain.incidents.clear();game.faculty.brain.reaction_times.clear()
 game.faculty.rng.seed=1
 game.faculty._on_player_message(1,"Student","Mr Stone, can you help me?")
 for frame in 2:await process_frame
 assert(game.faculty.brain.incidents.has("mr_stone:"+identity))
 assert(game.faculty.brain.incidents["mr_stone:"+identity].kind=="class_message")
 game.lecture_classes.classes.erase(room);game.lecture_classes.public_classes.erase(room)
 print("PASS perceived hazard reactions, class messages, cooldown and per-student memory")
 game.queue_free();await process_frame;quit()

