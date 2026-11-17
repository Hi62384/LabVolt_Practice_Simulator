extends SceneTree
## Isolated full-scene host lifecycle; the production feature gate remains off.
const Controller = preload("res://scripts/campus/academics/classroom_events/controller.gd")
var game: Node
var owner: Node
var deadline: int

func _initialize() -> void:
 call_deferred("run")

func wait_for(check: Callable, label: String) -> bool:
 while Time.get_ticks_msec() < deadline:
  if check.call(): return true
  await create_timer(.05).timeout
 push_error("LIVE HOST TIMEOUT " + label)
 quit(1)
 return false

func run() -> void:
 game = load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 for i in 4: await process_frame
 game.front.entered()
 owner = Controller.new()
 game.lecture_classes.add_child(owner)
 owner.configure(game)
 game.lecture_classes.classroom_events = owner
 deadline = Time.get_ticks_msec() + 60000
 var room := "ety155_lecture"
 if game.session.host_game("Host", 26379) != OK: quit(1); return
 owner.enabled = true
 game.player.global_position = game.lecture_classes.signs[room].desk
 if not await wait_for(func(): return game.school.identities.has(1), "identity"): return
 var error: String = game.lecture_classes._start(room, {"course_id":"ETY155", "week":1, "kind":"lecture", "difficulty":0})
 if not error.is_empty(): push_error(error); quit(1); return
 game.lecture_classes._sign(1, room)
 var activity: Dictionary = game.lecture_classes.classes[room]
 activity.phase = "lesson"
 activity.deadline = Time.get_ticks_msec() / 1000.0 + 200.0
 game.lecture_classes._publish()
 if not await wait_for(func(): return is_instance_valid(owner.presentation.panel), "practice view"): return
 var panel: Control = owner.presentation.panel
 if is_instance_valid(panel.options): panel.options.select(0)
 elif is_instance_valid(panel.entry): panel.entry.text = "0"
 else: push_error("Unsupported practice input"); quit(1); return
 panel._submit()
 if not await wait_for(func(): return owner.service.rooms.has(room) and not owner.service.rooms[room].round.submissions.is_empty(), "submission"): return
 if not game.lecture_classes._begin_assignment(room, activity): push_error("Official assignment failed"); quit(1); return
 owner.step(Time.get_ticks_msec() / 1000.0)
 if owner.service.rooms.has(room) or activity.phase != "assignment" or activity.students.values().any(func(s): return s.done):
  push_error("Practice affected assignment transition"); quit(1); return
 game.session.leave()
 await create_timer(.2).timeout
 game.queue_free()
 await process_frame
 print("LIVE_CLASSROOM_SINGLE_HOST PASS")
 quit(0)
