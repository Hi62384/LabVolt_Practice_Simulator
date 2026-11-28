extends SceneTree
## Real Session and population RPCs in separate ENet processes. The last event
## is created in the same frame that a deliberate departure is requested.
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Sync=preload("res://scripts/campus/academics/student_population_sync.gd")
const Session=preload("res://scripts/session.gd")
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
var role:=""
var mode:=""
var fixture: Node
var service: Node
var failures: Array[String]=[]
var stage:=0
var deadline:=0
var remote_id:=""
var remote_identity:=""
var started_leave:=false

class School extends Node:
	var local_identity:=""
	var identities: Dictionary={}
class Faculty extends Node:
	var brain:=Memory.new()
class Students extends Node:
	var population:=Population.new()
class Classes extends Node:
	var classroom_students:=Students.new()
	var classes: Dictionary={}
class NoReceiptSync extends Sync:
	@rpc("authority","call_remote","reliable")
	func _departure_checkpoint(_nonce: String,_player: String) -> void:
		pass
class Game extends Node:
	var school:=School.new()
	var session:=Session.new()
	var faculty:=Faculty.new()
	var lecture_classes:=Classes.new()
	func _init() -> void:
		session.name="Session"
		add_child(school);add_child(session);add_child(faculty);add_child(lecture_classes)
		lecture_classes.add_child(lecture_classes.classroom_students)
	@rpc("any_peer","call_remote","reliable")
	func identify(identity: String) -> void:
		if multiplayer.is_server() and identity.length()==48:school.identities[multiplayer.get_remote_sender_id()]=identity
	@rpc("any_peer","call_remote","reliable")
	func baseline_saved() -> void:
		if multiplayer.is_server():set_meta("baseline_saved",true)
	@rpc("authority","call_remote","reliable")
	func leave_client() -> void:
		set_meta("leave_client",true)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	role=OS.get_environment("LABVOLT_POP_ROLE")
	mode=OS.get_environment("LABVOLT_DEPARTURE_MODE")
	var identity:=OS.get_environment("LABVOLT_POP_ID")
	fixture=Game.new();fixture.name="DepartureFixture";root.add_child(fixture)
	fixture.school.local_identity=identity
	var population: RefCounted=fixture.lecture_classes.classroom_students.population
	population.set_host_profile(identity);population.load_population();Legacy.seed(population,12);population.save_population()
	fixture.faculty.brain.set_host_profile(identity);fixture.faculty.brain.load_memory()
	var port:=int(OS.get_environment("LABVOLT_POP_PORT"))
	var error: Error=fixture.session.host_game("Host",port) if role=="server" else fixture.session.join_game("127.0.0.1","Guest",port)
	if error!=OK:failures.append("Could not start ENet fixture");_finish();return
	if role=="server":fixture.school.identities[1]=identity
	else:root.multiplayer.connected_to_server.connect(func():fixture.identify.rpc_id(1,identity))
	service=NoReceiptSync.new() if role=="client" and mode=="timeout" else Sync.new()
	service.name="StudentPopulationSync";fixture.add_child(service);service.configure(fixture)
	fixture.session.leaving.connect(func():fixture.set_meta("leave_count",int(fixture.get_meta("leave_count",0))+1))
	deadline=Time.get_ticks_msec()+15000
	process_frame.connect(_step)

func _has_event(memory: RefCounted,id: String,identity: String,event: String) -> bool:
	return memory.relationship(id,identity).get("episodes",[]).any(func(episode):return episode.get("event_id")==event)

func _step() -> void:
	if Time.get_ticks_msec()>deadline:failures.append("Timed out at stage %d: %s identities=%s roster=%s"%[stage,JSON.stringify(service.diagnostics()),JSON.stringify(fixture.school.identities),JSON.stringify(fixture.session.roster)]);_finish();return
	if started_leave:return
	if not fixture.session.online:
		if role=="client" and stage>=1:
			if mode!="timeout" and not _verify_disk():failures.append("Final event absent from recipient disk after host close")
			_finish()
		return
	if not service._bind():return
	if role=="client":
		if stage==0 and _has_event(service.brain,"campus_student_00",fixture.school.local_identity,"departure-baseline"):
			stage=1;fixture.baseline_saved.rpc_id(1)
			if mode=="paused":paused=true
		if mode=="client" and fixture.get_meta("leave_client",false):
			started_leave=true;_leave_client.call_deferred()
		return
	if stage==0 and fixture.school.identities.size()>1:
		for peer in fixture.school.identities:
			if int(peer)!=1:remote_identity=str(fixture.school.identities[peer])
		for id in service.population.people:
			var profile: Dictionary=service.population.profile_for(str(id))
			if str(profile.origin_population)==remote_identity.sha256_text() and profile.name=="Sam Singh":remote_id=str(id);break
		if remote_id.is_empty():return
		fixture.lecture_classes.classes={"audit":{"course":"MTH147","students":{remote_identity:{}},"classmates":{remote_id:{}}}}
		service.brain.remember_event(service.population.profile_for(remote_id),remote_identity,{"event":"study"},"Baseline shared work.","Yes.",1700000000,"departure-baseline")
		stage=1
	if stage==1 and fixture.get_meta("baseline_saved",false):
		stage=2
		if mode=="client":fixture.leave_client.rpc_id(root.multiplayer.get_peers()[0])
		service.brain.remember_event(service.population.profile_for(remote_id),remote_identity,{"event":"joke"},"The very last shared joke.","I will remember that.",1700000001,"departure-final")
		if mode!="client":started_leave=true;_leave_host.call_deferred()
	if mode=="client" and stage==2 and root.multiplayer.get_peers().is_empty():
		if not _has_event(service.brain,remote_id,remote_identity,"departure-final"):failures.append("Host lost retained social event")
		_finish()

func _leave_host() -> void:
	var started:=Time.get_ticks_msec()
	if mode=="paused":paused=true
	var completed: bool=await fixture.session.leave_gracefully()
	var elapsed:=Time.get_ticks_msec()-started
	if not completed or fixture.session.online:failures.append("Graceful host departure did not complete")
	if int(fixture.get_meta("leave_count",0))!=1:failures.append("Leaving callbacks ran more than once")
	if elapsed>2600:failures.append("Departure exceeded bounded grace")
	if mode=="timeout":
		if fixture.session.last_departure_saved or elapsed<Sync.DEPARTURE_TIMEOUT_MS-50:failures.append("Missing receipt did not reach bounded timeout")
	elif not fixture.session.last_departure_saved:failures.append("Recipient did not acknowledge durable checkpoint")
	if not _has_event(service.brain,remote_id,remote_identity,"departure-final"):failures.append("Host lost final event")
	print("DEPARTURE_TIMING ",mode," ",elapsed,"ms saved=",fixture.session.last_departure_saved)
	_finish()

func _leave_client() -> void:
	if not await fixture.session.leave_gracefully():failures.append("Client departure did not complete")
	if not fixture.session.last_departure_saved or not _verify_disk():failures.append("Client closed before its final event was durable")
	if int(fixture.get_meta("leave_count",0))!=1:failures.append("Client leaving callbacks ran more than once")
	_finish()

func _verify_disk() -> bool:
	# A new memory object reads the actual durable snapshot, not the receiver's
	# in-memory array or an RPC instrumentation counter.
	var restored:=Memory.new();restored.set_host_profile(fixture.school.local_identity)
	return restored.load_memory() and _has_event(restored,"campus_student_00",fixture.school.local_identity,"departure-final")

func _finish() -> void:
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_DEPARTURE_%s_%s %s"%[mode.to_upper(),role.to_upper(),"PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
