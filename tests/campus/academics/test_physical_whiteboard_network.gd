extends SceneTree
## Host, selected writer, and observer exercise school and classroom RPCs.
const School=preload("res://scripts/school_session.gd")
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
class Session:
	var roster:={1:{}}
	var online:=true
	var poses:={}
	var api: MultiplayerAPI
	func peer_connected_now(peer: int) -> bool:return peer in api.get_peers()
class Classes:
	extends RefCounted
	var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":0.0,"course":"ETY155","week":1,"difficulty":0,"students":{"alice":{"peer":1,"done":false}}}}
	var classroom_events: Node
	func _inside(_peer: int,_room: String) -> bool:return true
class Events:
	extends Node
	var enabled:=true
	var service: Node
	var acks:=0
	var observer_acks:=0
	@rpc("any_peer","call_remote","reliable")
	func assessment_ack() -> void:acks+=1
	@rpc("any_peer","call_remote","reliable")
	func observer_ack() -> void:observer_acks+=1
class Game:
	extends Node
	var session:=Session.new()
	var front:={"in_game":false}
	var school: Node
	var lecture_classes:=Classes.new()
	var player:=Node3D.new()
var views: Array=[]
var statuses: Array=[]
func _initialize() -> void:call_deferred("run")
func wait_for(check: Callable,deadline: int) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.05).timeout
	return false
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or args[0] not in ["host","client","observer"]:fail("Use host, client, or observer role");return
	var host: bool=args[0]=="host"
	var peer:=ENetMultiplayerPeer.new()
	var error:=peer.create_server(26351,3) if host else peer.create_client("127.0.0.1",26351)
	if error!=OK:fail("Could not create ENet peer");return
	root.multiplayer.multiplayer_peer=peer
	var game:=Game.new();game.name="Game";root.add_child(game);game.add_child(game.player);game.session.api=root.multiplayer
	var school:=School.new();school.name="School";game.add_child(school);school.game=game;game.school=school
	school.project={"title":"Lesson","questions":[]};school.identities={1:"alice"}
	var events:=Events.new();events.name="Events";game.add_child(events);game.lecture_classes.classroom_events=events
	var service:=Service.new();service.name="Service";events.add_child(service);service.configure(game);events.service=service
	service.view_received.connect(func(_room: String,view: Dictionary):views.append(view))
	service.action_status_received.connect(func(_class_id: String,_event_id: String,op: String,status: String):statuses.append([op,status]))
	var deadline:=Time.get_ticks_msec()+30000
	if host:print("PHYSICAL_BOARD_HOST_READY")
	if not await wait_for(func():return not root.multiplayer.get_peers().is_empty(),deadline):fail("Initial connection timed out");return
	if args[0]=="client":print("PHYSICAL_BOARD_CLIENT_READY")
	if host:
		var remote: int=root.multiplayer.get_peers()[0]
		if not await wait_for(func():return root.multiplayer.get_peers().size()>=2,deadline):fail("Observer connection timed out");return
		var observer:=0
		for id in root.multiplayer.get_peers():
			if id!=remote:observer=id
		if observer==0:fail("Observer peer ID missing");return
		game.session.roster[remote]={};game.session.poses[remote]={"position":Vector3.ZERO}
		school.identities[remote]="bob"
		game.session.roster[observer]={};game.session.poses[observer]={"position":Vector3.ZERO};school.identities[observer]="observer"
		game.lecture_classes.classes.room.students["bob"]={"peer":remote,"done":false}
		school.papers[1]={"id":1,"owner":remote,"held":true,"supply_id":"marker","project":{"title":"Marker","questions":[]},"lesson":false,"mark":{},"answers":{},"strokes":{},"annotations":{},"revision":0}
		school.papers[2]={"id":2,"owner":0,"held":false,"supply_id":"whiteboard","classroom_board":"room","position":Vector3(0,1,0),"wall_normal":Vector3.BACK,"board_lines":[],"board_notes":[],"revision":0,"project":{"title":"Board","questions":[]},"mark":{},"lesson":false}
		var now:=Time.get_ticks_msec()/1000.0
		game.lecture_classes.classes.room.deadline=now+150.0
		if not service.start("room",now,[],"board"):fail("Board round did not start");return
		var event_id: String=service.rooms.room.round.event_id
		if not service.rooms.room.hands.call_student(true,event_id,"bob"):fail("Bob not selected");return
		school.broadcast();service.publish("room",now)
		if not await wait_for(func():return school.papers[2].board_lines.size()==1 and school.papers[2].board_notes.size()==1,deadline):fail("Remote board work missing");return
		if not await wait_for(func():return events.observer_acks>=1,deadline):fail("Observer did not receive strokes and note");return
		if not await wait_for(func():return remote not in root.multiplayer.get_peers(),deadline):fail("Remote did not disconnect");return
		game.session.roster.erase(remote);game.session.poses.erase(remote);school.identities.erase(remote);service.sync_roster("room",Time.get_ticks_msec()/1000.0)
		if service.can_mark_board(remote,"room",Time.get_ticks_msec()/1000.0):fail("Departed peer retained board access");return
		if not await wait_for(func():return root.multiplayer.get_peers().size()>=2,deadline):fail("Remote did not reconnect");return
		var returning:=0
		for id in root.multiplayer.get_peers():
			if id!=observer:returning=id
		if returning==0:fail("Returning peer ID missing");return
		if returning==remote:fail("Reconnect reused peer ID");return
		game.session.roster[returning]={};game.session.poses[returning]={"position":Vector3.ZERO};school.identities[returning]="bob"
		school.papers[1].owner=returning
		service.sync_roster("room",Time.get_ticks_msec()/1000.0)
		if service.can_mark_board(returning,"room",Time.get_ticks_msec()/1000.0):fail("Rejoin bypassed teacher selection");return
		school.broadcast();service.publish("room",Time.get_ticks_msec()/1000.0)
		if not await wait_for(func():return service.request_budget.has(returning),deadline):fail("Rejoined unauthorized request missing");return
		if school.papers[2].board_lines.size()!=1:fail("Unselected rejoin changed board");return
		game.lecture_classes.classes.room.phase="assignment";service.tick(Time.get_ticks_msec()/1000.0)
		var assessment_board: Array=school.papers[2].board_lines.duplicate(true)
		if service.can_mark_board(returning,"room",Time.get_ticks_msec()/1000.0):fail("Assessment phase retained board access");return
		if not await wait_for(func():return events.acks>=1,deadline):fail("Assessment-phase request missing");return
		if school.papers[2].board_lines!=assessment_board:fail("Assessment phase accepted board mark");return
		print("PHYSICAL_BOARD_HOST PASS")
	elif args[0]=="observer":
		if not await wait_for(func():return school.papers.has(2) and school.papers[2].board_lines.size()==1 and school.papers[2].board_notes.size()==1,deadline):fail("Observer did not receive whiteboard state");return
		if not await wait_for(func():return views.any(func(item):return item.has("shared") and item.get("hands",{}).get("selected",false)==false),deadline):fail("Observer event view missing");return
		events.observer_ack.rpc_id(1)
		if not await wait_for(func():return views.any(func(item):return item.is_empty()),deadline):fail("Observer did not see assessment cancellation");return
		print("PHYSICAL_BOARD_OBSERVER PASS")
	else:
		if not await wait_for(func():return views.any(func(view):return view.get("hands",{}).get("selected",false)),deadline):fail("Selected board view missing");return
		var view: Dictionary=views[-1]
		school.request({"op":"board_mark","id":2,"from":Vector2(.2,.2),"point":Vector2(.4,.4),"erase":false})
		service.request.rpc_id(1,"room",view.class_id,view.event_id,"contribute","I = V / R")
		if not await wait_for(func():return school.papers.has(2) and school.papers[2].board_lines.size()==1 and school.papers[2].board_notes.size()==1,deadline):fail("Observer board snapshot missing");return
		peer.close();await create_timer(.5).timeout
		views.clear();school.papers.clear()
		peer=ENetMultiplayerPeer.new()
		if peer.create_client("127.0.0.1",26351)!=OK:fail("Reconnect failed");return
		root.multiplayer.multiplayer_peer=peer
		if not await wait_for(func():return school.papers.has(2) and school.papers[2].board_lines.size()==1 and school.papers[2].board_notes.size()==1,deadline):fail("Late board snapshot missing");return
		if not await wait_for(func():return views.any(func(item):return item.has("hands")),deadline):fail("Rejoined event view missing");return
		view=views[-1]
		school.request({"op":"board_mark","id":2,"from":Vector2(.4,.4),"point":Vector2(.6,.6),"erase":false})
		service.request.rpc_id(1,"room",view.class_id,view.event_id,"contribute","Unselected")
		if not await wait_for(func():return statuses.any(func(item):return item==["contribute","not_selected"]),deadline):fail("Unselected text request was not denied");return
		if not await wait_for(func():return views.any(func(item):return item.is_empty()),deadline):fail("Assessment cancellation not received");return
		school.request({"op":"board_mark","id":2,"from":Vector2(.4,.4),"point":Vector2(.6,.6),"erase":false})
		service.request.rpc_id(1,"room",view.class_id,view.event_id,"contribute","After assessment")
		if not await wait_for(func():return statuses.any(func(item):return item==["contribute","denied"]),deadline):fail("Assessment text request was not denied");return
		events.assessment_ack.rpc_id(1)
		await create_timer(.5).timeout
		print("PHYSICAL_BOARD_CLIENT PASS")
	game.queue_free();peer.close();await process_frame;quit(0)
