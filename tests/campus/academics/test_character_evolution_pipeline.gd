extends SceneTree
## Production CharacterInteraction/Mind/Brain integration with deterministic
## provider output. This validates delivery/persistence/race boundaries, not live
## language quality. Run with isolated Godot user data, for example:
## XDG_DATA_HOME=/tmp/labvolt-evolution godot --headless --path . \
##   --script res://tests/campus/academics/test_character_evolution_pipeline.gd
const Pipeline=preload("res://scripts/campus/academics/character_interaction.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const ACTIVITY:={"phase":"lesson","course":"ETY155","title":"Workshop discussion"}
var failures: Array[String]=[]
var checks:=0
var brain: RefCounted
var mind: RefCounted
var pipeline: RefCounted
var provider: FixtureProvider

class FixtureProvider extends Node:
	var busy:=false
	var replies: Array[Dictionary]=[]
	var event:="chat"
	var generated:=0
	var moderated: Array[String]=[]
	var during_interpretation: Callable
	func ready_for_class() -> bool:return true
	func moderate(text: String) -> Dictionary:
		moderated.append(text)
		return {"ok":true,"flagged":false}
	func interpret_character(_instructions: String,_context: Dictionary,_question: String) -> Dictionary:
		return {"ok":true,"text":JSON.stringify({"consistent":true,"reason":"Authored fixture recalls an existing personal detail."})}
	func respond_character(_instructions: String,context: Dictionary,_question: String,_visual:=false) -> Dictionary:
		generated+=1
		await get_tree().process_frame
		if during_interpretation.is_valid():
			during_interpretation.call();during_interpretation=Callable()
		await get_tree().process_frame
		var response: Dictionary=replies.pop_front() if not replies.is_empty() else {"speech":"I am still considering that."}
		response.interpretation={"event":event,"tone":"hostile" if event=="insult" else "neutral","severity":.9 if event=="insult" else .3,
			"meaning":"An authored fixture argument." if event=="disagreement" else "An authored fixture conversation.","domain":"conversation","difficulty":0.,
			"question_kind":"casual","assessment_request":"social","requested_action":"","memories":[],"sincere":false,"constructive":true,"topic_changed":false,"important":false}
		response.delivery={"emotion":str(context.get("emotional_state",{}).get("emotion","steady")),"knowledge_mode":"personal_conversation"}
		return {"ok":true,"text":JSON.stringify(response)}

func _initialize() -> void:call_deferred("_run")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message);push_error(message)

func _exchange(person: Dictionary,speaker: String,question: String,replies: Array,event: String="chat") -> Dictionary:
	provider.replies.assign(replies.duplicate(true));provider.event=event
	var prepared: Dictionary=await pipeline.prepare(provider,person,speaker,ACTIVITY,question)
	return await pipeline.generate(provider,prepared)

func _opinion(person: Dictionary) -> Dictionary:
	for item in brain.character_beliefs(person):
		if item.id=="education":return item
	return {}

func _revision(position: String,evidence: String,change:=.02) -> Dictionary:
	return {"id":"education","position":position,"reason":"A practical counterexample qualifies the previous position.","evidence":evidence,"conviction_change":change}

