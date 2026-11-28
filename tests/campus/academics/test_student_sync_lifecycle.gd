extends SceneTree
const Sync=preload("res://scripts/campus/academics/student_population_sync.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
var failures: Array[String]=[]
class School extends Node:
	var local_identity:=""
	var identities: Dictionary={}
class Faculty extends Node:
	var brain: RefCounted
class Session extends Node:
	signal leaving
	var online:=false
class Students extends Node:
	var population: RefCounted
class Classes extends Node:
	var classroom_students: Node
	var classes: Dictionary={}
class Game extends Node:
	var school:=School.new()
	var faculty:=Faculty.new()
	var session:=Session.new()
	var lecture_classes:=Classes.new()
	func _init() -> void:
		add_child(school);add_child(faculty);add_child(session);add_child(lecture_classes)

func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game:=Game.new();root.add_child(game)
	game.school.local_identity="student-lifecycle-"+str(Time.get_ticks_usec())
	var sync:=Sync.new();root.add_child(sync);sync.configure(game);sync.set_process(false)
	check(not sync._bind(),"Missing classroom node defers safely")
	var students:=Students.new();game.lecture_classes.add_child(students);game.lecture_classes.classroom_students=students
	students.population=Population.new()
	check(not sync._bind() and not sync._bind(),"Null brain never becomes falsely bound")
	game.faculty.brain=Memory.new();game.faculty.brain.set_host_profile(game.school.local_identity);game.faculty.brain.load_memory()
	students.population.set_host_profile(game.school.local_identity);students.population.load_population()
	check(sync._bind() and sync.population==students.population and sync.brain==game.faculty.brain,"Host binds authoritative instances")
	var original: RefCounted=sync.population
	var client:=ENetMultiplayerPeer.new();check(client.create_client("127.0.0.1",45993)==OK,"Client role fixture starts")
	root.multiplayer.multiplayer_peer=client
	check(sync._bind() and not sync._bound_server and sync.population!=original,"Same identity switching to client loads own contribution service")
	client.close();root.multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	check(sync._bind() and sync._bound_server and sync.population==original and sync.brain==game.faculty.brain,"Returning to host replaces client references even with same profile")
	var replacement:=Population.new();replacement.set_host_profile(game.school.local_identity);replacement.load_population();students.population=replacement
	check(sync._bind() and sync.population==replacement,"Recreated classroom authority replaces stale reference")
	game.session.leaving.emit()
	game.queue_free()
	check(not sync._bind(),"Queued game teardown does not access child state")
	sync.queue_free()
	await process_frame
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_SYNC_LIFECYCLE "+("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
