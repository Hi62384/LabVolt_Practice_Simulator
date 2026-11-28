extends SceneTree
## State/transport-contract regression only. Fixture speech is not evidence of
## live model style, cost or latency; production methods execute unmodified.
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Store=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Interaction=preload("res://scripts/campus/academics/character_interaction.gd")
const Life=preload("res://scripts/campus/academics/character_life_memory.gd")
const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")
var failures: Array[String]=[]
var checks:=0
class Provider extends Node:
	var busy:=false
	var available:=true
	var responses: Array=[]
	var model_calls:=0
	var moderation_calls:=0
	var interpretations:=0
	var contexts: Array=[]
	var reviews: Array=[]
	func ready_for_class() -> bool:return available
	func moderate(_text: String) -> Dictionary:
		moderation_calls+=1
		await get_tree().process_frame
		return {"ok":true,"flagged":false,"measurement":{"usage":{},"latency_ms":1}}
	func respond_character(_rules: String,context: Dictionary,_question: String,_visual:=false) -> Dictionary:
		model_calls+=1;contexts.append(context.duplicate(true))
		await get_tree().process_frame
		if responses.is_empty():return {"ok":false,"error":"fixture_exhausted"}
		return {"ok":true,"text":JSON.stringify(responses.pop_front()),"measurement":{"usage":{"input":1234,"output":177,"cached":512},"latency_ms":2}}
	func interpret_character(_rules: String,_context: Dictionary,_question: String) -> Dictionary:
		interpretations+=1
		await get_tree().process_frame
		return {"ok":true,"text":JSON.stringify(reviews.pop_front() if not reviews.is_empty() else {"consistent":true,"reason":"Existing fixture detail."}),"measurement":{"usage":{"input":220,"output":30},"latency_ms":2}}

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)

func _initialize() -> void:call_deferred("run")

func utterance(speech: String,kind: String="casual",facts: Array=[],emotion: String="steady",event: String="chat") -> Dictionary:
	return {"speech":speech,"interpretation":{"event":event,"tone":"neutral","severity":.1,"meaning":"Synthetic contract fixture","topic":"training" if kind=="biography" else "conversation","domain":"fitness" if kind=="biography" else "conversation","difficulty":.2,"question_kind":kind,"assessment_request":"social","requested_action":"","memories":[]},
		"delivery":{"emotion":emotion,"knowledge_mode":"personal_conversation"},"behavior":{"intention":"Respond personally","mode":"engage","action":""},"biography_facts":facts,"belief_updates":[]}

