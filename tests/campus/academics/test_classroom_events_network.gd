extends SceneTree
## Two lightweight ENet peers; the campus scene and live relay are not used.
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
class Session:
 var roster:={1:{}}
 var online:=true
 var api: MultiplayerAPI
 func peer_connected_now(peer: int) -> bool:return peer in api.get_peers()
class School:
 var identities:={1:"alice"}
 var random:=RandomNumberGenerator.new()
class Classes:
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":0.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false}}}}
 func _inside(_peer: int,_room: String) -> bool:return true
class Game:
 extends Node
 var session:=Session.new()
 var school:=School.new()
 var lecture_classes:=Classes.new()
var views:=[]
var statuses:=[]
func _initialize() -> void:call_deferred("run")
func wait_for(check: Callable,deadline: int) -> bool:
 while Time.get_ticks_msec()<deadline:
  if check.call():return true
  await create_timer(.05).timeout
 return false
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=1 or args[0] not in ["host","client"]:
  push_error("Usage: --script res://tests/campus/academics/test_classroom_events_network.gd -- host|client (run one of each concurrently)")
  quit(2);return
 var host:=args[0]=="host"
 var peer:=ENetMultiplayerPeer.new()
 var error:=peer.create_server(26349,1) if host else peer.create_client("127.0.0.1",26349)
 if error!=OK:push_error("Could not create peer");quit(1);return
 root.multiplayer.multiplayer_peer=peer
 var game:=Game.new();game.name="Game";root.add_child(game);game.session.api=root.multiplayer
 var service:=Service.new();service.name="ClassroomService";game.add_child(service);service.configure(game)
 service.view_received.connect(func(room,view):views.append({"room":room,"view":view}))
 service.action_status_received.connect(func(class_id,event_id,op,status):statuses.append([class_id,event_id,op,status]))
 var deadline:=Time.get_ticks_msec()+25000
 if host:print("CLASSROOM_RPC_HOST_READY")
 if not await wait_for(func():return not root.multiplayer.get_peers().is_empty(),deadline):push_error("Peer connection timed out");quit(1);return
 if host:
  var remote: int=root.multiplayer.get_peers()[0]
  game.session.roster[remote]={};game.school.identities[remote]="bob"
  game.lecture_classes.classes.room.students["bob"]={"peer":remote,"done":false}
  var now:=Time.get_ticks_msec()/1000.0
  game.lecture_classes.classes.room.deadline=now+150.0
  if not service.start("room",now):
   var probe=preload("res://scripts/campus/academics/classroom_events/practice_round.gd").new()
   var prepared: bool=probe.prepare(true,"probe","DGS266",3,0,42,now+30.0,["alice","bob"])
   push_error("Could not start practice: server=%s roster=%s identities=%s students=%s round=%s"%[str(service.multiplayer.is_server()),str(game.session.roster.keys()),str(game.school.identities.keys()),str(game.lecture_classes.classes.room.students.keys()),str(prepared)])
   quit(1);return
  if not await wait_for(func():return "bob" in service.rooms.room.hands.hands,deadline):push_error("Remote hand not raised");quit(1);return
  service.publish("room",Time.get_ticks_msec()/1000.0)
  if not await wait_for(func():return "bob" not in service.rooms.room.hands.hands,deadline):push_error("Remote hand not lowered");quit(1);return
  service.publish("room",Time.get_ticks_msec()/1000.0)
  if not await wait_for(func():return service.rooms.room.round.submissions.has("bob"),deadline):push_error("Remote answer not received");quit(1);return
  if service.rooms.room.round.submissions.has("alice"):push_error("Wrong participant marked");quit(1);return
  if not await wait_for(func():return remote not in root.multiplayer.get_peers(),deadline):push_error("Remote did not disconnect");quit(1);return
  game.session.roster.erase(remote);game.school.identities.erase(remote);service.sync_roster("room",Time.get_ticks_msec()/1000.0)
  if not await wait_for(func():return not root.multiplayer.get_peers().is_empty(),deadline):push_error("Remote did not reconnect");quit(1);return
  var returning: int=root.multiplayer.get_peers()[0]
  if returning==remote:push_error("Reconnect reused peer ID");quit(1);return
  game.session.roster[returning]={};game.school.identities[returning]="bob"
  service.sync_roster("room",Time.get_ticks_msec()/1000.0)
  if game.lecture_classes.classes.room.students["bob"].peer!=returning:push_error("Participant not rebound");quit(1);return
  service.publish("room",Time.get_ticks_msec()/1000.0)
  await create_timer(.5).timeout
  var finish_time:=Time.get_ticks_msec()/1000.0
  service.rooms.room.round.deadline=finish_time;service.tick(finish_time)
  await create_timer(.5).timeout
  game.lecture_classes.classes.room.phase="assignment";service.tick(Time.get_ticks_msec()/1000.0)
  await create_timer(1.0).timeout
  print("CLASSROOM_RPC_HOST PASS")
 else:
  if not await wait_for(func():return not views.is_empty(),deadline):push_error("No practice snapshot");quit(1);return
  var snapshot: Dictionary=views[-1].view
  if not snapshot.get("can_submit",false) or snapshot.question.has("answer"):push_error("Bad or private snapshot");quit(1);return
  service.request.rpc_id(1,"room",snapshot.class_id,snapshot.event_id,"hand",true)
  if not await wait_for(func():return statuses.any(func(item):return item[2]=="hand" and item[3]=="accepted"),deadline):push_error("Hand action rejected");quit(1);return
  if not await wait_for(func():return views.any(func(item):return root.multiplayer.get_unique_id() in item.view.get("raised_peers",[])),deadline):push_error("Raised hand not replicated");quit(1);return
  service.request.rpc_id(1,"room",snapshot.class_id,snapshot.event_id,"hand",false)
  if not await wait_for(func():return statuses.filter(func(item):return item[2]=="hand" and item[3]=="accepted").size()==2,deadline):push_error("Lower hand rejected");quit(1);return
  service.request.rpc_id(1,"room",snapshot.class_id,snapshot.event_id,"submit","0")
  if not await wait_for(func():return statuses.any(func(item):return item[2]=="submit"),deadline):push_error("No submission status");quit(1);return
  if statuses[-1][2]!="submit" or statuses[-1][3]!="accepted":push_error("Submission rejected");quit(1);return
  peer.close()
  await create_timer(.5).timeout
  peer=ENetMultiplayerPeer.new()
  if peer.create_client("127.0.0.1",26349)!=OK:push_error("Reconnect failed");quit(1);return
  root.multiplayer.multiplayer_peer=peer;views.clear()
  if not await wait_for(func():return views.any(func(item):return item.view.get("submitted",false)),deadline):push_error("Submitted state not restored");quit(1);return
  if views[-1].view.get("can_submit",true):push_error("Duplicate submission allowed after rejoin");quit(1);return
  if not await wait_for(func():return views.any(func(item):return item.view.has("result")),deadline):push_error("No private feedback");quit(1);return
  if str(views[-1].view).contains("alice"):push_error("Another student identity was exposed");quit(1);return
  if not await wait_for(func():return views.any(func(item):return item.view.is_empty()),deadline):push_error("Assignment did not clear UI");quit(1);return
  print("CLASSROOM_RPC_CLIENT PASS")
 game.queue_free();peer.close();await process_frame;quit(0)
