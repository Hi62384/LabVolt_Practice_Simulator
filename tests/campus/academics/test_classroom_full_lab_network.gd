extends SceneTree
## Full Main AC lab demonstration; the prediction follows a real supply action.
const Controller=preload("res://scripts/campus/academics/classroom_events/controller.gd")
const Catalog=preload("res://scripts/equipment_catalog.gd")
class Probe:
 extends Node
 var result_acks:=0
 var cleanup_acks:=0
 @rpc("any_peer","call_remote","reliable")
 func result_ack() -> void:result_acks+=1
 @rpc("any_peer","call_remote","reliable")
 func cleanup_ack() -> void:cleanup_acks+=1
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
 print("FULL LAB STATE ",label," roster=",game.session.roster.keys()," rooms=",owner.service.rooms.keys()," statuses=",statuses)
 push_error("FULL LAB TIMEOUT "+label);quit(1);return false
func prepare_station(lab: RefCounted,plan: Dictionary) -> bool:
 lab.cables.clear();lab.powered=false
 for kind in ["R","L","C"]:lab.switches[kind]=[false,false,false,false,false,false,false,false,false]
 lab.level=plan.variable_level;lab.frequency=plan.frequency_hz
 var nodes: Dictionary=plan.source_nodes.duplicate();var serial:=1
 for bank in plan.banks:
  var id: String=str(bank.kind)+str(bank.index)
  var switch_index: int=Catalog.LOADS[bank.kind].values.find(bank.value)
  if switch_index<0:return false
  lab.switches[bank.kind][int(bank.index)*3+switch_index]=true
  for pair in [[bank.a,id+"_P"],[bank.b,id+"_N"]]:
   if not nodes.has(pair[0]):nodes[pair[0]]=pair[1]
   else:lab.cables.append({"id":serial,"a":nodes[pair[0]],"b":pair[1],"owner":0,"color":0});serial+=1
 for lead in lab.cables:
  if lead.b=="R0_P":lead.b="AM0_IN";break
 for pair in [["AM0_OUT","R0_P"],["V0_COM","R0_N"],["V0_150","R0_P"]]:
  lab.cables.append({"id":serial,"a":pair[0],"b":pair[1],"owner":0,"color":0});serial+=1
 lab.powered=true;lab.recalculate()
 return lab.powered and str(lab.readings.get("fault",""))=="" and lab.readings.get("voltmeters",[]).any(func(value):return float(value)>.01)
