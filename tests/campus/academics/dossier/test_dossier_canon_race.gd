extends SceneTree
## Actual Brain and production generator with a held provider response. This is
## a concurrency/consistency fixture, not a claim about live model naturalness.
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Dossier=preload("res://scripts/campus/academics/character_dossier.gd")
const Generation=preload("res://scripts/campus/academics/character_dossier_generation.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Brain=preload("res://scripts/campus/academics/character_memory.gd")
const Fixture=preload("res://tests/campus/academics/dossier/dossier_fixture.gd")
var failures: Array[String]=[]
var checks:=0
class HeldClient extends Node:
	signal released
	var enabled:=true
	var busy:=false
	var background_busy:=false
	var model:="synthetic-canon-race"
	var calls:=0
	var held:=false
	var hold_next:=true
	var payload: Dictionary={}
	var contexts: Array=[]
	func host_allowed()->bool:return true
	func configured()->bool:return true
	func cancel_background_generation()->void:pass
	func generate_character_dossier(_instructions:String,context:Dictionary,_limit:int)->Dictionary:
		calls+=1
		contexts.append(context.duplicate(true))
		background_busy=true
		if hold_next:
			hold_next=false;held=true
			await released
			held=false
		else:await get_tree().process_frame
		background_busy=false
		return {"ok":true,"text":JSON.stringify(payload),"measurement":{"usage":{"input":100,"output":200},"latency_ms":20,"model":model}}
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func establish(brain:RefCounted,person:Dictionary,speaker:String,topic:String,detail:String,value:String)->void:
	brain.remember_conversation(person.id,speaker,"A personal question.",detail,int(Time.get_unix_time_from_system()))
	brain.remember_dialogue_details(person,speaker,"A personal question.",{"speech":detail,"biography":{"topic":topic,"detail":detail,"value":value,"kind":"current"}},int(Time.get_unix_time_from_system()))
func finish(generator:RefCounted)->void:
	var deadline:=Time.get_ticks_msec()+3000
	while generator.running and Time.get_ticks_msec()<deadline:await process_frame
	check(not generator.running,"background generation resolved within its fixture bound")
func run()->void:
	create_timer(12.).timeout.connect(func():printerr("DOSSIER_CANON_RACE TIMEOUT");quit(1))
	var owner:="dossier-canon-race-"+str(Time.get_ticks_usec())
	var brain:=Brain.new()
	check(brain.set_host_profile(owner)==OK,"actual brain is host-bound")
	var population:=Population.new()
	check(population.set_host_profile(owner)==OK,"population and dossier share the host")
	population.load_population()
	var person:=Profiles.teacher("mr_bro")
	var seed:=Store.get_dossier("mr_bro")
	var candidate:=Fixture.make("mr_bro","Mr Bro")
	candidate.identity=seed.identity.duplicate(true)
	candidate.voice=seed.voice.duplicate(true)
	candidate.traits=seed.traits.duplicate(true)
	for key in candidate.trait_evidence:
		var value:=float(candidate.traits[key])
		candidate.trait_evidence[key].level="low" if value<.34 else "high" if value>.66 else "moderate"
	candidate.life_history[4].text+=" His bench press record was 225 lb."
	candidate.compact_core=seed.compact_core+" His bench press record was 225 lb."
	candidate.communication.examples[0].reply="My bench press record is 225 lb."
	candidate=JSON.parse_string(JSON.stringify(candidate)) # Match the actual JSON transport precision.
	check(Dossier.validate(candidate,seed).ok,"complete held response satisfies the structural teacher schema: "+str(Dossier.validate(candidate,seed).errors))
	var changed_appearance:=candidate.duplicate(true)
	changed_appearance.identity.appearance.build=1.1
	check(not Dossier.validate(changed_appearance,seed).ok,"JSON number compatibility still rejects an actual appearance change")
	establish(brain,person,"player-before","favorite_drink","My favorite drink is iced tea.","iced tea")
	var client:=HeldClient.new();root.add_child(client);client.payload=candidate
	var generator:=Generation.new();generator.configure(client,population,brain)
	generator.tick(["mr_bro"])
	check(client.held and client.calls==1,"actual background request is held while gameplay can continue")
	check(client.contexts[0].canonical_personal_records.has("favorite_drink"),"first generation includes already shared personal canon")
	check(not client.contexts[0].canonical_personal_records.has("bench_press_pr"),"new personal record was not known when generation started")
	establish(brain,person,"player-during","bench_press_pr","My bench press record is 245 lb.","245 lb")
	check(brain.character_life_records(person).get("bench_press_pr",{}).get("value")=="245 lb","foreground delivery establishes real shared Brain canon while request is pending")
	check(brain.save_memory()==OK,"new shared fact is durably saved")
	client.released.emit();await finish(generator)
	check(Store.get_dossier("mr_bro").generation.status=="needs_expansion","stale complete response cannot publish")
	var job:Dictionary=Store.jobs.mr_bro
	if not job.get("invalid_sections",[]).has("life_history"): print("CANON_RACE unexpected job: ",job.get("issues",[]))
	check(job.stage=="repair" and job.invalid_sections.has("life_history") and job.invalid_sections.has("compact_core"),"only biography-bearing stages are rebased on changed canon")
	check(job.invalid_sections.has("communication") and job.canon_example_ids==["example_0"],"definitely contradictory personal example is individually selected for repair")
	check(not job.invalid_sections.has("traits") and job.draft.traits==candidate.traits,"completed independent traits remain unchanged")
	check(job.draft.communication.examples==candidate.communication.examples,"all examples remain stored until the targeted correction arrives")
	check(not job.has("canonical_personal_records") and job.canon_hashes.has("favorite_drink"),"job persists hashes rather than duplicating the growing personal ledger")
	check(not Store.get_dossier("mr_bro").established_biography.has("bench_press_pr"),"dynamic fact is not copied into an immutable legacy anchor")
	var fixed_life:Array=candidate.life_history.duplicate(true)
	fixed_life[4].text=str(fixed_life[4].text).replace("225 lb","245 lb")
	client.payload={"life_history":fixed_life,"compact_core":str(candidate.compact_core).replace("225 lb","245 lb"),"traits":{"confidence":0.},
		"communication":{"description":"This unrequested rewrite must be ignored.","examples":[{"id":"example_0","reply":"My bench press record is 245 lb.","mood":"angry"},{"id":"example_1","reply":"An unrelated example must not be rewritten."}]}}
	Store.jobs.mr_bro.retry_at=0;generator._next_start_ms=0
	client.hold_next=true
	generator.tick(["mr_bro"])
	check(client.held and client.calls==2,"only one bounded repair request begins")
	check(client.contexts[1].canonical_personal_records.bench_press_pr.value=="245 lb","repair uses the latest shared canonical value")
	check(client.contexts[1].communication_repair.example_ids==["example_0"],"provider receives exact example repair scope")
	# A metadata-only timestamp update is not a semantic change and must not
	# provoke another biography request or discard the now-consistent repair.
	brain.biography_records.mr_bro.bench_press_pr.at+=60
	client.released.emit();await finish(generator)
	var published:=Store.get_dossier("mr_bro")
	check(published.generation.status=="complete" and client.calls==2,"corrected draft publishes with no redundant full generation: "+str(Store.jobs.mr_bro.get("issues",[])))
	if published.generation.status!="complete": client.queue_free();quit(1);return
	check(published.traits==candidate.traits,"unrequested trait rewrite is ignored")
	check(published.identity.appearance==seed.identity.appearance,"exact authored appearance is retained after the JSON round-trip")
	check(published.communication.description==candidate.communication.description,"unrequested speaking description rewrite is ignored")
	check(published.communication.examples[0].reply=="My bench press record is 245 lb." and published.communication.examples[0].mood==candidate.communication.examples[0].mood,"only the conflicting example words change")
	check(published.communication.examples.slice(1)==candidate.communication.examples.slice(1),"every unrelated dialogue example remains byte-for-byte equivalent")
	check("245 lb" in published.life_history[4].text and not "225 lb" in JSON.stringify(published),"published prose and example agree with shared personal canon")
	check(brain.character_life_records(person).bench_press_pr.value=="245 lb" and not published.established_biography.has("bench_press_pr"),"publication preserves the sole developing-fact authority")
	check(published.generation.measurement.requests==2 and published.generation.measurement.canon_repairs==1,"actual fixture requests and canon repair are accounted once")
	# The same protection applies when a validated draft was saved but its
	# publication is retried later, without making an unnecessary HTTP call.
	var pending:=Fixture.make("campus_student_92","Devon Quill")
	pending.life_history[4].text+=" Their bench press record was 225 lb."
	Store.queue_student("campus_student_92")
	var recovery:Dictionary=Store.jobs.campus_student_92
	var captured:Dictionary=generator._capture_canon("campus_student_92",{})
	recovery.stage="publish";recovery.draft=pending;recovery.canon_fingerprint=captured.fingerprint;recovery.canon_hashes=captured.hashes
	establish(brain,{"id":"campus_student_92"},"player-later","bench_press_pr","My bench press record is 245 lb.","245 lb")
	check(Store.save()==OK,"publication draft checkpoint saves with valid canon hashes")
	var before:=client.calls
	generator._next_start_ms=0;generator.tick(["campus_student_92"])
	await finish(generator)
	check(client.calls==before and not Store.dossiers.has("campus_student_92"),"publication recovery refuses stale canon before any API request or publication")
	check(Store.jobs.campus_student_92.stage=="repair" and Store.jobs.campus_student_92.draft.traits==pending.traits,"recovery preserves completed draft for only needed biography repair")
	check(Store._read(Store.path).get("jobs",{}).get("campus_student_92",{}).get("canon_fingerprint")==captured.fingerprint,"new hash metadata survives persistence validation")
	# A large existing personal ledger must never be silently cut to fit the
	# background transport. Retain the validated draft and hold without HTTP.
	Store.jobs.campus_student_92.retry_at=int(Time.get_unix_time_from_system())+60
	Store.queue_student("campus_student_93")
	var oversized:=Fixture.make("campus_student_93","Avery Banks")
	Store.jobs.campus_student_93.stage="repair"
	Store.jobs.campus_student_93.draft=oversized
	Store.jobs.campus_student_93.invalid_sections=["life_history","compact_core"]
	for index in 80:
		var value:="remembered experience %03d"%index
		var detail:="I recall a "+value+". "+"It was an ordinary afternoon in a familiar neighborhood. ".repeat(12)
		establish(brain,{"id":"campus_student_93"},"earlier-player","saved_story_%03d"%index,detail,value)
	check(brain.character_life_records({"id":"campus_student_93"}).size()==80,"large context fixture is actual established Brain personal history")
	generator._next_start_ms=0;generator.tick(["campus_student_93"])
	await finish(generator)
	var blocked:Dictionary=Store.jobs.campus_student_93
	check(client.calls==before and int(blocked.get("request_attempts",0))==0,"oversized canonical constraints are held before any provider request")
	check(blocked.status=="failed" and "60000-character" in blocked.last_error,"oversized generation exposes the exact context-limit diagnostic")
	check(blocked.draft==oversized and not Store.dossiers.has("campus_student_93"),"context limit preserves every completed section without publishing or dropping canon")
	print("DOSSIER_CANON_RACE %s checks=%d synthetic_provider_actual_brain"%["PASS" if failures.is_empty() else "FAIL",checks])
	client.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
