extends SceneTree
## Full Main host/client board exercise with isolated saves and the gate enabled only here.
const Controller=preload("res://scripts/campus/academics/classroom_events/controller.gd")
class Probe:
 extends Node
 var cleanup_acks:=0
 var reveal_acks:=0
 var rejoin_acks:=0
 var vote_acks:=0
 @rpc("any_peer","call_remote","reliable")
 func cleanup_ack() -> void:cleanup_acks+=1
 @rpc("any_peer","call_remote","reliable")
 func reveal_ack() -> void:reveal_acks+=1
 @rpc("any_peer","call_remote","reliable")
 func rejoin_ack() -> void:rejoin_acks+=1
 @rpc("any_peer","call_remote","reliable")
 func vote_ack() -> void:vote_acks+=1
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
 print("FULL BOARD STATE ",label," roster=",game.session.roster.keys()," identities=",game.school.identities," poses=",game.session.poses," classes=",game.lecture_classes.public_classes.keys()," rooms=",owner.service.rooms.keys())
 if label=="group note and vote" and owner.service.rooms.has("ety155_lecture"):
  var shared=owner.service.rooms["ety155_lecture"].shared
  print("FULL BOARD GROUP STATE entries=",shared.entries," votes=",shared.votes," present=",shared.present)
 print("FULL BOARD STATUSES ",statuses)
 push_error("FULL BOARD TIMEOUT "+label);quit(1);return false
