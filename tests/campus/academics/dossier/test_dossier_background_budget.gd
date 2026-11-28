extends SceneTree
## Real persistent generator with an explicitly held fixture response. No API use.
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Generation=preload("res://scripts/campus/academics/character_dossier_generation.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Fixture=preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
var failures: Array[String]=[]
var checks:=0
class Client extends Node:
	signal released
	var enabled:=true
	var busy:=false
	var background_busy:=false
	var model:="fixture-budget"
	var calls:=0
	var hold:=true
	var reject:=false
	var payload: Dictionary={}
	func host_allowed()->bool:return true
	func configured()->bool:return true
	func cancel_background_generation()->void:pass
	func generate_character_dossier(_instructions:String,_context:Dictionary,_output:int)->Dictionary:
		calls+=1
		if hold:await released
		else:await get_tree().process_frame
		if reject:return {"ok":false,"error":"Fixture permission denied.","retryable":false}
		return {"ok":true,"text":JSON.stringify(payload),"measurement":{"usage":{"input":100,"output":200},"latency_ms":20,"model":model}}
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func settled(generator:RefCounted)->void:
	while generator.running:await process_frame
func run()->void:
	create_timer(15.).timeout.connect(func():printerr("DOSSIER_BACKGROUND_BUDGET TIMEOUT");quit(1))
	var owner:="dossier-budget-"+str(Time.get_ticks_usec())
	var population:=Population.new()
	check(population.set_host_profile(owner)==OK,"Isolated durable namespace opens")
	population.load_population()
	var client:=Client.new();root.add_child(client)
	var generator:=Generation.new();generator.client=client;generator.population=population;generator._bound_host=Store.host_identity
	var pending:=Store.jobs.size()
	generator.tick([],true,false)
	check(client.calls==0 and Store.jobs.size()==pending,"Empty campus does not expand dossiers or queue population requests")
	var candidate:=Fixture.make();var id:=str(candidate.identity.id)
	client.payload=candidate
	Store.queue_student(id)
	generator.tick([],true,false)
	check(client.calls==0,"Existing queued students remain idle without an audience")
	client.busy=true;generator.tick([id],true,false)
	check(client.calls==0,"Foreground provider lane takes priority")
	client.busy=false
	var state:={"active":true}
	generator.publication_guard=func(_id:String):return not state.active
	generator.tick([id],true,false)
	check(client.calls==0,"An active character conversation blocks identity regeneration")
	state.active=false;generator.tick([id],true,false)
	check(client.calls==1 and generator.running,"Relevant idle character starts exactly one request")
	state.active=true;client.released.emit();await settled(generator)
	check(Store.jobs[id].stage=="publish" and Store.jobs[id].status=="queued","A conversation that starts during generation defers publication")
	check(not population.people.has(id),"Held identity cannot replace a character during conversation")
	check(Store.jobs[id].measurement.requests==1 and Store.jobs[id].measurement.usage.input==100,"Held publication retains request and usage accounting")
	Store.jobs[id].attempts=Generation.MAX_ATTEMPTS
	generator._next_start_ms=0;generator.tick([id],true,false)
	check(client.calls==1 and not population.people.has(id),"Repeated ticks while busy do not regenerate or publish")
	state.active=false;generator.tick([id],true,false);await settled(generator)
	generator._next_start_ms=0;generator.tick([id],true,false);await settled(generator)
	check(client.calls==1 and population.people.has(id),"Completed draft publishes after conversation even at the attempt limit without another model call")
	check(Store.get_dossier(id).generation.measurement.requests==1,"Published dossier retains original request count")
	var failed_id:="campus_student_91"
	Store.queue_student(failed_id);client.hold=false;client.reject=true
	generator._next_start_ms=0;generator.tick([failed_id],true,false);await settled(generator)
	check(Store.jobs[failed_id].status=="failed" and client.calls==2,"Permission failure is terminal instead of retrying a full biography")
	Store.jobs[failed_id].retry_at=0;generator._next_start_ms=0;generator.tick([failed_id],true,false)
	check(client.calls==2,"Background timer does not retry nonretryable errors")
	client.reject=false
	var custom:=generator.request_teacher("MTH147","An impatient mathematician with a private ambition.")
	check(custom.get("ok",false),"Explicit instructor request is accepted")
	client.payload=Fixture.make(str(custom.id),"Morgan Voss");client.payload.identity.role="teacher"
	generator.tick([],true,false);await settled(generator)
	check(client.calls==3 and Store.jobs[custom.id].status=="complete","Explicit instructor creation proceeds without a nearby player")
	print("DOSSIER_BACKGROUND_BUDGET ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," provider_requests=",client.calls," source=authored provider fixture")
	client.queue_free();quit(0 if failures.is_empty() else 1)
