extends SceneTree
const Store = preload("res://scripts/campus/academics/character_dossier_store.gd")
const Dossier = preload("res://scripts/campus/academics/character_dossier.gd")
const Generation = preload("res://scripts/campus/academics/character_dossier_generation.gd")
const Population = preload("res://scripts/campus/academics/student_population.gd")
const Fixture = preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
var failures: Array[String]=[]
class FixtureClient extends Node:
	var enabled:=true
	var busy:=false
	var background_busy:=false
	var model:="fixture-no-live-ai"
	var calls:=0
	var contexts: Array=[]
	var payload: Dictionary={}
	func host_allowed()->bool:return true
	func configured()->bool:return true
	func cancel_background_generation()->void:pass
	func generate_character_dossier(_instructions:String,context:Dictionary,_output:int)->Dictionary:
		calls+=1
		contexts.append(context.duplicate(true))
		await get_tree().process_frame
		var data:=payload.duplicate(true)
		if calls==1:data.communication.description="too short"
		if calls==2:data={"communication":payload.communication}
		return {"ok":true,"text":JSON.stringify(data),"measurement":{"usage":{"input":100,"output":200},"latency_ms":20,"model":"fixture-no-live-ai"}}
func _initialize()->void:call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func run()->void:
	var owner:="dossier-generation-"+str(Time.get_ticks_usec())
	check(Store.set_host_profile(owner)==OK,"isolated owner")
	var first:=Fixture.make()
	var second:=Fixture.make("campus_student_91","Ellis Marr",false)
	var validation:=Dossier.validate(first,{"identity":{"id":first.identity.id,"role":"student"}})
	check(validation.ok,"fixture must satisfy schema: "+str(validation.errors))
	var broken:=first.duplicate(true)
	broken.traits.confrontation=.05
	check(not Dossier.validate(broken).ok,"trait evidence contradiction rejected")
	broken=first.duplicate(true)
	broken.life_history[0].source="observed_gameplay"
	check(not Dossier.validate(broken).ok,"fabricated gameplay provenance rejected")
	broken=first.duplicate(true)
	broken.identity.age=16
	check(not Dossier.validate(broken).ok,"nonadult student rejected")
	var population:=Population.new()
	population.set_host_profile(owner)
	population.load_population()
	var client:=FixtureClient.new()
	root.add_child(client)
	client.payload=first
	var generator:=Generation.new()
	generator.client=client
	generator.population=population
	generator._bound_host=Store.host_identity
	Store.queue_student(first.identity.id)
	generator.tick()
	generator.tick()
	await process_frame
	await process_frame
	check(client.calls==1,"bounded one request in flight")
	check(not population.people.has(first.identity.id),"invalid dossier not published")
	check(Store.jobs[first.identity.id].stage=="repair","invalid section retained for repair")
	check(Store.jobs[first.identity.id].invalid_sections==["communication"],"only broken section requires repair")
	Store.jobs[first.identity.id].retry_at=0
	generator._next_start_ms=0
	generator.tick()
	await process_frame
	await process_frame
	check(client.calls==2,"one repair request")
	check(client.contexts[1].task.begins_with("Repair only"),"repair does not regenerate completed history")
	check(population.people.has(first.identity.id),"valid dossier published after repair")
	check(Store.jobs[first.identity.id].status=="complete","completed job persisted")
	check(Store.get_dossier(first.identity.id).generation.measurement.usage.input==200,"actual fixture token metadata aggregated")
	check(Store.get_dossier(first.identity.id).life_history==first.life_history,"repair preserves completed biography exactly")
	check(Store.publish(second,{"identity":{"id":second.identity.id,"role":"student"}}).ok,"second distinct fixture publishes")
	check(population.import_generated(Generation.student_profile(Store.get_dossier(second.identity.id))),"second student import")
	check(population.profile_for(first.identity.id).traits.confrontation!=population.profile_for(second.identity.id).traits.confrontation,"independent traits projected unchanged")
	var selected:=population.available({first.identity.id:true},6,4)
	check(selected.all(func(p):return p.id!=first.identity.id),"occupied identities excluded from other locations")
	check(population.save_population()==OK,"population saved")
	var reopened:=Population.new()
	reopened.set_host_profile(owner)
	reopened.load_population()
	check(reopened.profile_for(first.identity.id).name==first.identity.name,"saved identity survives reload")
	check(Store.set_host_profile(owner+"-other")==OK and Store.set_host_profile(owner)==OK,"dossier reload")
	check(Store.get_dossier(first.identity.id).voice.identifier=="coral","permanent voice survives reload")
	check(Store.jobs[first.identity.id].status=="complete","completed generation not requeued after reload")
	generator._bound_host=Store.host_identity
	var custom:=generator.request_teacher("MTH147","An impatient ambitious mathematician who dislikes meetings.")
	check(custom.get("ok",false) and custom.get("queued",false),"custom teacher queued")
	check(not preload("res://scripts/campus/academics/faculty_roster.gd").has(str(custom.id)),"incomplete teacher not exposed in roster")
	var duplicate:=generator.request_teacher("MTH147","An impatient ambitious mathematician who dislikes meetings.")
	check(duplicate.get("id")==custom.id,"duplicate pending creation deduplicated")
	var teacher:=Fixture.make(str(custom.id),"Morgan Voss")
	teacher.identity.role="teacher"
	client.payload=teacher
	generator._next_start_ms=0
	generator.tick()
	await process_frame
	await process_frame
	check(preload("res://scripts/campus/academics/faculty_roster.gd").has(str(custom.id)),"complete custom teacher published")
	check(Store.get_dossier(str(custom.id)).get("subjects",[])==["MTH147"],"teacher course retained authoritatively")
	var checkpoint: Dictionary={"version":Store.VERSION,"dossiers":Store.dossiers,"jobs":Store.jobs.duplicate(true)}
	var job_id: String=checkpoint.jobs.keys()[0]
	checkpoint.jobs[job_id].attempts={"damaged":true}
	var invalid_path:="user://dossier-malformed-job-%d.json"%Time.get_ticks_usec()
	var invalid_file:=FileAccess.open(invalid_path,FileAccess.WRITE)
	invalid_file.store_string(JSON.stringify(checkpoint));invalid_file.close()
	check(Store._read(invalid_path).is_empty(),"malformed job counters rejected before integer conversion")
	DirAccess.remove_absolute(invalid_path)
	print("DOSSIER_GENERATION PASS (synthetic transport contract, not live AI quality)" if failures.is_empty() else "DOSSIER_GENERATION FAIL "+str(failures))
	client.queue_free()
	quit(0 if failures.is_empty() else 1)
