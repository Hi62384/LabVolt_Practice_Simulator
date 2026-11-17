extends SceneTree
## Render the ELM253 AC prediction and solver-backed reveal in the real room.
const Controller=preload("res://scripts/campus/academics/classroom_events/controller.gd")
func _initialize() -> void:call_deferred("run")
func _capture(path: String) -> bool:
 for i in 20:await process_frame
 await RenderingServer.frame_post_draw
 return root.get_texture().get_image().save_png(path)==OK
func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 var room:="elm253_lecture"
 var classes=game.lecture_classes
 var school=game.school
 game.campus.request_room(room)
 game.session.roster[1]={"name":"Student"}
 if not school.identities.has(1):school._identify(1,school.local_identity)
 game.player.global_position=classes.signs[room].desk
 assert(classes._start(room,{"kind":"lecture","course_id":"ELM253","week":3,"difficulty":0})=="")
 assert(classes._sign(1,room)=="")
 var activity: Dictionary=classes.classes[room]
 var now: float=classes._now()
 activity.phase="lesson";activity.deadline=now+180.0
 var owner:=Controller.new();classes.add_child(owner);owner.configure(game);owner.enabled=true
 assert(owner.service.start(room,now,[],"demonstration"))
 var round=owner.service.rooms[room].round
 assert(round.topology=="series" and round.reveal().is_empty())
 var camera:=Camera3D.new();game.add_child(camera);camera.current=true
 camera.global_position=classes.signs[room].board.global_position+Vector3(0,0,4.5)
 camera.look_at(owner.projector.board.global_position)
 var before:=ProjectSettings.globalize_path("res://.godot/classroom-ac-prediction.png")
 assert(await _capture(before))
 print("CLASSROOM_AC_PREDICTION_CAPTURE PASS ",before)
 assert(not owner.projector.board.signature.contains("Simulated:"))
 assert(owner.service.perform(1,room,activity.id,round.event_id,"submit",str(round.correct_option),now+1.0)=="accepted")
 owner.service.tick(now+30.0)
 owner.service.publish(room,now+30.0)
 assert(owner.service.view(1,room,now+30.0).result.correct)
 assert(owner.projector.board.signature.contains("AC network solver"))
 if owner.presentation.panel!=null:owner.presentation.panel.hide()
 var after:=ProjectSettings.globalize_path("res://.godot/classroom-ac-result.png")
 assert(await _capture(after))
 print("CLASSROOM_AC_RESULT_CAPTURE PASS ",after)
 game.queue_free();await process_frame;quit(0)