func board_paper(room: String) -> Dictionary:
 for paper in game.school.papers.values():
  if paper.get("classroom_board","")==room:return paper
 return {}
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=1 or args[0] not in ["host","client"]:quit(1);return
 var host: bool=args[0]=="host"
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 owner=Controller.new();owner.name="ClassroomEventsTest";game.lecture_classes.add_child(owner)
 owner.configure(game);owner.enabled=true;game.lecture_classes.classroom_events=owner
 probe=Probe.new();probe.name="BoardProbe";game.add_child(probe)
 owner.service.action_status_received.connect(func(_c: String,_e: String,op: String,status: String):statuses.append([op,status]))
 deadline=Time.get_ticks_msec()+90000
 var room:="ety155_lecture"
 var desk: Vector3=game.lecture_classes.signs[room].desk
 if host:
  if game.session.host_game("Host",26361)!=OK:quit(1);return
  owner.enabled=true;game.player.global_position=desk
  if not await wait_for(func():return game.school.identities.has(1),"host identity"):return
  var error: String=game.lecture_classes._start(room,{"course_id":"ETY155","week":4,"kind":"lecture","difficulty":0})
  if not error.is_empty():push_error(error);quit(1);return
  var activity: Dictionary=game.lecture_classes.classes[room]
  activity.phase="lesson";activity.deadline=Time.get_ticks_msec()/1000.0+180.0
  owner.attempted[str(activity.id)]={"count":3,"tries":0,"next":INF,"recent":[],"recent_modes":[]}
  game.lecture_classes._publish()
  game.school._ensure_classroom_whiteboards()
  print("FULL_BOARD_HOST_READY")
  if not await wait_for(func():return activity.students.size()==1,"client enrollment"):return
  var remote: int=int(activity.students.values()[0].peer)
  var selected: String=str(game.school.identities.get(remote,""))
  var paper: Dictionary=board_paper(room)
  if paper.is_empty() or selected.is_empty():push_error("Board or selected student missing");quit(1);return
  var now:=Time.get_ticks_msec()/1000.0
  if not owner.service.start(room,now,[],"board"):push_error("Board round did not start");quit(1);return
  var state: Dictionary=owner.service.rooms[room]
  if not state.hands.call_student(true,state.round.event_id,selected):push_error("Selection failed");quit(1);return
  owner.service.publish(room,now)
  if not await wait_for(func():return paper.get("board_lines",[]).size()==1 and paper.get("board_notes",[]).size()==1,"live stroke and note"):return
  if not await wait_for(func():return not game.session.roster.has(remote),"writer disconnected"):return
  owner.service.sync_roster(room,Time.get_ticks_msec()/1000.0)
  if owner.service.can_mark_board(remote,room,Time.get_ticks_msec()/1000.0):push_error("Old peer retained board selection");quit(1);return
  if not await wait_for(func():return game.session.roster.size()==2,"writer reconnected"):return
  remote=int(game.session.roster.keys().filter(func(peer):return peer!=1)[0])
  if not await wait_for(func():return str(game.school.identities.get(remote,""))==selected and game.school._near(remote,paper.position),"writer identity and pose restored"):return
  owner.service.sync_roster(room,Time.get_ticks_msec()/1000.0)
  if owner.service.can_mark_board(remote,room,Time.get_ticks_msec()/1000.0):push_error("Rejoin bypassed teacher selection");quit(1);return
  game.school.broadcast();owner.service.publish(room,Time.get_ticks_msec()/1000.0)
  if not await wait_for(func():return probe.rejoin_acks>=1,"client restored board snapshot"):return
  await create_timer(.5).timeout
  if paper.board_lines.size()!=1:push_error("Unselected rejoin changed board");quit(1);return
  owner.service.tick(now+30.0);owner.service.tick(now+41.0)
  if owner.service.rooms.has(room):push_error("Board result did not clean up");quit(1);return
  var group_now:=Time.get_ticks_msec()/1000.0
  if not owner.service.start(room,group_now,[],"group"):push_error("Group round did not start");quit(1);return
  if not await wait_for(func():return owner.service.rooms.has(room) and owner.service.rooms[room].shared.entries.size()==1 and owner.service.rooms[room].shared.votes.get(selected,false),"group note and vote"):return
  var observer_view: Dictionary=owner.service.view(1,room,Time.get_ticks_msec()/1000.0)
  if not observer_view.get("shared",{}).get("entries",[]).is_empty() or not str(observer_view.get("shared",{}).get("proposal","")).is_empty():push_error("Observer saw team work");quit(1);return
  if not await wait_for(func():return probe.vote_acks>=1,"client saw group vote"):return
  owner.service.tick(group_now+30.0);owner.service.tick(group_now+41.0)
  if owner.service.rooms.has(room):push_error("Group result did not clean up");quit(1);return
  var demo_now:=Time.get_ticks_msec()/1000.0
  if not owner.service.start(room,demo_now,[],"demonstration"):push_error("Demonstration did not start");quit(1);return
  if not await wait_for(func():return owner.service.rooms.has(room) and owner.service.rooms[room].round.submissions.has(selected),"demo prediction"):return
  if owner.service.view(remote,room,Time.get_ticks_msec()/1000.0).has("reveal"):push_error("Demo answer leaked early");quit(1);return
  owner.service.tick(demo_now+30.0)
  owner.service.publish(room,demo_now+30.0)
  if not owner.service.view(remote,room,demo_now+30.0).has("reveal"):push_error("Demo reveal missing");quit(1);return
  if not await wait_for(func():return probe.reveal_acks>=1,"client saw demonstration reveal"):return
  if not game.lecture_classes._begin_assignment(room,activity):push_error("Assignment failed");quit(1);return
  owner.step(Time.get_ticks_msec()/1000.0)
  if owner.service.rooms.has(room):push_error("Demonstration survived assignment");quit(1);return
  if not await wait_for(func():return probe.cleanup_acks>=1,"client cleanup acknowledgement"):return
  await create_timer(.5).timeout
  if paper.board_lines.size()!=1 or paper.board_notes.size()!=1:push_error("Stale write changed board");quit(1);return
  print("FULL_BOARD_HOST PASS")
 else:
  print("FULL_BOARD_CLIENT_LOADING")
  if game.session.join_game("127.0.0.1","Student",26361)!=OK:quit(1);return
  print("FULL_BOARD_CLIENT_JOINED")
  owner.enabled=true
  if not await wait_for(func():
   game.player.global_position=desk;game.session.send_pose({"position":desk})
   var own: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
   return game.session.roster.size()==2 and game.lecture_classes.public_classes.has(room) and own.get("position",Vector3.INF).distance_to(desk)<.6
  ,"class visible"):return
  await create_timer(.5).timeout
  game.lecture_classes._send("sign",room,{})
  if not await wait_for(func():return game.lecture_classes.public_classes.get(room,{}).get("signed",false),"attendance"):return
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.get("seconds_left")>0 and owner.presentation.panel.get("hand_label").text.contains("walk"),"selected board view"):return
  var class_id: String=owner.presentation.active_class
  var event_id: String=owner.presentation.active_id
  if not await wait_for(func():return not board_paper(room).is_empty(),"board snapshot"):return
  var paper: Dictionary=board_paper(room)
  var point: Vector3=paper.position+Vector3(0,-1,2)
  if not await wait_for(func():
   game.player.global_position=point;game.session.send_pose({"position":point})
   return game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(point)<.6
  ,"board proximity"):return
  game.school.request({"op":"board_mark","id":paper.id,"from":Vector2(.2,.2),"point":Vector2(.4,.4),"erase":false})
  owner.service.request.rpc_id(1,room,class_id,event_id,"contribute","I = V / R")
  if not await wait_for(func():return board_paper(room).get("board_lines",[]).size()==1 and board_paper(room).get("board_notes",[]).size()==1,"replicated board work"):return
  var old_peer: int=game.multiplayer.get_unique_id()
  game.session.leave()
  await create_timer(2.0).timeout
  if game.session.join_game("127.0.0.1","Student",26361)!=OK:push_error("Rejoin failed");quit(1);return
  owner.enabled=true
  if not await wait_for(func():
   game.player.global_position=point;game.session.send_pose({"position":point})
   return game.session.roster.size()==2 and game.multiplayer.get_unique_id()!=old_peer and board_paper(room).get("board_lines",[]).size()==1 and board_paper(room).get("board_notes",[]).size()==1
  ,"rejoined board snapshot"):return
  game.school.request({"op":"board_mark","id":paper.id,"from":Vector2(.4,.4),"point":Vector2(.6,.6),"erase":false})
  probe.rejoin_ack.rpc_id(1)
  if not await wait_for(func():return owner.presentation.active_id!=event_id and is_instance_valid(owner.presentation.panel) and owner.presentation.panel.title_label.text=="Group exercise","group view"):return
  var group_id: String=owner.presentation.active_id
  owner.service.request.rpc_id(1,room,class_id,group_id,"contribute","Convert resistance to ohms first")
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.vote_label.visible,"team proposal"):return
  owner.service.request.rpc_id(1,room,class_id,group_id,"vote",true)
  if not await wait_for(func():return statuses.any(func(item):return item[0]=="vote"),"team vote status"):return
  if statuses.back()!=["vote","accepted"]:push_error("Vote rejected: "+str(statuses.back()));quit(1);return
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.vote_label.text.contains("Agree 1"),"team vote"):return
  probe.vote_ack.rpc_id(1)
  if not await wait_for(func():return owner.presentation.active_id!=group_id and is_instance_valid(owner.presentation.panel) and owner.presentation.panel.title_label.text=="Predict the result","demonstration view"):return
  var demo_id: String=owner.presentation.active_id
  owner.presentation.panel.options.select(0)
  owner.presentation.panel._submit()
  if not await wait_for(func():return statuses.any(func(item):return item==["submit","accepted"]),"demo submission"):return
  if not await wait_for(func():return owner.presentation.panel!=null and owner.presentation.panel.status_label.text.contains("Teacher:"),"demo reveal"):return
  probe.reveal_ack.rpc_id(1)
  if not await wait_for(func():return owner.presentation.panel==null,"assignment removed event"):return
  game.school.request({"op":"board_mark","id":paper.id,"from":Vector2(.4,.4),"point":Vector2(.6,.6),"erase":false})
  owner.service.request.rpc_id(1,room,class_id,demo_id,"submit","0")
  owner.service.request.rpc_id(1,room,class_id,group_id,"vote",false)
  owner.service.request.rpc_id(1,room,class_id,event_id,"contribute","After assessment")
  if not await wait_for(func():return statuses.any(func(item):return item==["contribute","denied"]) and statuses.any(func(item):return item==["submit","denied"]) and statuses.any(func(item):return item==["vote","denied"]),"stale actions denied"):return
  probe.cleanup_ack.rpc_id(1)
  await create_timer(.5).timeout
  print("FULL_BOARD_CLIENT PASS")
 game.session.leave();await create_timer(.2).timeout
 game.queue_free();await process_frame;quit(0)