func run() -> void:
	var brain:=Brain.new()
	var fixture_profile:="dossier-pipeline-"+str(Time.get_ticks_usec())
	var mind:=Mind.new()
	brain.set_host_profile(fixture_profile);brain.load_memory();brain.bind_mind(mind)
	Store.set_host_profile(fixture_profile)
	var interaction:=Interaction.new();interaction.bind(mind,brain)
	var client:=Provider.new();root.add_child(client)
	var person:=Profiles.teacher("mr_bro")
	var activity:={"id":"fixture","phase":"freeplay","private_answer":"PRIVATE_KEY_DO_NOT_DISCLOSE"}
	client.responses=[utterance("Yo, what's good?", "casual",[],"steady","greeting")]
	var prepared:=await interaction.prepare(client,person,"player-one",activity,"Hey")
	var result:=await interaction.generate(client,prepared)
	check(result.source=="ai","a valid combined response is delivered")
	check(client.model_calls==1 and client.interpretations==0,"routine turn uses one model generation and no sequential semantic request")
	check(client.moderation_calls==2,"input and actual spoken output moderation remain")
	check(not JSON.stringify(client.contexts).contains("PRIVATE_KEY_DO_NOT_DISCLOSE"),"private gameplay fields do not enter model context")
	check(interaction.record(result),"delivered response records once")
	check(interaction.record(result) and brain.recall(person.id,"player-one").size()==1,"retried recording is idempotent")
	check(interaction.diagnostics[-1].usage.input==1234 and interaction.diagnostics[-1].usage.output==177,"telemetry retains provider-reported fixture counts exactly")
	check(interaction.diagnostics[-1].request_count==3,"request count includes moderation without inventing token measurements")
	var quiet:=utterance("")
	quiet.behavior={"mode":"disengage","intention":"Continue working without speaking."}
	quiet.nonverbal=["turn_away"]
	client.responses=[quiet]
	prepared=await interaction.prepare(client,person,"quiet-player",activity,"",{"initiate":true,"intention":"Decide whether to start a conversation."})
	result=await interaction.generate(client,prepared)
	check(result.source=="intentional_silence" and result.silent and result.line.is_empty() and result.nonverbal==["turn_away"],"an initiated turn can choose a separate nonverbal action without fabricated speech")
	interaction.record(result)
	check(mind.disengagement(person.id,"quiet-player").disengagement=="withdraw","a generated silent decision commits without a second emotional appraisal")
	var pending:=mind.observe(person,brain.relationship(person.id,"delayed-player"),"Hello",Time.get_ticks_msec(),"delayed-player","chat","delayed-perception")
	brain.remember_event(person,"delayed-player",pending,"Hello","",int(Time.get_unix_time_from_system()),"delayed-perception")
	check(brain.complete_event(person,"delayed-player","delayed-perception",""),"a heard event may complete with intentional silence")
	var sealed:=JSON.stringify(brain.relationship(person.id,"delayed-player"))
	check(brain.complete_event(person,"delayed-player","delayed-perception","") and JSON.stringify(brain.relationship(person.id,"delayed-player"))==sealed,"replayed silent completion cannot append duplicate episode text or updates")
	var first:="My best bench press is 287 pounds."
	client.responses=[utterance(first,"biography",[{"topic":"training.bench_press_record","detail":first,"value":"287 pounds","kind":"current","chronology":"last winter"}])]
	prepared=await interaction.prepare(client,person,"player-one",activity,"How much can you bench?")
	result=await interaction.generate(client,prepared)
	check(result.source=="ai","unseeded fictional personal detail is allowed")
	interaction.record(result)
	check(str(brain.character_biography(person).get("bench_press_pr","")).contains("287"),"new personal fact becomes globally established")
	var new_player:=brain.character_context(person,"player-two","What's the most you've ever benched?")
	check(JSON.stringify(new_player.personal_records).contains("287"),"another player's paraphrase retrieves the same character's fact")
	check(new_player.prior_turns.is_empty(),"other player's private transcript is not exposed")
	var calls_before:=client.model_calls
	client.responses=[utterance("My bench press record is 325 pounds.","biography"),utterance("My bench press record is still 287 pounds.","biography")]
	prepared=await interaction.prepare(client,person,"player-two",activity,"What did you get on bench?")
	result=await interaction.generate(client,prepared)
	check(result.source=="ai" and "325" not in str(result.line) and "287" in str(result.line),"spoken contradiction is repaired even with no proposed memory change")
	check(client.model_calls==calls_before+2,"contradiction repair is bounded to one additional generation")
	interaction.record(result)
	check(not JSON.stringify(brain.character_biography(person)).contains("325"),"rejected speech never becomes saved history")
	var denial:="I have never lifted weights."
	client.responses=[utterance(denial,"biography",[{"topic":"training.experience","detail":denial,"value":"never lifted","kind":"historical"}]),utterance("Bench press, 287 pounds.","biography")]
	client.reviews=[{"consistent":false,"reason":"The spoken denial contradicts the supplied training history."}]
	var reviews_before:=client.interpretations
	prepared=await interaction.prepare(client,person,"player-one",activity,"Have you trained before?")
	result=await interaction.generate(client,prepared)
	check(result.source=="ai" and result.line!=denial and client.interpretations==reviews_before+1,"a contradictory denial with a new valid-looking record receives deeper review and repair")
	check(Interaction._dossier_conflict_possible("My bench record is 400 pounds.",[{"text":"His bench record is 315 pounds. He also enjoys cycling."}],[{"topic":"bench.record"}]),"quantities already established in generated life prose are checked before a new ledger proposal")
	check(not Interaction._dossier_conflict_possible("My squat record is 400 pounds.",[{"text":"His bench record is 315 pounds."}],[{"topic":"squat.record"}]),"unrelated narrative quantities do not require an extra validation request")
	var invented:="You got 72 on the test."
	client.responses=[utterance(invented,"academic"),utterance(invented,"academic")]
	client.reviews=[{"consistent":false,"reason":"There is no verified test result."},{"consistent":false,"reason":"There is no verified test result."}]
	prepared=await interaction.prepare(client,person,"grade-player",activity,"How did my test go?")
	result=await interaction.generate(client,prepared)
	check(result.source=="technical_unavailable" and result.line.is_empty(),"unsupported spoken academic outcome is rejected even without a memory or grade update")
	check(Interaction._needs_gameplay_review("You called me useless in yesterday's lab.") and Interaction._needs_gameplay_review("You mocked me last class."),"generic past-event scope covers paraphrased accusations without exact question checks")
	var late_fact:="I learned the glockenspiel at college."
	var delivery_guard:={"valid":true}
	client.responses=[utterance(late_fact,"biography",[{"topic":"music.training","detail":late_fact,"value":"glockenspiel","kind":"historical"}])]
	prepared=await interaction.prepare(client,person,"late-player",activity,"What instrument did you study?",{"_valid":func():return delivery_guard.valid})
	result=await interaction.generate(client,prepared)
	delivery_guard.valid=false
	check(not interaction.record(result,true) and not brain.character_biography(person).has("music.training"),"a guard invalidated after generation still prevents unheard personal facts at commit")
	var squat:="My best squat is 391 pounds."
	var independent:={"topic":"training.squat_record","detail":squat,"value":"391 pounds","kind":"current"}
	check(Life.speech_check(squat,brain.character_life_records(person),[independent],true).ok,"shared generic topic does not confuse different personal records")
	var permanent:={"topic":"childhood.job","detail":"I worked at a corner bakery when I was eighteen.","value":"corner bakery","kind":"historical"}
	check(brain.validate_life_details(person,permanent.detail,[permanent]).ok,"new historical experience is expandable")
	var forbidden:={"topic":"childhood.story","detail":"I remember you completed yesterday's test."}
	check(not brain.validate_life_details(person,forbidden.detail,[forbidden]).ok,"fictional life cannot fabricate gameplay by using an innocent topic name")
	var food:={"topic":"food.favorite","detail":"My favourite food is noodles.","value":"noodles","kind":"preference"}
	var stored:={}
	Life.apply(stored,Life.validate(food,food.detail,stored))
	var changed:={"topic":"food.favorite","detail":"My favourite food is dumplings now.","value":"dumplings","kind":"preference","revision":"update","reason":"I got tired of the same lunch."}
	var checked:=Life.validate(changed,changed.detail+" "+changed.reason,stored)
	check(checked.ok,"a changing preference requires a spoken reason")
	Life.apply(stored,checked)
	check(stored["food.favorite"].history.size()==1 and stored["food.favorite"].history[0].value=="noodles","old preferences remain in chronological history")
	check(Knowledge.assess(person,activity,"What's your training history?",{"question_kind":"biography","domain":"fitness"}).allowed,"own biography is independent of specialist knowledge gates")
	var hostile:=Profiles.teacher("brian")
	for index in 3:
		var interpreted:={"event":"insult","tone":"hostile","severity":.9,"behavior":{"mode":"permanent_silence","intention":"End this repeatedly hostile relationship"}}
		mind.observe(hostile,{},"You are useless.",Time.get_ticks_msec(),"hostile-player","insult","hostility-"+str(index),interpreted)
	check(mind.disengagement(hostile.id,"hostile-player").disengagement=="permanent","a grounded permanent silent-treatment decision is represented")
	brain.memory_dirty=true
	check(brain.save_memory()==OK,"dossier-era memory including persistent disengagement saves")
	var reloaded:=Brain.new();reloaded.set_host_profile(fixture_profile);reloaded.load_memory()
	var restored:=Mind.new();reloaded.bind_mind(restored)
	check(restored.disengagement(hostile.id,"hostile-player").disengagement=="permanent","silent treatment survives reconstruction from disk")
	check(reloaded.character_biography(person)==brain.character_biography(person),"established personal information survives reload")
	var later:=Interaction.new();later.bind(restored,reloaded)
	calls_before=client.model_calls
	prepared=await later.prepare(client,hostile,"hostile-player",activity,"I'm sorry. Let's discuss something different.")
	result=await later.generate(client,prepared)
	check(result.source=="intentional_silence" and str(result.line).is_empty(),"apology/topic change does not automatically clear permanent disengagement")
	check(client.model_calls==calls_before,"persistent silence needs no provider request")
	client.available=false
	prepared=await later.prepare(client,person,"new-player",activity,"What's up?")
	result=await later.generate(client,prepared)
	check(result.source=="technical_unavailable" and result.line=="" and result.has("technical_status"),"service outage remains explicit technical state without canned character speech")
	var before:=restored.export_state()
	prepared=await later.prepare(client,person,"new-player",activity,"Hello",{"_valid":func():return false})
	result=await later.generate(client,prepared)
	check(result.get("cancelled",false) and restored.export_state()==before,"cancelled request does not mutate character affect")
	print("CHARACTER_DOSSIER_PIPELINE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," source=synthetic provider contract; no live language-quality or token-performance claim")
	client.queue_free()
	quit(0 if failures.is_empty() else 1)
