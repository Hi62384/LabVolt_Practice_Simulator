extends SceneTree
## Production group scheduler with an explicit provider/transport fixture.
## This proves bounds, intent routing and privacy, not generated language quality.
const Shared=preload("res://scripts/campus/academics/classroom_events/shared_work.gd")
var checks:=0
var failures: Array[String]=[]
class Client extends Node:
	var busy:=false
	var online:=true
	func ready_for_class() -> bool:return online
class Classes extends Node:
	var classes: Dictionary={}
	func _now() -> float:return 10.0
class Recorder extends RefCounted:
	var deliveries: Array=[]
	func record(_result: Dictionary,delivered: bool) -> bool:deliveries.append(delivered);return true
class Faculty extends Node:
	var calls:=0
	var captured: Dictionary={}
	var line:="Check the units before we compare those two values."
	var character_interaction:=Recorder.new()
	func generate_character_exchange(_person: Dictionary,_listener: String,_activity: Dictionary,_question: String,extra: Dictionary) -> Dictionary:
		calls+=1;captured=extra
		await get_tree().process_frame
		return {"line":line,"cancelled":not bool(extra._valid.call())}
class Practice extends RefCounted:
	var event_id:="group-fixture"
	var closed:=false
	# Real solo-human group rounds add an NPC to shared work only. The helper
	# does not become a graded participant merely by contributing a note.
	var present: Dictionary={"c_peer":true}
	var answer_key:="PRIVATE_RESULT"
	func snapshot(_identity: String,_now: float) -> Dictionary:return {"question":{"prompt":"Compare the quantities and explain your reasoning.","options":[]}}
class Game extends Node:
	var host_openai: Client
	var faculty: Faculty
	var lecture_classes: Classes
class ServiceProbe extends "res://scripts/campus/academics/classroom_events/service.gd":
	var publications:=0
	func publish(_room: String,_now: float) -> void:publications+=1
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize() -> void:call_deferred("run")
func shared_fixture() -> RefCounted:
	var shared:=Shared.new();shared.begin("group",["c_peer"]);shared.add_member("a_npc")
	return shared
func run() -> void:
	var game:=Game.new();root.add_child(game)
	game.host_openai=Client.new();game.add_child(game.host_openai)
	game.faculty=Faculty.new();game.add_child(game.faculty)
	game.lecture_classes=Classes.new();game.add_child(game.lecture_classes)
	var service:=ServiceProbe.new();root.add_child(service);service.configure(game)
	var actor:={"profile":{"id":"a_npc","name":"Fixture Student"},"seated":true,"next":0.0}
	var activity:={"id":"class-fixture","phase":"lesson","classmates":{"a_npc":actor}}
	var shared:=shared_fixture()
	var state:={"round":Practice.new(),"shared":shared}
	service.rooms.room=state
	check(not state.round.present.has("a_npc") and shared.present.has("a_npc"),"an NPC helper participates in shared work without becoming a graded human participant")
	check(service._classmate_group("room",state,activity,10.0),"a meaningful group contribution starts one bounded generation")
	check(not service._classmate_group("room",state,activity,10.1) and game.faculty.calls==1,"pending work never launches a duplicate per-frame request")
	await process_frame;await process_frame
	check(shared.entries.size()==1 and shared.entries[0].text==game.faculty.line,"only the generated contribution is published")
	check(game.faculty.character_interaction.deliveries==[true] and actor.action=="discussing group work","actual note publication controls delivered memory and local behavior")
	check(not "PRIVATE_RESULT" in JSON.stringify(game.faculty.captured.teaching_step),"only released practice information reaches the request")
	check(not service._classmate_group("room",state,activity,40.0) and game.faculty.calls==1,"completed contributions are never generated again")
	shared=shared_fixture()
	state={"round":Practice.new(),"shared":shared};service.rooms.room=state
	game.host_openai.online=false
	check(not service._classmate_group("room",state,activity,50.0) and shared.entries.is_empty(),"offline group work does not fabricate a generic personality note")
	game.host_openai.online=true
	service._classmate_group("room",state,activity,60.0)
	activity.phase="assignment"
	await process_frame;await process_frame
	check(shared.entries.is_empty() and game.faculty.character_interaction.deliveries==[true],"a phase change cancels delayed group contribution and its memory")
	activity.phase="lesson"
	for interruption in ["leaving","absent","replaced"]:
		actor={"profile":{"id":"a_npc","name":"Fixture Student"},"seated":true,"next":0.0}
		activity.classmates={"a_npc":actor}
		shared=shared_fixture()
		state={"round":Practice.new(),"shared":shared};service.rooms.room=state
		check(service._classmate_group("room",state,activity,80.0),"start pending contribution before "+interruption)
		if interruption=="leaving":
			# Production discipline marks the route in progress before the student
			# reaches the exit and removed_from_class becomes true.
			actor.leaving_class=true;actor.seated=false;actor.walking=true;actor.action="leaving class"
		elif interruption=="absent":
			shared.set_present("a_npc",false)
		else:
			activity.classmates["a_npc"]={"profile":{"id":"a_npc","name":"Different actor"},"seated":true,"next":0.0}
		await process_frame;await process_frame
		check(shared.entries.is_empty() and game.faculty.character_interaction.deliveries==[true],interruption+" cancels delayed contribution and its memory")
		if interruption=="leaving":check(actor.action=="leaving class","group completion cannot overwrite an active removal route")
		state.npc_group_attempted={}
		if interruption!="replaced":check(not service._classmate_group("room",state,activity,100.0),interruption+" actor cannot start a fresh group request")
	print("CHARACTER_GROUP_INTENT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," source=explicit scheduling fixture, not live AI")
	service.queue_free();game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
