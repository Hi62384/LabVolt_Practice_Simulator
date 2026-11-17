extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 game.school.start("Freeplay",0)
 var faculty=game.faculty
 var peer: int=game.multiplayer.get_unique_id()
 var identity:=str(game.school.identities.get(peer,""))
 assert(not identity.is_empty())
 game.school_world.teacher.global_position=game.school.teacher_position
 game.player.global_position=Vector3(0,0,8.5)
 game.lecture_classes.classes.ac_lab={"teacher":faculty.current.ac_lab}
 faculty._call_request(peer,"ac_lab")
 assert(not faculty.calls.has("ac_lab"))
 game.lecture_classes.classes.erase("ac_lab")
 faculty.call_cooldowns.erase(peer)
 faculty._call_request(peer,"ac_lab")
 assert(faculty.calls.has("ac_lab"))
 var first: Dictionary=faculty.calls.ac_lab.duplicate()
 var guest:=991
 game.session.roster[guest]={"name":"Other student","ready":false}
 game.school.identities[guest]="other-student"
 game.session.poses[guest]={"position":Vector3(0,0,4)}
 faculty._call_request(guest,"ac_lab")
 assert(faculty.calls.ac_lab.peer==peer)
 game.session.roster.erase(guest)
 game.school.identities.erase(guest)
 game.session.poses.erase(guest)
 faculty._call_request(peer,"ac_lab")
 assert(faculty.calls.ac_lab==first)
 faculty.call_cooldowns.erase(peer)
 faculty._call_request(peer,"ac_lab")
 assert(faculty.calls.ac_lab==first)
 var before: Vector3=game.school.teacher_position
 for i in 45:
  faculty._advance_call("ac_lab",.1)
  await process_frame
 assert(game.school.teacher_position.distance_to(before)>.01)
 game.player.global_position=game.school_world.teacher.global_position+Vector3(1.5,0,0)
 faculty._advance_call("ac_lab",.1)
 assert(faculty.calls.ac_lab.arrived)
 game.lecture_classes.classes.ac_lab={"teacher":faculty.current.ac_lab}
 faculty._advance_call("ac_lab",.1)
 assert(not faculty.calls.has("ac_lab"))
 game.lecture_classes.classes.erase("ac_lab")
 faculty.call_cooldowns.erase(peer)
 faculty._call_request(peer,"ac_lab")
 assert(faculty.calls.has("ac_lab"))
 faculty.calls.ac_lab.identity="stale"
 faculty._advance_call("ac_lab",.1)
 assert(not faculty.calls.has("ac_lab"))
 faculty.call_cooldowns.erase(peer)
 faculty._call_request(peer,"ac_lab")
 assert(faculty.calls.has("ac_lab"))
 faculty.calls.ac_lab.peer=guest
 faculty.last_dialogue[guest]=123
 faculty.dialogue_counter["%d:mr_phillips"%guest]=2
 faculty._prune_calls()
 assert(not faculty.calls.has("ac_lab"))
 assert(not faculty.last_dialogue.has(guest))
 assert(not faculty.dialogue_counter.has("%d:mr_phillips"%guest))
 faculty.call_cooldowns.erase(peer)
 faculty._call_request(peer,"ac_lab")
 assert(faculty.calls.has("ac_lab"))
 var teacher_before:=str(faculty.current.ac_lab)
 faculty.current.ac_lab="unavailable"
 faculty._advance_call("ac_lab",.1)
 assert(not faculty.calls.has("ac_lab"))
 faculty.current.ac_lab=teacher_before
 game.player.global_position=Vector3(0,0,3)
 faculty.call_cooldowns.erase(peer)
 faculty._call_request(peer,"ac_lab")
 assert(faculty.calls.has("ac_lab"))
 faculty.calls.ac_lab.until=0
 faculty._advance_call("ac_lab",.1)
 assert(not faculty.calls.has("ac_lab"))
 assert(game.school.teacher_goal==Vector3(2,0,4))
 game.school_world.dc_instructor.global_position=faculty.dc_home+Vector3(-1,0,0)
 faculty._return_dc_home(2.0)
 assert(game.school_world.dc_instructor.global_position.distance_to(faculty.dc_home)<.02)
 game.player.global_position=faculty.dc_home+Vector3(-3,0,0)
 faculty.call_cooldowns.erase(peer)
 faculty._call_request(peer,"dc_lab")
 assert(faculty.calls.has("dc_lab"))
 faculty.calls.dc_lab.until=0
 faculty._advance_call("dc_lab",.1)
 assert(not faculty.calls.has("dc_lab"))
 print("PASS teacher call validation, repeat requests, movement, stale caller, and cleanup")
 game.queue_free()
 await process_frame
 quit()
