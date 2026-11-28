extends SceneTree
## Real separate ENet processes using production synchronization. Synthetic
## identities only; provider requests are not involved.
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Sync=preload("res://scripts/campus/academics/student_population_sync.gd")
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
var role:=""
var fixture: Node
var service: Node
var failures: Array[String]=[]
var remote_identity:=""
var remote_id:=""
var stage:=0
var deadline:=0

class School extends Node:
	var local_identity:=""
	var identities: Dictionary={}
class Session extends Node:
	var online:=true
class Students extends Node:
	var population:=Population.new()
class Classes extends Node:
	var classroom_students:=Students.new()
	var classes: Dictionary={}
class Faculty extends Node:
	var brain:=Memory.new()
class Game extends Node:
	var school:=School.new()
	var session:=Session.new()
	var lecture_classes:=Classes.new()
	var faculty:=Faculty.new()
	func _init() -> void:
		add_child(school);add_child(session);add_child(lecture_classes);add_child(faculty)
		lecture_classes.add_child(lecture_classes.classroom_students)
	@rpc("any_peer","call_remote","reliable")
	func identify(id: String) -> void:
		if multiplayer.is_server() and id.length()==48:school.identities[multiplayer.get_remote_sender_id()]=id
	@rpc("authority","call_remote","reliable")
	func result(value: String) -> void:
		set_meta("received_result",value)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	role=OS.get_environment("LABVOLT_POP_ROLE")
	var port:=int(OS.get_environment("LABVOLT_POP_PORT"))
	var id:=OS.get_environment("LABVOLT_POP_ID")
	fixture=Game.new();fixture.name="PopulationFixture";root.add_child(fixture)
	fixture.school.local_identity=id
	var population: RefCounted=fixture.lecture_classes.classroom_students.population
	population.set_host_profile(id);population.load_population()
	if population.people.is_empty():Legacy.seed(population,12);population.save_population()
	fixture.faculty.brain.set_host_profile(id);fixture.faculty.brain.load_memory()
	var peer:=ENetMultiplayerPeer.new()
	var error:=peer.create_server(port,2) if role=="server" else peer.create_client("127.0.0.1",port)
	if error!=OK:failures.append("ENet setup failed");_finish();return
	root.multiplayer.multiplayer_peer=peer
	if role=="server":fixture.school.identities[1]=id
	else:
		root.multiplayer.connected_to_server.connect(func():fixture.identify.rpc_id(1,id))
	service=Sync.new();service.name="StudentPopulationSync";fixture.add_child(service);service.configure(fixture)
	deadline=Time.get_ticks_msec()+45000
	process_frame.connect(_step)

func _step() -> void:
	if Time.get_ticks_msec()>deadline:failures.append("Timed out at stage %d: %s"%[stage,JSON.stringify(service.diagnostics())]);_finish();return
	if not service._bind():return
	if role=="client":
		var person_id:="campus_student_00"
		var memory: Dictionary=service.brain.relationship(person_id,fixture.school.local_identity)
		if memory.get("episodes",[]).any(func(episode):return episode.get("event_id")=="network-friendship"):
			if float(service.brain.social_context(memory).friendship)<=0.:failures.append("Friendship did not travel to owner")
			fixture.identify.rpc_id(1,fixture.school.local_identity)
			print("POPULATION_NETWORK_CLIENT PASS own relationship persisted")
			quit(0)
		return
	if stage==0 and fixture.school.identities.size()>1:
		for peer in fixture.school.identities:
			if int(peer)!=1:remote_identity=str(fixture.school.identities[peer])
		var target_origin:=remote_identity.sha256_text()
		for id in service.population.people:
			var profile: Dictionary=service.population.profile_for(str(id))
			if str(profile.origin_population)==target_origin and profile.name=="Sam Singh":remote_id=str(id);break
		if remote_id.is_empty():return
		var person: Dictionary=service.population.profile_for(remote_id)
		service.brain.remember_event(person,remote_identity,{"event":"study","interpretation":{"summary":"We worked together on the practice project."}},"Let's study together.","Sure.",1700000001,"network-friendship")
		fixture.lecture_classes.classes={"test":{"id":"network-class","course":"MTH147","students":{remote_identity:{"peer":root.multiplayer.get_peers()[0]}},"classmates":{remote_id:{"profile":person}}}}
		stage=1
	if stage==1 and root.multiplayer.get_peers().is_empty():
		if not service.population.people.has(remote_id):failures.append("Admitted student disappeared on disconnect")
		if service.population.save_population()!=OK:failures.append("Retained population did not save")
		_finish()

func _finish() -> void:
	for failure in failures:printerr("FAIL: "+failure)
	print("POPULATION_NETWORK_%s %s"%[role.to_upper(),"PASS" if failures.is_empty() else "FAIL"])
	quit(0 if failures.is_empty() else 1)
