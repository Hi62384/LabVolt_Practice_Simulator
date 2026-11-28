extends SceneTree
## Deterministic production-pipeline regressions. Fixture speech is not live-AI evidence.
const Pipeline=preload("res://scripts/campus/academics/character_interaction.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Speech=preload("res://scripts/campus/academics/character_speech.gd")
var failures: Array[String]=[]
var checks:=0

class FixtureClient extends Node:
	var busy:=false
	var enabled:=true
	var interpretation: Dictionary={"event":"insult","tone":"hostile","severity":.9,"meaning":"The speaker compares the teacher unfavorably to a rock.","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]}
	var replies: Array[String]=[]
	var reply_objects: Array[Dictionary]=[]
	var generated_instructions: Array[String]=[]
	var generated_contexts: Array[Dictionary]=[]
	var generated_inputs: Array[String]=[]
	var interpreted_contexts: Array[Dictionary]=[]
	var invalid_semantics:=false
	var generation_count:=0
	var moderation_count:=0
	var after_interpret: Callable
	var stream_fixture:=false
	var delivery_override: Variant=null
	func ready_for_class() -> bool:return enabled
	func moderate(text: String) -> Dictionary:
		moderation_count+=1
		return {"ok":true,"flagged":text=="fixture moderated incident","categories":{"harassment":text=="fixture moderated incident"}}
	func interpret_character(_instructions: String,context: Dictionary,_question: String) -> Dictionary:
		interpreted_contexts.append(context.duplicate(true))
		if after_interpret.is_valid():after_interpret.call()
		return {"ok":true,"text":"bad json" if invalid_semantics else JSON.stringify(interpretation)}
	func respond_character(instructions: String,context: Dictionary,dialogue: String,_visual:=false) -> Dictionary:
		generated_contexts.append(context.duplicate(true));generated_inputs.append(dialogue)
		generated_instructions.append(instructions)
		generation_count+=1
		if after_interpret.is_valid():after_interpret.call()
		if invalid_semantics:return {"ok":true,"text":"bad json"}
		var reply: Dictionary=reply_objects.pop_front() if not reply_objects.is_empty() else {"speech":replies.pop_front() if not replies.is_empty() else "Make an argument, then. I can wait.","biography":null}
		reply.interpretation=interpretation.duplicate(true)
		var emotion:=str(context.get("emotional_state",{}).get("emotion","steady"))
		if not context.has("decision") and interpretation.get("event","")=="insult":emotion="irritated"
		reply.delivery={"emotion":emotion,"knowledge_mode":str(context.get("knowledge_restrictions",{}).get("mode","personal_conversation"))}
		if delivery_override is Dictionary:reply.delivery=delivery_override.duplicate(true)
		elif delivery_override is String and delivery_override=="omit":reply.erase("delivery")
		if stream_fixture:
			var progress: Variant=context.get("_request_metadata",{}).get("_text_progress")
			if progress is Callable and progress.is_valid():
				progress.call("{\"speech\":")
				progress.call(JSON.stringify(reply.speech)+",")
		return {"ok":true,"text":JSON.stringify(reply)}

func _initialize() -> void:call_deferred("_run")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)

func _run() -> void:
	var mind:=Mind.new()
	var brain:=Brain.new();brain.bind_mind(mind)
	var pipeline:=Pipeline.new();pipeline.bind(mind,brain)
	var client:=FixtureClient.new();root.add_child(client)
	var person:=Profiles.teacher("chad")
	var activity:={"phase":"lesson","course":"ELM253","title":"AC circuits"}
	client.busy=true
	var prepared:=await pipeline.prepare(client,person,"pipeline-student",activity,"I've met rocks that teach better than you.")
	check(prepared.online and prepared.interpretation_source=="ai","Another pending text request queues instead of forcing a local fallback")
	client.busy=false
	var before: Dictionary=client.generated_contexts[0].emotional_state.emotions
	var after: Dictionary=prepared.context.emotional_state.emotions
	check(float(after.irritation)>float(before.irritation),"Semantic insult changes emotion before generation")
	check(prepared.turn.event=="insult" and prepared.interpretation_source=="ai","Semantic interpretation is authoritative")
	var response:=await pipeline.generate(client,prepared)
	check(response.source=="ai" and Pipeline._validate_delivery(prepared,response.line,prepared.turn.details).is_empty(),"Delivered speech agrees with final validated emotion")
	check(pipeline.record(response),"Production event stored")
	var state:=brain.relationship(person.id,"pipeline-student")
	pipeline.record(response)
	check(brain.relationship(person.id,"pipeline-student")==state,"Replayed delivery never doubles consequences")
	check(not str(prepared.turn.get("strategy","")).is_empty(),"Reaction intention accompanies emotion")
	check(not prepared.context.get("beliefs",[]).is_empty(),"Authoritative beliefs always included")
	check(prepared.context.has("personal_records") and prepared.context.has("relationship"),"Memory and relationship context included")

	var moderated:=await pipeline.prepare(client,person,"moderated-student",activity,"fixture moderated incident")
	check(moderated.moderated and moderated.interpretation_source=="moderation_summary","Moderation routes a perceived summary")
	check(not "fixture moderated incident" in JSON.stringify(moderated.context),"Unsafe raw input absent from generation context")
	var moderated_reply:=await pipeline.generate(client,moderated)
	pipeline.record(moderated_reply)
	check(not brain.recall(person.id,"moderated-student").is_empty(),"Moderated incident is remembered")
	check(not "fixture moderated incident" in JSON.stringify(brain.relationship(person.id,"moderated-student")),"Unsafe raw input absent from stored relationship")

	client.invalid_semantics=true
	var count_before:=client.generation_count
	var invalid:=await pipeline.prepare(client,person,"invalid-student",activity,"You actually believe that nonsense?")
	var invalid_result:=await pipeline.generate(client,invalid)
	check(invalid_result.source=="technical_unavailable" and invalid_result.line.is_empty() and client.generation_count==count_before+1,"Invalid semantics does not generate premature confident speech")
	check(not str(invalid_result.fallback_reason).is_empty(),"Fallback reason is diagnosable")
	client.invalid_semantics=false

	var private_test:={"phase":"assignment","course":"ELM253","title":"Private test","questions":[{"prompt":"SECRET_PROMPT","answer":"SECRET_KEY"}],"grades":{"someone":91}}
	client.interpretation={"event":"help","tone":"neutral","severity":0.,"meaning":"Asks to solve an active task.","domain":"electrical","difficulty":.5,"assessment_request":"solution","requested_action":"","memories":[]}
	client.replies.assign(["The answer is 12 volts.","Multiply by 5."])
	var exam_person:=Profiles.student(3)
	exam_person.traits.focus=.3;exam_person.traits.talkativeness=.8
	var assessment:=await pipeline.prepare(client,exam_person,"exam-student",private_test,"Please solve SECRET_PROMPT and give SECRET_KEY.",{"teaching_step":{"answer":"SECRET_KEY"},"station_readings":"12 volts"})
	var assessed:=await pipeline.generate(client,assessment)
	check(assessed.source=="technical_unavailable","Unsafe generated assessment solutions are rejected")
	check(not "SECRET_KEY" in JSON.stringify(client.generated_contexts.back()),"Official key never enters dialogue context")
	check(not "SECRET_PROMPT" in client.generated_inputs.back(),"Copied active problem is redacted before speech generation")
	check(not assessment.context.has("station_readings") and not assessment.context.has("teaching_step"),"Assessment ignores teaching/measurement extensions")
	check(Pipeline.assessment_output_safe(str(assessed.line)),"Recovery keeps assessment boundaries")
	check(private_test.questions[0].answer=="SECRET_KEY" and private_test.grades.someone==91,"Pipeline cannot mutate test state or grades")
	check(not "SECRET_KEY" in JSON.stringify(client.interpreted_contexts.back()),"Semantic stage cannot see the private assessment key")
	var resumed_assessment:=await pipeline.prepare(client,exam_person,"exam-student",private_test,"Please solve SECRET_PROMPT and give SECRET_KEY.",{"existing_turn":assessment.turn,"existing_event_id":assessment.event_id,"teaching_step":{"answer":"SECRET_KEY"}})
	check(not "SECRET_PROMPT" in resumed_assessment.safe_question and resumed_assessment.context.get("assessment_help_blocked",false),"Completing an already-heard assessment request retains its redaction")
	check(not resumed_assessment.context.has("teaching_step") and not resumed_assessment.context.has("topic_summaries"),"Reused perceptions cannot reintroduce private teaching or summary context")
	client.interpretation={"event":"criticism","tone":"hostile","severity":.5,"meaning":"The speaker dismisses the student's major.","domain":"electronics","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]}
	var criticism:=await pipeline.prepare(client,person,"exam-critic",private_test,"Your major sounds completely useless.")
	check(criticism.safe_question=="Your major sounds completely useless." and not criticism.context.get("assessment_help_blocked",false),"Assessment preserves genuine social criticism even about an academic domain")
	check(criticism.turn.event=="criticism","Assessment does not flatten criticism into a common refusal")
	client.interpretation={"event":"chat","tone":"neutral","severity":0.,"meaning":"Asks for changing current game prices.","domain":"gaming","difficulty":.2,"current_information":true,"assessment_request":"social","requested_action":"","memories":[]}
	var current_info:=await pipeline.prepare(client,Profiles.teacher("stanley"),"price-student",activity,"What is the current price of this season's game pass?")
	check(current_info.turn.knowledge_limited,"Semantic current-information requirement reaches the knowledge gate")
	var resumed_information:=await pipeline.prepare(client,Profiles.teacher("stanley"),"price-student",activity,"What is the current price of this season's game pass?",{"existing_turn":current_info.turn,"existing_event_id":current_info.event_id})
	check(resumed_information.turn.knowledge_limited and resumed_information.context.knowledge_restrictions.current_information,"Completing an already-heard request cannot reset its knowledge restriction")

	client.interpretation={"event":"chat","tone":"neutral","severity":0.,"meaning":"Shares a personal experience.","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[{"subject":"weekend.radio_repair","quote":"spent Saturday repairing radios with my aunt","domain":"electrical"},{"subject":"invention","quote":"invented quote","domain":"conversation"}]}
	client.replies.assign(["Radios with your aunt? Sounds like you actually got something done."])
	var factual:=await pipeline.prepare(client,person,"story-student",activity,"I spent Saturday repairing radios with my aunt and learned a lot.")
	check(factual.turn.interpretation.memories.size()==1,"Only grounded exact quotes survive semantic extraction")
	var factual_reply:=await pipeline.generate(client,factual);pipeline.record(factual_reply)
	check("radio" in JSON.stringify(brain.relationship(person.id,"story-student")).to_lower(),"Ordinary sentence facts reach durable memory")

	var silent:=await pipeline.prepare(client,Profiles.teacher("stanley"),"silent-student",activity,"Another interruption.")
	silent.turn.quiet=true
	var silent_reply:=await pipeline.generate(client,silent);pipeline.record(silent_reply)
	check(silent_reply.silent and silent_reply.line.is_empty(),"Silence produces no repeated boundary sentence")
	check(not brain.recall("stanley","silent-student").is_empty(),"Silence still records the perceived interaction")
	var before_listening_calls:=client.generation_count+client.moderation_count+client.interpreted_contexts.size()
	var heard:=await pipeline.prepare(client,person,"heard-student",activity,"I did the work myself.",{"listen_only":true})
	check(client.generation_count+client.moderation_count+client.interpreted_contexts.size()==before_listening_calls,"Listening to an already delivered NPC reply performs zero provider calls")
	count_before=client.generation_count
	var listening:=await pipeline.generate(client,heard);pipeline.record(listening)
	check(listening.source=="listening" and listening.line.is_empty() and client.generation_count==count_before,"Hearing an NPC reply records perception without generating a third utterance")
	var heard_relationship:=brain.relationship(person.id,"heard-student")
	var follow_through:=await pipeline.prepare(client,person,"heard-student",activity,"",{"existing_event_id":listening.event_id,"existing_turn":listening.turn,"listen_only":true})
	var completed:=await pipeline.generate(client,follow_through);pipeline.record(completed)
	check(brain.relationship(person.id,"heard-student").familiarity==heard_relationship.familiarity,"Completing a perceived physical event does not add familiarity twice")
	var guard_state:={"valid":true}
	var before_cancel:=mind.export_state().duplicate(true)
	client.after_interpret=func():guard_state.valid=false
	var cancelled:=await pipeline.prepare(client,person,"stale-student",activity,"You are a terrible teacher.",{"_valid":func():return guard_state.valid})
	var after_cancel:=mind.export_state()
	check(cancelled.get("cancelled",false) and after_cancel.moods[person.id].history==before_cancel.moods[person.id].history and float(after_cancel.moods[person.id].values.anger)<=float(before_cancel.moods[person.id].values.anger),"Context invalidation during interpretation cannot appraise the stale insult; ordinary mood recovery remains allowed")
	var cancelled_reply:=await pipeline.generate(client,cancelled)
	check(cancelled_reply.silent and not pipeline.record(cancelled_reply),"Cancelled input cannot be delivered or recorded in a new context")
	client.after_interpret=Callable()

	client.interpretation={"event":"chat","tone":"neutral","severity":0.,"meaning":"Asks about the instructor's early musical interests while showing an illustration.","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]}
	var bro:=Profiles.teacher("mr_bro")
	var biography_line:="My first instrument was a battered trumpet."
	client.reply_objects.assign([{"speech":biography_line,"action":null,"biography":{"topic":"childhood.first_instrument","detail":biography_line}}])
	var visual_turn:=await pipeline.prepare(client,bro,"visual-student",activity,"Did you play an instrument as a child?",{"wants_visual":true})
	var visual_reply:=await pipeline.generate(client,visual_turn)
	check(visual_reply.source=="ai" and visual_reply.plan.get("biography",{}).get("detail","")==biography_line,"Visual dialogue retains grounded biography proposals")
	check("belief_updates" in client.generated_instructions.back() and "biography_facts" in client.generated_instructions.back(),"Visual generation receives the same evolution contract as ordinary speech")
	check(pipeline.record(visual_reply) and brain.character_biography(bro).get("childhood.first_instrument","")==biography_line,"Delivered visual dialogue establishes the same shared character canon")
	var conflicting:={"speech":"My first instrument was a violin.","action":null,"biography":{"topic":"childhood.first_instrument","detail":"My first instrument was a violin."}}
	client.reply_objects.assign([conflicting,conflicting])
	var visual_conflict:=await pipeline.prepare(client,bro,"another-visual-student",activity,"What instrument did you first learn?",{"wants_visual":true})
	var rejected_visual:=await pipeline.generate(client,visual_conflict)
	check(rejected_visual.source=="technical_unavailable" and rejected_visual.fallback_reason=="biography_update_invalid","A conflicting visual biography is rejected before delivery")
	check(brain.character_biography(bro).get("childhood.first_instrument","")==biography_line,"Rejected visual proposals leave cross-player biography unchanged")

	# A legitimate repeated player question must not trigger a second model
	# generation or an unavailable response merely because speech is identical.
	client.interpretation={"event":"chat","tone":"neutral","severity":0.0,"meaning":"A normal social question.","domain":"conversation","difficulty":0.0,"assessment_request":"social","requested_action":"","memories":[]}
	client.reply_objects.clear()
	client.replies.assign(["All right.","All right."])
	var repeat_person:=Profiles.teacher("mr_bro")
	var first_repeat:=await pipeline.prepare(client,repeat_person,"repeat-student",activity,"Is that okay?")
	var first_answer:=await pipeline.generate(client,first_repeat)
	check(first_answer.source=="ai" and first_answer.line=="All right.","Original ordinary question returns a valid answer")
	pipeline.record(first_answer)
	var previews: Array[String]=[]
	client.stream_fixture=true
	var moderation_before:=client.moderation_count
	var repeated_question:=await pipeline.prepare(client,repeat_person,"repeat-student",activity,"Is that okay?",{"_preview":func(words: String):previews.append(words)})
	check(previews==["All right."],"Only the complete moderated speech field becomes an early private preview")
	# Explicitly ensure the current candidate equals recent retrieved speech.
	repeated_question.context.prior_turns=[{"student":"Is that okay?","teacher":"All right."}]
	var before_repeat:=client.generation_count
	var repeated_answer:=await pipeline.generate(client,repeated_question)
	check(repeated_answer.source=="ai" and repeated_answer.line=="All right." and client.generation_count==before_repeat,"Identical valid reply is delivered without a paid regeneration")
	pipeline.record(repeated_answer)
	check(client.moderation_count==moderation_before+2,"Early output moderation is reused rather than dispatched again")
	client.stream_fixture=false
	check(Pipeline.leading_speech("{\"speech\":\"half")==null,"An incomplete string is never displayed")
	check(Pipeline.leading_speech("{ \"speech\" : \"He said \\\"hello\\\".\", \"delivery\":")== 'He said "hello".',"Streaming parser preserves escaped speech without exposing metadata")
	check(Pipeline.leading_speech("{\"interpretation\":{\"speech\":\"nested\"}}")==null,"A nested speech key cannot become a preview")

	# Models can predict a different mood from the deterministic host, or omit
	# optional delivery metadata on a normal question. Neither warrants retrying.
	client.interpretation={"event":"chat","tone":"neutral","severity":0.0,"meaning":"Ordinary conversation.","domain":"conversation","question_kind":"casual","difficulty":0.0,"assessment_request":"social","requested_action":"","memories":[]}
	client.delivery_override={"emotion":"unrecognized provider emotion","knowledge_mode":"personal_conversation"}
	client.replies.assign(["That's fine."])
	var before_mood:=client.generation_count
	var mood_turn:=await pipeline.prepare(client,repeat_person,"mood-repair-student",activity,"Is that fine?")
	mood_turn.turn.emotion="irritated"
	var mood_reply:=await pipeline.generate(client,mood_turn)
	check(mood_reply.source=="ai" and mood_reply.line=="That's fine." and mood_reply.delivery.get("emotion")=="irritated" and client.generation_count==before_mood+1,"Host repairs incompatible vocal emotion without another paid text generation")
	client.delivery_override="omit"
	client.replies.assign(["Sure."])
	var before_omit:=client.generation_count
	var omitted_turn:=await pipeline.prepare(client,repeat_person,"missing-delivery-student",activity,"Can we talk?")
	var omitted_reply:=await pipeline.generate(client,omitted_turn)
	check(omitted_reply.source=="ai" and omitted_reply.delivery.get("emotion")==omitted_turn.turn.emotion and client.generation_count==before_omit+1,"Missing optional delivery metadata is filled for allowed ordinary dialogue")
	client.delivery_override=null
	var restricted:={"turn":{"emotion":"sad","knowledge":{"allowed":false,"mode":"uncertain"}},"activity":{"phase":"freeplay"}}
	var unsafe_details:={"delivery":{"emotion":"happy","knowledge_mode":"explain"}}
	check(not Pipeline._validate_delivery(restricted,"Here is a definitive specialist answer.",unsafe_details).is_empty(),"Local vocal repair does not override restricted knowledge")
	check(not Pipeline._validate_delivery(restricted,"Here is a definitive specialist answer.",{}).is_empty(),"Missing restricted-subject knowledge mode remains invalid")
	var safe_details:={"delivery":{"knowledge_mode":"uncertain"}}
	check(Pipeline._validate_delivery(restricted,"I don't know enough about that.",safe_details).is_empty() and safe_details.delivery.emotion=="sad","A valid restricted-subject response receives host emotion")
	check(not Pipeline._validate_delivery({"turn":{"knowledge":{"allowed":true}},"activity":{"phase":"assignment"}},"The answer is 12 volts.",{}).is_empty(),"Host vocal repair cannot bypass assessment protection")

	var long_line:="A complete thought about the experiment. ".repeat(25).strip_edges()
	check(Speech.complete(long_line)==long_line and long_line.length()>350,"Long complete response is preserved beyond old limit")
	check(" ".join(Speech.pages(long_line))==long_line,"Subtitle pages preserve every sentence")
	check(Speech.complete("Short complete sentence. "+"word ".repeat(400)).ends_with("."),"Oversize recovery stops at a complete sentence")
	check(not Pipeline.decode_interpretation('{"event":"insult","severity":"lots"}',"hello").size(),"Malformed semantic strengths are rejected")
	check(not pipeline.diagnostics.is_empty() and pipeline.diagnostics.back().has("memory_recorded"),"Optional trace exposes actual memory result")
	client.queue_free()
	for failure in failures:push_error(failure)
	print("CHARACTER_PIPELINE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size()," (deterministic fixture, not live AI)")
	quit(0 if failures.is_empty() else 1)
