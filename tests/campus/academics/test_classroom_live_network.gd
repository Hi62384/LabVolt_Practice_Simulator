extends SceneTree
## Full-scene test, isolated saves and local ENet only. Production gate stays off.
const Controller=preload("res://scripts/campus/academics/classroom_events/controller.gd")
var game: Node
var owner: Node
var deadline: int
var submission_status := ""
func _initialize() -> void:call_deferred("run")
func wait_for(check: Callable,label: String) -> bool:
 while Time.get_ticks_msec()<deadline:
  if check.call():return true
  await create_timer(.05).timeout
 if label in ["practice started","practice submitted","submission status"]:
  print("LIVE CLASSROOM STATE ",label," rooms=",owner.service.rooms.keys()," attempted=",owner.attempted," presentation=",owner.presentation.active_id)
 push_error("LIVE CLASSROOM TIMEOUT "+label);quit(1);return false
func run() -> void:
 var host:=OS.get_cmdline_user_args()[0]=="host"
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 owner=Controller.new();owner.name="ClassroomEventsTest";game.lecture_classes.add_child(owner)
 owner.configure(game);owner.enabled=true;game.lecture_classes.classroom_events=owner
 deadline=Time.get_ticks_msec()+60000
 var room:="ety155_lecture"
 var desk: Vector3=game.lecture_classes.signs[room].desk
 if host:
  if game.session.host_game("Host",26359)!=OK:quit(1);return
  owner.enabled=true
  game.player.global_position=desk
  if not await wait_for(func():return game.school.identities.has(1),"host identity"):return
  var error: String=game.lecture_classes._start(room,{"course_id":"ETY155","week":1,"kind":"lecture","difficulty":0})
  if not error.is_empty():push_error("Could not start class: "+error);quit(1);return
  game.lecture_classes.classes[room].phase="lesson"
  game.lecture_classes.classes[room].deadline=Time.get_ticks_msec()/1000.0+300.0
  game.lecture_classes._publish()
  print("LIVE_CLASSROOM_HOST_READY")
  if not await wait_for(func():return game.lecture_classes.classes[room].students.size()==1,"client enrollment"):return
  var activity: Dictionary=game.lecture_classes.classes[room]
  activity.deadline=Time.get_ticks_msec()/1000.0+200.0
  # The controller may have scheduled against the original class deadline
  # before this fixture advances the lesson clock.
  owner.attempted.erase(str(activity.id))
  if not await wait_for(func():return owner.service.rooms.has(room),"practice started"):return
  if not await wait_for(func():return owner.service.rooms.has(room) and not owner.service.rooms[room].round.submissions.is_empty(),"practice submitted"):return
  if not game.lecture_classes._begin_assignment(room,activity):push_error("Official assignment failed");quit(1);return
  owner.step(Time.get_ticks_msec()/1000.0)
  if owner.service.rooms.has(room):push_error("Practice survived assignment transition");quit(1);return
  if activity.phase!="assignment" or activity.students.values().any(func(s):return s.done):push_error("Practice altered official student status");quit(1);return
  await create_timer(2).timeout
  print("LIVE_CLASSROOM_HOST PASS")
 else:
  if game.session.join_game("127.0.0.1","Student",26359)!=OK:quit(1);return
  owner.enabled=true
  if not await wait_for(func():
   game.player.global_position=desk;game.session.send_pose({"position":desk})
   var own: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
   return game.session.roster.size()==2 and game.lecture_classes.public_classes.has(room) and own.get("position",Vector3.INF).distance_to(desk)<.6
  ,"class visible"):return
  game.lecture_classes._send("sign",room,{})
  if not await wait_for(func():return game.lecture_classes.public_classes.get(room,{}).get("signed",false),"attendance"):return
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel),"practice view"):return
  var panel: Control=owner.presentation.panel
  var class_id: String=owner.presentation.active_class
  var event_id: String=owner.presentation.active_id
  owner.service.action_status_received.connect(func(c,e,op,status):
   if c==class_id and e==event_id and op=="submit":submission_status=status
  )
  if is_instance_valid(panel.options):panel.options.select(0)
  elif is_instance_valid(panel.entry):panel.entry.text="0"
  else:push_error("Unsupported practice input");quit(1);return
  panel._submit()
  if not await wait_for(func():return not submission_status.is_empty(),"submission status"):return
  if submission_status=="retry":
   submission_status=""
   panel._submit()
   if not await wait_for(func():return not submission_status.is_empty(),"submission status"):return
  if submission_status!="accepted":push_error("Submission rejected: "+submission_status+" class="+class_id+" event="+event_id);quit(1);return
  if not await wait_for(func():return owner.presentation.panel==null,"assignment removed practice"):return
  print("LIVE_CLASSROOM_CLIENT PASS")
 game.session.leave()
 await create_timer(.2).timeout
 game.queue_free();await process_frame;quit(0)
