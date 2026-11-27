extends SceneTree
## Real ENet peers, owned phone UI and issued work; no fake player controller.
const ROOM:="ety155_lecture"
const PORT:=26365

class Coordination extends Node:
	var step: Dictionary={}
	var acknowledgement:=""
	var sender:=0
	@rpc("authority","call_remote","reliable")
	func prepare(value: Dictionary) -> void:step=value
	@rpc("any_peer","call_remote","reliable")
	func acknowledge(value: String) -> void:
		if multiplayer.is_server():
			acknowledgement=value
			sender=multiplayer.get_remote_sender_id()

var game: Node
var coordination: Coordination
var deadline:=0

func _initialize() -> void:call_deferred("run")

func fail(message: String) -> void:
	push_error("HUMAN DISCIPLINE NETWORK: "+message)
	quit(1)

func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if not game.multiplayer.is_server():game.session.send_pose({"position":game.player.global_position})
		if condition.call():return true
		await create_timer(.05).timeout
	fail("Timed out waiting for "+label)
	return false

func acknowledged(peer: int,stage: String) -> bool:
	return coordination.sender==peer and coordination.acknowledgement==stage

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or args[0] not in ["host","client"]:fail("Expected host or client");return
	var host:=args[0]=="host"
	coordination=Coordination.new();coordination.name="DisciplineTestCoordination";root.add_child(coordination)
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	game.faculty.set_process(false)
	game.smartphones.set_process(false)
	game.client_preferences.values.teacher_speech=false
	game.client_preferences.values.teacher_automatic_conversation=false
	var classes: Node=game.lecture_classes
	classes.set_process(false)
	var profile: RefCounted=game.electronics.profile
	profile.open("human-discipline-network-"+args[0])
	game.school.local_identity=profile.data.dorm.owner
	profile.data.dollars=10000
	var phone_id:=""
	if not host:
		profile.buy_smartphone("basic")
		if not profile.operation_succeeded:fail("Owned phone fixture failed");return
		phone_id=str(profile.data.dorm.smartphones.keys()[0])
	game.player.global_position=classes.signs[ROOM].desk
	deadline=Time.get_ticks_msec()+55000
	if host:
		if game.session.host_game("Discipline host",PORT)!=OK:fail("Host failed");return
		print("HUMAN_DISCIPLINE_HOST_READY")
		if not await until(func():return game.session.roster.size()==2 and game.school.identities.size()==2,"authenticated peer"):return
		var peer: int=game.session.roster.keys().filter(func(value):return value!=1)[0]
		var identity:=str(game.school.identities[peer])
		if not await until(func():return classes._inside(peer,ROOM),"peer in classroom"):return
		if classes._start(ROOM,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0,"teacher_override":"mr_stone"})!="":fail("Actual lecture did not start");return
		var activity: Dictionary=classes.classes[ROOM]
		classes._publish()
		if not await until(func():return activity.students.has(identity),"remote attendance"):return
		if not classes._begin_assignment(ROOM,activity):fail("Actual assignment did not start");return
		var paper_id:=int(activity.students[identity].paper)
		if paper_id<=0:fail("Remote assignment was not issued");return
		game.school.papers[paper_id].answers["0"]="unfinished remote working"
		game.school.broadcast();classes._publish()
		var answers: Dictionary=game.school.papers[paper_id].answers.duplicate(true)
		var archive: Dictionary=game.school.archive.duplicate(true)
		coordination.prepare.rpc_id(peer,{"name":"open_phone","class_id":str(activity.id),"paper":paper_id})
		if not await until(func():return acknowledged(peer,"phone_open"),"owned phone UI open"):return
		game.faculty._discipline_instruction.rpc_id(peer,ROOM,"stale-class",str(activity.teacher),"put_away",Vector3.INF)
		coordination.prepare.rpc_id(peer,{"name":"stale_instruction"})
		if not await until(func():return acknowledged(peer,"stale_refused"),"stale instruction refused"):return
		var put_away: Dictionary=game.faculty._apply_human_discipline(peer,ROOM,activity,str(activity.teacher),{"action":"put_away"})
		if put_away.get("executed",true) or not put_away.get("pending",false):fail("Remote put-away was incorrectly declared completed");return
		if not await until(func():return acknowledged(peer,"phone_closed"),"actual remote phone UI closure"):return
		var previous: Vector3=classes._position(peer)
		var target: Vector3=game.faculty._discipline_destination(peer,ROOM,activity,false)
		if not target.is_finite() or not game.campus.registry.room_contains(ROOM,target) or target.distance_to(previous)<1.5:
			fail("Host did not select a clear distinct classroom destination");return
		var moved: Dictionary=game.faculty._apply_human_discipline(peer,ROOM,activity,str(activity.teacher),{"action":"move"})
		if moved.get("executed",true) or not moved.get("pending",false):fail("Remote movement was incorrectly declared completed");return
		coordination.prepare.rpc_id(peer,{"name":"move","target":target})
		if not await until(func():return acknowledged(peer,"moved") and classes._position(peer).distance_to(target)<.05,"actual client relocation and returned pose"):return
		var removed: Dictionary=game.faculty._apply_human_discipline(peer,ROOM,activity,str(activity.teacher),{"action":"remove"})
		if removed.get("executed",true) or removed.get("pending",false):fail("Host allowed removal during assessment");return
		# A matching, authoritative packet must still respect the client's
		# assignment-phase guard even if a faulty host caller sends it directly.
		game.faculty._discipline_instruction.rpc_id(peer,ROOM,str(activity.id),str(activity.teacher),"remove",previous)
		coordination.prepare.rpc_id(peer,{"name":"assignment_remove","target":target})
		if not await until(func():return acknowledged(peer,"assignment_remove_refused"),"client assignment removal refusal"):return
		if moved.get("executed",true) or put_away.get("executed",true):fail("Remote pending executions silently became confirmed");return
		if game.school.papers[paper_id].answers!=answers or game.school.archive!=archive or activity.students[identity].done:
			fail("Remote discipline changed work or marks");return
		coordination.prepare.rpc_id(peer,{"name":"complete"})
		if not await until(func():return game.session.roster.size()==1,"peer checks completed"):return
		print("HUMAN_DISCIPLINE_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Discipline student",PORT)!=OK:fail("Join failed");return
		if not await until(func():return classes.public_classes.has(ROOM) and game.electronics_trade.authority.bound,"class and inventory authority"):return
		classes._send("sign",ROOM,{})
		if not await until(func():return coordination.step.get("name","")=="open_phone" and classes.public_classes.get(ROOM,{}).get("phase","")=="assignment","issued assignment"):return
		var paper_id:=int(coordination.step.paper)
		if not await until(func():return game.school.papers.get(paper_id,{}).get("answers",{}).get("0","")=="unfinished remote working","remote work snapshot"):return
		game.smartphones._toggle_power(phone_id,false)
		game.smartphones._open_phone(phone_id)
		if not game.smartphones.is_ui_open():fail("Owned phone did not open");return
		coordination.acknowledge.rpc_id(1,"phone_open")
		if not await until(func():return coordination.step.get("name","")=="stale_instruction","stale packet delivered"):return
		if not game.smartphones.is_ui_open():fail("Stale class instruction closed phone");return
		coordination.acknowledge.rpc_id(1,"stale_refused")
		if not await until(func():return not game.smartphones.is_ui_open(),"valid put-away instruction"):return
		coordination.acknowledge.rpc_id(1,"phone_closed")
		if not await until(func():return coordination.step.get("name","")=="move","move packet delivered"):return
		var target: Vector3=coordination.step.target
		if not await until(func():return game.player.global_position.distance_to(target)<.05,"actual player body movement"):return
		if not game.campus.registry.room_contains(ROOM,game.player.global_position):fail("Assessment movement left classroom");return
		coordination.acknowledge.rpc_id(1,"moved")
		if not await until(func():return coordination.step.get("name","")=="assignment_remove","removal packet delivered"):return
		if game.player.global_position.distance_to(target)>.05:fail("Authoritative removal displaced player during assessment");return
		if game.school.papers.get(paper_id,{}).get("answers",{}).get("0","")!="unfinished remote working":fail("Remote work changed");return
		coordination.acknowledge.rpc_id(1,"assignment_remove_refused")
		if not await until(func():return coordination.step.get("name","")=="complete","host verified pending state and work"):return
		print("HUMAN_DISCIPLINE_CLIENT PASS")
		game.session.leave();await create_timer(.3).timeout
	game.session.leave();game.queue_free();coordination.queue_free()
	await process_frame
	quit(0)