func run() -> void:
 var args:=OS.get_cmdline_user_args()
 if args.size()!=1 or args[0] not in ["host","client"]:quit(1);return
 var host: bool=args[0]=="host"
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 owner=Controller.new();owner.name="ClassroomEventsTest";game.lecture_classes.add_child(owner)
 owner.configure(game);owner.enabled=true;game.lecture_classes.classroom_events=owner
 probe=Probe.new();probe.name="LabProbe";game.add_child(probe)
 owner.service.action_status_received.connect(func(_c: String,_e: String,op: String,status: String):statuses.append([op,status]))
 deadline=Time.get_ticks_msec()+80000
 var room:="ac_lab"
 var classes=game.lecture_classes
 var desk: Vector3=classes.signs[room].desk
 if host:
  if game.session.host_game("Host",26363)!=OK:quit(1);return
  owner.enabled=true;game.player.global_position=desk
  game.faculty.current.ac_lab="mr_phillips"
  if not await wait_for(func():return game.school.identities.has(1),"host identity"):return
  var error: String=classes._start(room,{"course_id":"ELM253","week":2,"kind":"lab","difficulty":1})
  if not error.is_empty():push_error(error);quit(1);return
  var activity: Dictionary=classes.classes[room]
  activity.phase="lesson";activity.deadline=Time.get_ticks_msec()/1000.0+180.0
  owner.attempted[str(activity.id)]={"count":3,"tries":0,"next":INF,"recent":[],"recent_modes":[]}
  classes._publish()
  print("FULL_LAB_HOST_READY")
  if not await wait_for(func():return activity.students.size()==1,"student enrollment"):return
  var student: Dictionary=activity.students.values()[0]
  var peer: int=int(student.peer)
  var bench: int=int(student.bench)
  if bench!=0 or not game.school.equipment_access(peer,bench,"ELM253"):push_error("Student has no station ownership");quit(1);return
  var lab: RefCounted=game.session.labs[bench]
  if not prepare_station(lab,student.project.physical_ac_plan):push_error("Live AC station setup failed");quit(1);return
  game.session.broadcast()
  var now:=Time.get_ticks_msec()/1000.0
  if not owner.service.start(room,now,[],"physical"):push_error("Physical round did not start");quit(1);return
  var state: Dictionary=owner.service.rooms[room]
  var first: float=state.round.first_voltage
  var initial_revision: int=int(lab.revision)
  if not await wait_for(func():return int(lab.revision)>initial_revision and float(lab.readings.voltmeters[state.round.channel])>first+.05,"student supply change"):return
  print("FULL_LAB_HOST_CHANGE voltage=",first," -> ",lab.readings.voltmeters[state.round.channel]," level=",lab.level)
  owner.service.tick(Time.get_ticks_msec()/1000.0)
  if not state.round.measurement_valid:push_error("Round ignored live station change");quit(1);return
  if not await wait_for(func():return state.round.submissions.size()==1,"student prediction"):return
  if owner.service.view(peer,room,Time.get_ticks_msec()/1000.0).has("reveal"):push_error("Physical result leaked early");quit(1);return
  owner.service.tick(now+30.0);owner.service.publish(room,now+30.0)
  var reveal: Dictionary=owner.service.view(peer,room,now+30.0).get("reveal",{})
  if reveal.get("answer","")!="Increase" or float(reveal.get("after_v",0))<=first:push_error("Wrong live result: "+str(reveal));quit(1);return
  if not await wait_for(func():return probe.result_acks>=1,"client saw result"):return
  if not classes._begin_assignment(room,activity):push_error("Assessment failed");quit(1);return
  owner.step(Time.get_ticks_msec()/1000.0)
  if owner.service.rooms.has(room) or not owner.service.lifecycle.reservations.is_empty():push_error("Physical event survived assessment");quit(1);return
  if not await wait_for(func():return probe.cleanup_acks>=1,"client cleanup"):return
  print("FULL_LAB_HOST PASS")
 else:
  if game.session.join_game("127.0.0.1","Student",26363)!=OK:quit(1);return
  owner.enabled=true
  if not await wait_for(func():
   game.player.global_position=desk;game.session.send_pose({"position":desk})
   var own: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
   return game.session.roster.size()==2 and classes.public_classes.has(room) and own.get("position",Vector3.INF).distance_to(desk)<.6
  ,"lab visible"):return
  await create_timer(.5).timeout
  classes._send("sign",room,{})
  if not await wait_for(func():return classes.public_classes.get(room,{}).get("signed",false),"attendance"):return
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.title_label.text=="Live AC station observation" and owner.presentation.panel.status_label.text.to_lower().contains("station"),"physical prediction view"):return
  var class_id: String=owner.presentation.active_class
  var id: String=owner.presentation.active_id
  var bench:=0
  var control: Vector3=game.session.labs[bench].positions.get("variable",Vector3.INF)
  if not control.is_finite():push_error("Supply dial missing");quit(1);return
  if not await wait_for(func():
   game.player.global_position=control;game.session.send_pose({"position":control})
   return game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(control)<.6
  ,"supply proximity"):return
  game.session.message_received.connect(func(message):print("FULL_LAB_ACTION_MESSAGE ",message))
  await create_timer(.5).timeout
  print("FULL_LAB_CLIENT_DIAL control=",control)
  game.session.request({"op":"voltage","station":bench,"delta":.05})
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.status_label.text.contains("Station changed"),"measured change view"):return
  owner.presentation.panel.options.select(0)
  owner.presentation.panel._submit()
  if not await wait_for(func():return statuses.any(func(item):return item==["submit","accepted"]),"prediction accepted"):return
  if not await wait_for(func():return is_instance_valid(owner.presentation.panel) and owner.presentation.panel.status_label.text.contains("RMS after the change"),"result view"):return
  probe.result_ack.rpc_id(1)
  if not await wait_for(func():return owner.presentation.panel==null,"assessment cleanup"):return
  owner.service.request.rpc_id(1,room,class_id,id,"submit","0")
  if not await wait_for(func():return statuses.any(func(item):return item==["submit","denied"]),"stale prediction denied"):return
  probe.cleanup_ack.rpc_id(1)
  await create_timer(.5).timeout
  print("FULL_LAB_CLIENT PASS")
 game.session.leave();await create_timer(.2).timeout
 game.queue_free();await process_frame;quit(0)
