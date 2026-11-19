extends SceneTree

const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
const ROOM := "ety155_lecture"
var game: Node
var deadline: int

func _initialize() -> void: call_deferred("run")
func until(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.05).timeout
	push_error("EVENT REJOIN TIMEOUT "+label);quit(1);return false

func run() -> void:
	var host: bool=OS.get_cmdline_user_args()[0]=="host"
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	deadline=Time.get_ticks_msec()+110000
	var classes=game.lecture_classes
	var school=game.school
	var desk: Vector3=classes.signs[ROOM].desk
	var service:=Service.new();service.name="EventRejoinService";classes.add_child(service);service.configure(game)
	if host:
		if game.session.host_game("Host",26310)!=OK:quit(1);return
		print("PAPER_REJOIN_HOST_READY")
		if not await until(func():return game.session.roster.size()==2 and school.identities.size()==2,"identity"):return
		var old_peer: int=game.session.roster.keys().filter(func(id):return id!=1)[0]
		var identity: String=str(school.identities[old_peer])
		if not await until(func():return classes._position(old_peer).distance_to(desk)<.6,"desk"):return
		assert(classes._start(ROOM,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})=="")
		var activity: Dictionary=classes.classes[ROOM]
		activity.phase="lesson";activity.deadline=classes._now()+180.0;classes._publish()
		if not await until(func():return activity.students.has(identity),"attendance"):return
		print("EVENT_REJOIN_HOST_ATTENDANCE")
		assert(service.start(ROOM,classes._now(),[],"practice"))
		print("EVENT_REJOIN_HOST_STARTED")
		var id: String=service.rooms[ROOM].round.event_id
		if not await until(func():return not game.session.roster.has(old_peer),"disconnect"):return
		print("EVENT_REJOIN_HOST_DISCONNECTED")
		service.sync_roster(ROOM,classes._now())
		assert(service.lifecycle.states[id].phase=="interrupted")
		assert(service.perform(old_peer,ROOM,activity.id,id,"hand",true,classes._now())=="denied")
		if not await until(func():return game.session.roster.size()==2,"reconnect"):return
		print("EVENT_REJOIN_HOST_RECONNECTED")
		var new_peer: int=game.session.roster.keys().filter(func(peer):return peer!=1)[0]
		if not await until(func():return str(school.identities.get(new_peer,""))==identity and classes._position(new_peer).distance_to(desk)<.6,"identity and pose restored"):return
		print("EVENT_REJOIN_HOST_RESTORED")
		service.sync_roster(ROOM,classes._now())
		assert(new_peer!=old_peer and activity.students[identity].peer==new_peer)
		assert(service.lifecycle.states[id].phase=="active")
		assert(service.perform(old_peer,ROOM,activity.id,id,"hand",true,classes._now())=="denied")
		assert(service.perform(new_peer,ROOM,activity.id,id,"hand",true,classes._now())=="accepted")
		service.publish(ROOM,classes._now())
		await create_timer(.5).timeout
		assert(classes._begin_assignment(ROOM,activity))
		service.tick(classes._now())
		assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
		var student: Dictionary=activity.students[identity]
		assert(student.paper>0)
		var paper_id: int=student.paper
		school.papers[paper_id].answers["0"]="saved before reconnect"
		school.broadcast()
		classes._publish()
		print("PAPER_ISSUED ",paper_id)
		if not await until(func():return not game.session.roster.has(new_peer),"second disconnect"):return
		var records: Array=school.archive[identity].values().filter(func(record):return record.get("assessment_id","")==activity.id)
		assert(not student.done and records.size()==1 and not records[0].has("score"))
		if not await until(func():
			var returning: Variant=school.identities.find_key(identity)
			return returning!=null and int(returning)!=new_peer and school.papers[paper_id].owner==returning
		,"paper owner rebind"):return
		assert(school.papers[paper_id].answers["0"]=="saved before reconnect")
		await create_timer(1).timeout
		print("PAPER_REJOIN_HOST PASS")
		await create_timer(2).timeout
	else:
		var current_event:=[{}]
		service.view_received.connect(func(_room: String,snapshot: Dictionary):
			current_event[0]=snapshot)
		if game.session.join_game("127.0.0.1","Student",26310)!=OK:quit(1);return
		if not await until(func():
			game.player.global_position=desk;game.session.send_pose({"position":desk})
			return classes.public_classes.get(ROOM,{}).get("phase","")=="lesson"
		,"lesson"):return
		classes._send("sign",ROOM,{})
		if not await until(func():return classes.public_classes.get(ROOM,{}).get("signed",false),"signed"):return
		if not await until(func():return not current_event[0].is_empty(),"event view"):return
		var event_id: String=current_event[0].event_id
		var old_peer: int=game.multiplayer.get_unique_id()
		game.session.leave()
		current_event[0]={}
		await create_timer(.8).timeout
		if game.session.join_game("127.0.0.1","Student",26310)!=OK:quit(1);return
		if not await until(func():
			game.player.global_position=desk;game.session.send_pose({"position":desk})
			return (game.session.roster.size()==2 and game.multiplayer.get_unique_id()!=old_peer
				and current_event[0].get("event_id","")==event_id)
		,"same event view on the new peer"):return
		var papers:=func()->Array:
			return school.papers.values().filter(func(p):return p.get("owner",0)==game.multiplayer.get_unique_id() and p.get("answers",{}).get("0","")=="saved before reconnect")
		if not await until(func():return not papers.call().is_empty(),"issued paper with answer"):return
		var paper_id: int=papers.call()[0].id
		var known_peer: int=game.multiplayer.get_unique_id()
		game.session.leave()
		await create_timer(.8).timeout
		if game.session.join_game("127.0.0.1","Student",26310)!=OK:quit(1);return
		if not await until(func():
			var paper: Dictionary=school.papers.get(paper_id,{})
			return game.multiplayer.get_unique_id()!=known_peer and paper.get("owner",0)==game.multiplayer.get_unique_id() and paper.get("answers",{}).get("0","")=="saved before reconnect"
		,"same paper and answer after second reconnect"):return
		print("PAPER_REJOIN_CLIENT PASS")
		await create_timer(4).timeout
	game.session.leave();await create_timer(.2).timeout
	game.queue_free();await process_frame;quit(0)
