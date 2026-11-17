extends SceneTree
## Three enrolled players in full Main: a late member joins one of two teams.
const Controller=preload("res://scripts/campus/academics/classroom_events/controller.gd")
class Probe:
 extends Node
 var votes:={}
 var results:={}
 var cleanup:={}
 @rpc("any_peer","call_remote","reliable")
 func vote_ack() -> void:votes[multiplayer.get_remote_sender_id()]=true
 @rpc("any_peer","call_remote","reliable")
 func result_ack() -> void:results[multiplayer.get_remote_sender_id()]=true
 @rpc("any_peer","call_remote","reliable")
 func cleanup_ack() -> void:cleanup[multiplayer.get_remote_sender_id()]=true
var game: Node
var owner: Node
var probe: Probe
var deadline: int
var statuses: Array=[]
func _initialize() -> void:call_deferred("run")
func wait_for(check: Callable,label: String) -> bool:
 while Time.get_ticks_msec()<deadline:
  if check.call():return true
  await create_timer(.05).timeout
 print("FULL GROUP STATE ",label," roster=",game.session.roster.keys()," identities=",game.school.identities," rooms=",owner.service.rooms.keys()," statuses=",statuses)
 push_error("FULL GROUP TIMEOUT "+label);quit(1);return false
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=1 or args[0] not in ["host","client_a","client_b"]:quit(1);return
 var role: String=args[0]
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 owner=Controller.new();owner.name="ClassroomEventsTest";game.lecture_classes.add_child(owner)
 owner.configure(game);owner.enabled=true;game.lecture_classes.classroom_events=owner
 probe=Probe.new();probe.name="GroupProbe";game.add_child(probe)
 owner.service.action_status_received.connect(func(_c: String,_e: String,op: String,status: String):statuses.append([op,status]))
 deadline=Time.get_ticks_msec()+90000
 var room:="ety155_lecture"
 var classes=game.lecture_classes
 var desk: Vector3=classes.signs[room].desk
 if role=="host":
  if game.session.host_game("Host",26362)!=OK:quit(1);return
  owner.enabled=true;game.player.global_position=desk
  if not await wait_for(func():return game.school.identities.has(1),"host identity"):return
  var error: String=classes._start(room,{"course_id":"ETY155","week":4,"kind":"lecture","difficulty":0})
  if not error.is_empty():push_error(error);quit(1);return
  var activity: Dictionary=classes.classes[room]
  activity.phase="lesson";activity.deadline=Time.get_ticks_msec()/1000.0+180.0
  if not classes._sign(1,room).is_empty():push_error("Host attendance failed");quit(1);return
  owner.attempted[str(activity.id)]={"count":3,"tries":0,"next":INF,"recent":[],"recent_modes":[]}
  classes._publish()
  print("FULL_GROUP_HOST_READY")
  if not await wait_for(func():return activity.students.size()==2,"first client enrollment"):return
  var first_peer: int=int(game.session.roster.keys().filter(func(peer):return peer!=1)[0])
  var now:=Time.get_ticks_msec()/1000.0
  if not owner.service.start(room,now,[],"group"):push_error("Group did not start");quit(1);return
  var state: Dictionary=owner.service.rooms[room]
  var id: String=state.round.event_id
  var host_identity: String=str(game.school.identities[1])
  if owner.service.perform(1,room,activity.id,id,"contribute","Host method",now+1.0)!="accepted":push_error("Host note failed");quit(1);return
  if owner.service.perform(1,room,activity.id,id,"vote",true,now+1.1)!="accepted":push_error("Host vote failed");quit(1);return
  owner.service.publish(room,now+1.1)
  print("FULL_GROUP_STARTED")
  if not await wait_for(func():
   owner.service.sync_roster(room,Time.get_ticks_msec()/1000.0)
   return activity.students.size()==3 and state.round.participants.size()==3
  ,"late enrollment"):return
  var late_peer: int=int(game.session.roster.keys().filter(func(peer):return peer!=1 and peer!=first_peer)[0])
  var first_identity: String=str(game.school.identities[first_peer])
  var late_identity: String=str(game.school.identities[late_peer])
  if state.shared.groups[late_identity]!="A":push_error("Late member not balanced into team A");quit(1);return
  if not await wait_for(func():return state.shared.entries.size()==2 and state.shared.votes.size()==3 and probe.votes.size()==2,"team notes and votes"):return
  var counts: Dictionary={"A":0,"B":0}
  for member in state.shared.groups:counts[state.shared.groups[member]]+=1
  if counts!={"A":2,"B":1}:push_error("Unbalanced teams: "+str(counts));quit(1);return
  for peer in [1,first_peer,late_peer]:
   var identity: String=str(game.school.identities[peer])
   var view: Dictionary=owner.service.view(peer,room,Time.get_ticks_msec()/1000.0)
   var shared: Dictionary=view.get("shared",{})
   if str(shared.get("group",""))!=str(state.shared.groups[identity]):push_error("Wrong team view");quit(1);return
   if int(shared.get("agree",0))!=counts[shared.group] or int(shared.get("disagree",0))!=0:push_error("Wrong team tally");quit(1);return
   for entry in shared.get("entries",[]):
    if entry.group!=shared.group:push_error("Cross-team note leak");quit(1);return
  owner.service.tick(now+30.0);owner.service.publish(room,now+30.0)
  for peer in [1,first_peer,late_peer]:
   var result: Dictionary=owner.service.view(peer,room,now+30.0).get("group_result",{})
   if int(result.get("members",0))!=counts[str(result.get("team",""))]:push_error("Wrong team result");quit(1);return
  if not await wait_for(func():return probe.results.size()==2,"client results"):return
  if not classes._begin_assignment(room,activity):push_error("Assignment failed");quit(1);return
  owner.step(Time.get_ticks_msec()/1000.0)
  if owner.service.rooms.has(room):push_error("Group survived assessment");quit(1);return
  if not await wait_for(func():return probe.cleanup.size()==2,"client cleanup"):return
  print("FULL_GROUP_HOST PASS")
 else:
  if game.session.join_game("127.0.0.1","Student",26362)!=OK:quit(1);return
  owner.enabled=true
  if not await wait_for(func():
   game.player.global_position=desk;game.session.send_pose({"position":desk})
   var own: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
   return game.session.roster.size()>1 and classes.public_classes.has(room) and own.get("position",Vector3.INF).distance_to(desk)<.6
  ,"class visible"):return
  await create_timer(.5).timeout
  classes._send("sign",room,{})
  if not await wait_for(func():return classes.public_classes.get(room,{}).get("signed",false),"attendance"):return
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.title_label.text=="Group exercise","group view"):return
  var class_id: String=owner.presentation.active_class
  var id: String=owner.presentation.active_id
  if role=="client_a":
   owner.service.request.rpc_id(1,room,class_id,id,"contribute","First student method")
   if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.vote_label.visible,"first team proposal"):return
  else:
   if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.vote_label.visible,"late team proposal"):return
  owner.service.request.rpc_id(1,room,class_id,id,"vote",true)
  if not await wait_for(func():return statuses.any(func(item):return item==["vote","accepted"]),"vote accepted"):return
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.vote_label.text.contains("Agree"),"team tally displayed"):return
  probe.vote_ack.rpc_id(1)
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.status_label.text.contains("correct of") and owner.presentation.panel.status_label.text.contains("members"),"team result"):return
  probe.result_ack.rpc_id(1)
  if not await wait_for(func():return owner.presentation.panel==null,"assessment cleanup"):return
  owner.service.request.rpc_id(1,room,class_id,id,"vote",false)
  if not await wait_for(func():return statuses.any(func(item):return item==["vote","denied"]),"stale vote denied"):return
  probe.cleanup_ack.rpc_id(1)
  await create_timer(.5).timeout
  print("FULL_GROUP_",role.to_upper()," PASS")
 game.session.leave();await create_timer(.2).timeout
 game.queue_free();await process_frame;quit(0)