func _run() -> void:
	create_timer(30.).timeout.connect(func():push_error("Evolution fixture timed out");quit(1))
	mind=Mind.new();brain=Brain.new();brain.bind_mind(mind)
	pipeline=Pipeline.new();pipeline.bind(mind,brain)
	provider=FixtureProvider.new();root.add_child(provider)
	var profile_a:="evolution_fixture_"+str(Time.get_ticks_usec())
	var profile_b:=profile_a+"_other"
	check(brain.set_host_profile(profile_a)==OK and brain.load_memory(),"production memory opens an isolated host profile")
	var path_a: String=brain.memory_path
	var bro:=Profiles.teacher("mr_bro")
	bro.biography={"bench_press_pr":"My best bench press is 315 pounds."}
	var bench: String=brain.character_biography(bro).bench_press_pr
	var conflict:={"speech":"My best bench press is 225 pounds.","biography":{"topic":"training.bench_press_record","detail":"My best bench press is 225 pounds."}}
	var count:=provider.generated
	var rejected:=await _exchange(bro,"conflict-listener","What is your bench record?",[conflict,conflict])
	check(rejected.source=="technical_unavailable" and rejected.fallback_reason=="biography_update_invalid" and provider.generated-count==2,"a conflicting bench record is rejected before delivery with bounded retry")
	check(not conflict.speech in provider.moderated and rejected.line!=conflict.speech,"contradictory biography never reaches output moderation or delivered speech")
	pipeline.record(rejected)
	check(brain.character_biography(bro).bench_press_pr==bench and "315" in bench,"recovery retains the established personal record")
	var malformed:={"speech":"I grew up beside a quarry.","biography":"not an object"}
	var malformed_result:=await _exchange(bro,"malformed-listener","Where did you grow up?",[malformed,malformed])
	check(malformed_result.source=="technical_unavailable" and malformed_result.fallback_reason=="biography_update_invalid","malformed biography cannot disappear from pre-delivery validation")
	pipeline.record(malformed_result)
	check(not malformed.speech in provider.moderated and not "quarry" in JSON.stringify(brain.character_biography(bro)),"malformed biography is neither delivered nor canonized")
	var unspoken:={"speech":"I prefer to talk about training.","biography":{"topic":"childhood.quarry","detail":"I grew up beside a quarry."}}
	var unspoken_result:=await _exchange(bro,"unspoken-listener","What was your childhood like?",[unspoken,unspoken])
	check(unspoken_result.source=="technical_unavailable" and unspoken_result.fallback_reason=="biography_update_invalid","a biography proposal absent from actual speech is rejected before delivery")
	pipeline.record(unspoken_result)
	check(not brain.character_biography(bro).has("childhood.quarry"),"undelivered proposed details do not become biography")

	var life_line:="My best squat is 405 pounds. I trained with Luis for three winters."
	var life_reply:={"speech":life_line,"biography":null,"biography_facts":[
		{"topic":"training.squat_record","detail":"My best squat is 405 pounds."},
		{"topic":"training.partners.luis","detail":"I trained with Luis for three winters."}]}
	var life_result:=await _exchange(bro,"alex","Tell me about your squat and your training partner.",[life_reply])
	check(life_result.source=="ai" and life_result.line==life_line,"multiple specific biography facts pass the real generation validator")
	check(not brain.character_biography(bro).has("squat_pr"),"validated generated biography remains uncommitted until actual delivery is recorded")
	check(pipeline.record(life_result),"delivery records accepted biography through the production event path")
	var established: Dictionary=brain.character_biography(bro)
	check(established.squat_pr==life_reply.biography_facts[0].detail and established["training.partners.luis"]==life_reply.biography_facts[1].detail and established.bench_press_pr==bench,"separate specific facts coexist while the earlier bench record remains stable")
	var another:=await _exchange(bro,"jordan","Who did you train with?",[{"speech":"I trained with Luis for three winters."}])
	check("Luis" in JSON.stringify(another.prepared.context.personal_records) and not "315" in JSON.stringify(another.prepared.context.personal_records),"another listener retrieves the same relevant history without unrelated records")
	pipeline.record(another)
	check(brain.save_memory()==OK,"accepted exchanges and biography save together")
	var restored_brain:=Brain.new();var restored_mind:=Mind.new();restored_brain.bind_mind(restored_mind)
	check(restored_brain.set_host_profile(profile_a)==OK and restored_brain.load_memory(),"a fresh production mind and memory load the selected host")
	brain=restored_brain;mind=restored_mind;pipeline.bind(mind,brain)
	check(brain.character_biography(bro)==established and brain.recall(bro.id,"alex").size()==1,"specific biography and its delivered exchange survive a process-equivalent reload")

	var nye:=Profiles.teacher("bill_nye")
	var previous:=_opinion(nye)
	var argument:="My supervised placement helped me diagnose a real motor fault."
	var position:="College should include more supervised practical placements."
	var update:=_revision(position,argument,.04)
	var thought:={"speech":"That is a practical example. "+position,"belief_updates":[update]}
	var thoughtful:=await _exchange(nye,"alex",argument,[thought],"disagreement")
	check(thoughtful.source=="ai" and thoughtful.line==thought.speech,"a grounded Nye revision passes pre-delivery validation")
	check(_opinion(nye).position==previous.position,"a generated opinion is not stored before delivery")
	check(pipeline.record(thoughtful) and _opinion(nye).position==position and _opinion(nye).history_count==1,"delivered revision reaches the persistent character opinion")
	var next_turn:=await _exchange(nye,"jordan","Do you still think practical placements matter?",[{"speech":"That remains my view."}])
	check(next_turn.prepared.person.beliefs[0].position==position and next_turn.prepared.context.beliefs[0].position==position,"the next prepared person and generation context use the effective saved opinion")
	pipeline.record(next_turn)
	var unchanged: Dictionary=brain.belief_revisions.duplicate(true)
	var other_evidence:="My evening workshop gave working students more time to practise."
	var other_position:="College should offer flexible workshop hours as well as placements."
	var ordinary:=_revision(other_position,other_evidence,.02)
	var bad_cases:=[
		{"label":"duplicate IDs","question":other_evidence,"updates":[ordinary,ordinary]},
		{"label":"ungrounded quote","question":"I want to discuss a different idea.","updates":[ordinary]},
		{"label":"excessive conviction change","question":other_evidence,"updates":[_revision(other_position,other_evidence,.9)]},
		{"label":"too many revisions","question":other_evidence,"updates":[ordinary,ordinary,ordinary]},
		{"label":"repeated evidence","question":argument,"updates":[_revision(other_position,argument,.02)]}
	]
	for index in bad_cases.size():
		var test: Dictionary=bad_cases[index]
		var bad:={"speech":other_position,"belief_updates":test.updates}
		var result:=await _exchange(nye,"invalid-%d"%index,test.question,[bad,bad],"disagreement")
		check(result.source=="technical_unavailable" and result.fallback_reason=="belief_update_invalid" and result.line!=other_position,"%s cannot deliver an unpersistable changed opinion"%test.label)
		pipeline.record(result)
		check(brain.belief_revisions==unchanged,"%s leaves the accepted opinion and evidence history unchanged"%test.label)

	# Change the actual bound host profile while interpretation is suspended.
	# This uses no artificial validity flag: cancellation must follow identity.
	var switched:={"error":ERR_BUSY,"loaded":false,"mind":{},"path":""}
	provider.during_interpretation=func():
		switched.error=brain.set_host_profile(profile_b)
		switched.loaded=brain.load_memory()
		switched.mind=mind.export_state().duplicate(true)
		switched.path=brain.memory_path
	provider.event="insult"
	count=provider.generated
	var racing: Dictionary=await pipeline.prepare(provider,Profiles.teacher("brian"),"racing-speaker",ACTIVITY,"You are a useless teacher.")
	check(switched.error==OK and switched.loaded and brain.host_profile()==profile_b,"the awaited interpretation really crossed a host-profile switch")
	check(racing.get("cancelled",false) and racing.host_profile==profile_a and racing.fallback_reason=="request_context_changed","the stale interpretation is cancelled using its captured host identity")
	check(mind.export_state()==switched.mind and mind.moods.is_empty(),"stale interpretation cannot initialize or mutate the new profile's affect")
	check(brain.relationships.is_empty() and brain.conversations.is_empty() and brain.belief_revisions.is_empty() and brain.biographies.is_empty(),"stale interpretation cannot change new-profile relationships, history, opinions or biography")
	var cancelled: Dictionary=await pipeline.generate(provider,racing)
	check(cancelled.source=="cancelled" and cancelled.line.is_empty() and provider.generated==count+1 and not pipeline.record(cancelled),"cancelled profile work cannot request speech, deliver text or record an event")
	check(brain.set_host_profile(profile_a)==OK and brain.load_memory() and _opinion(nye).position==position and brain.character_biography(bro)==established and brain.recall("brian","racing-speaker").is_empty(),"returning to the original profile restores accepted evolution without the cancelled insult")
	for path in [path_a,str(switched.path)]:
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	provider.queue_free()
	print("CHARACTER_EVOLUTION_PIPELINE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," (deterministic provider; not live AI)")
	quit(0 if failures.is_empty() else 1)
