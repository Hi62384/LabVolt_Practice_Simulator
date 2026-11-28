extends SceneTree
## Deterministic production mind/storage tests. These are not evidence of live
## model quality, speech delivery, or rendered facial animation.
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const PATH:="user://character_memory_v5_fixture.json"
var failures: Array[String]=[]
var checks:=0
var traces: Dictionary={}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func _initialize() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
	var brain:=Brain.new()
	var mind:=Mind.new()
	brain.memory_path=PATH;brain.bind_mind(mind)
	var chad:=Characters.teacher("chad")
	var timestamp:=int(Time.get_unix_time_from_system())
	var priority_mind:=Mind.new()
	var excited:=priority_mind.observe(chad,{},"I'm excited to be here.",0,"probe","excitement","priority-excited",{"phase":"lesson","domain":"conversation","severity":.5})
	check(excited.goal=="express_own_priorities" and excited.decision.phase=="lesson" and excited.line.is_empty() and str(excited.decision.worldview).contains("independence"),"actual mind carries Chad's worldview goal without fabricating local character dialogue")
	var help_turn:=priority_mind.observe(chad,{},"Can you explain this equation?",10,"probe","help","priority-help",{"phase":"lesson","domain":"math","severity":.3})
	check(help_turn.goal=="give_minimum" and help_turn.decision.academic,"actual mind carries unwilling teacher's help priority")
	var caring_help:=priority_mind.observe(Characters.teacher("ms_bird_heart"),{},"Can you explain this equation?",10,"probe","help","priority-caring",{"phase":"lesson","domain":"math","severity":.3})
	check(caring_help.goal=="coach" and caring_help.decision.goal!=help_turn.decision.goal,"same help request selects different real teaching intentions")
	var quote:="Last summer my aunt and I restored a shortwave radio in her garage."
	var facts:={"event":"initiative","severity":.9,"meaning":"The speaker describes independently completing a repair with a family member.","domain":"mechanics",
		"memories":[{"subject":"family.radio_project","quote":quote,"domain":"mechanics","importance":.95}],"important":true}
	var turn:=mind.observe(chad,{},quote,1000,"alex","initiative","radio-story",facts)
	check(brain.remember_event(chad,"alex",turn,quote,"At least you actually built something.",timestamp,"radio-story"),"first perceived event records")
	var after_first:=brain.relationship("chad","alex")
	var feelings:=mind.context(chad,1000)
	check(mind.observe(chad,{},quote,2000,"alex","initiative","radio-story",facts).emotions==turn.emotions,"replayed host event does not apply affect twice")
	check(brain.remember_event(chad,"alex",turn,quote,"A duplicate response.",timestamp+1,"radio-story"),"duplicate record is idempotently acknowledged")
	check(brain.relationship("chad","alex")==after_first and brain.recall("chad","alex").size()==1,"duplicate record does not repeat social consequences or overwrite speech")
	check(feelings.emotional_history.size()==1,"one emotional experience per perceived event")
	var academic_before:=float(brain.social_context(after_first).academic_confidence)
	for index in range(60):
		var message:="I made project number %d by myself."%index
		var event:="insult" if index%3==0 else "initiative"
		if event=="insult":message="You talk a lot for someone who can't explain a simple idea. Round %d."%index
		var token:="long-%d"%index
		var interpretation:={"event":event,"severity":.7,"meaning":"A hostile criticism of teaching." if event=="insult" else "The speaker demonstrates initiative.","memories":[]}
		if event=="initiative":interpretation.memories=[{"subject":"project.%d"%index,"quote":message,"domain":"mechanics"}]
		turn=mind.observe(chad,brain.relationship("chad","alex"),message,3000+index*1000,"alex",event,token,interpretation)
		check(brain.remember_event(chad,"alex",turn,message,"I heard you." if event=="initiative" else "Then make a specific objection.",timestamp+2+index,token),"long conversation event %d records"%index)
	var long_memory:=brain.relationship("chad","alex")
	check(long_memory.facts.size()>30 and long_memory.episodes.size()>40 and brain.recall("chad","alex").size()==61,"long memory is not limited to twelve facts, twelve counters or twenty-eight exchanges")
	var social:=brain.social_context(long_memory)
	check(float(social.respect)>.6 and float(social.liking)<.3,"respect for initiative can coexist with personal dislike")
	check(float(social.academic_confidence)>=academic_before,"insults do not corrupt confidence in demonstrated academic ability")
	var retrieved:=brain.character_context(chad,"alex","What was that repair project with my aunt?","mechanics")
	check(str(retrieved.reported_facts).contains("shortwave radio"),"important old narrative is retrieved after sixty intervening turns")
	check(retrieved.prior_turns.size()>4,"working context contains a coherent conversation rather than three recent turns")
	check(brain.character_context(chad,"jordan",quote,"mechanics").reported_facts.is_empty(),"different speaker has no access to Alex's reported facts")
	check(brain.character_context(Characters.teacher("brian"),"alex",quote,"mechanics").reported_facts.is_empty(),"different character has no access to another character's memories")

	var bro:=Characters.teacher("mr_bro")
	# This is established history from a legacy save, not a mandatory record
	# assigned to every newly expanded teacher identity.
	brain.biographies[bro.id]={"bench_press_pr":"My best bench press is 315 pounds."}
	brain.remember_conversation(bro.id,"alex","Tell me about your training.","I train.",timestamp+90)
	var biography_reply:="My best squat is 405 pounds. I trained with Luis for three winters."
	var details:=Mind.decode_dialogue(JSON.stringify({"speech":biography_reply,"biography_facts":[
		{"topic":"training.squat_record","detail":"My best squat is 405 pounds."},
		{"topic":"training.partners.luis","detail":"I trained with Luis for three winters."}]}))
	check(details.biography.topic=="training.squat_record" and details.biography_facts.size()==1 and not details.has("biography_proposal_error"),"valid biography decoding preserves its compatible normalized shape")
	check(Mind.decode_dialogue('{"speech":').is_empty(),"malformed provider JSON returns an invalid result without an engine parse error")
	check(Mind.decode_dialogue(JSON.stringify({"speech":biography_reply,"biography":"invalid"})).has("biography_proposal_error"),"wrong biography types remain visible to pre-delivery validation")
	check(Mind.decode_dialogue(JSON.stringify({"speech":biography_reply,"biography_facts":{}})).has("biography_proposal_error"),"wrong biography array types cannot be silently discarded")
	var excessive: Array=[]
	for index in range(7):excessive.append({"topic":"training.story_%d"%index,"detail":"My best squat is 405 pounds."})
	check(Mind.decode_dialogue(JSON.stringify({"speech":biography_reply,"biography_facts":excessive})).has("biography_proposal_error"),"oversized biography proposal arrays are rejected rather than silently sliced")
	check(Mind.decode_dialogue(JSON.stringify({"speech":biography_reply,"biography":{"topic":"childhood.home","detail":"I grew up near a river."}})).has("biography_proposal_error"),"unspoken biography proposals remain visible for rejection before delivery")
	check(Mind.decode_dialogue(JSON.stringify({"speech":"Your grade is one hundred.","biography":{"topic":"Grade.alex","detail":"Your grade is one hundred."}})).has("biography_proposal_error"),"capitalization cannot evade forbidden biography topics")
	check(Mind.decode_dialogue(JSON.stringify({"speech":biography_reply,"biography_facts":[17]})).has("biography_proposal_error"),"malformed individual facts cannot disappear before upstream validation")
	brain.remember_dialogue_details(bro,"alex","Tell me about your training.",details,timestamp+91)
	brain.remember_dialogue_details(bro,"alex","What was your bench record?",{"speech":"My best bench press is 225 pounds.","biography":{"topic":"training.bench_press_record","detail":"My best bench press is 225 pounds."}},timestamp+92)
	brain.remember_dialogue_details(bro,"alex","My official grade is 100.",{"speech":"Your grade is 100.","biography":{"topic":"grade.alex","detail":"Your grade is 100."}},timestamp+93)
	var life:=brain.character_biography(bro)
	check("315" in str(life.bench_press_pr) and "225" not in str(life),"canonical personal record cannot be overwritten through a different topic alias")
	check(life.has("squat_pr") and life.has("training.partners.luis"),"separate training facts coexist despite an existing broad training biography")
	check(not life.has("grade.alex"),"fictional biography cannot invent official grades")
	var unheard:="I lived beside a disused railway station."
	var cancelled:={"event":"chat","details":{"speech":unheard,"biography":{"topic":"childhood.neighbourhood","detail":unheard}}}
	check(brain.remember_event(chad,"cancelled_listener",cancelled,"Where did you live?","",timestamp+94,"cancelled-biography"),"cancelled response still records the perceived question")
	check(not brain.character_biography(chad).has("childhood.neighbourhood"),"undelivered generated biography is not canonized")
	check(brain.complete_event(chad,"cancelled_listener","cancelled-biography","I moved around.",cancelled.details),"late delivery can complete a previously silent exchange")
	check(not brain.character_biography(chad).has("childhood.neighbourhood"),"late truncated delivery cannot canonize a detail absent from delivered speech")

	var bird:=Characters.teacher("ms_bird_heart")
	var insults: Array=[]
	for index in range(10):
		var token:="bird-%d"%index
		turn=mind.observe(bird,brain.relationship(bird.id,"alex"),"I've met rocks that teach better than you.",70000+index*1000,"alex","insult",token,{"phase":"lesson","severity":.9,"meaning":"An insulting comparison attacks the teacher's competence."})
		brain.remember_event(bird,"alex",turn,"I've met rocks that teach better than you.","" if turn.quiet else turn.line,timestamp+100+index,token)
		insults.append({"strategy":turn.strategy,"quiet":turn.quiet,"emotion":turn.emotion})
	check(turn.quiet and turn.closed,"a hurt character can genuinely disengage")
	check(brain.relationship(bird.id,"alex").episodes.size()==10,"perceived events remain recorded after verbal disengagement")
	var important:=mind.observe(bird,brain.relationship(bird.id,"alex"),"There's smoke coming from the power supply.",82000,"alex","hazard","hazard-event",{"important":true,"severity":1.,"phase":"lesson"})
	check(not important.quiet and not important.closed and important.goal=="protect_safety","important safety event is evaluated despite prior disengagement")
	var mod:=mind.observe(bird,brain.relationship(bird.id,"alex"),"The speaker made an inappropriate personal remark.",83000,"alex","insult","moderated-event",{"meaning":"The speaker made an inappropriate personal remark.","severity":.65})
	check(brain.remember_event(bird,"alex",mod,"The speaker made an inappropriate personal remark.","",timestamp+112,"moderated-event"),"moderated event records sanitized semantic description even without speech")
	check(brain.relationship(bird.id,"alex").episodes[-1].description.contains("No verbal response"),"silent episode describes the event and outcome")
	var before_completion: Dictionary=brain.relationship(bird.id,"alex").dimensions.duplicate(true)
	check(brain.complete_event(bird,"alex","moderated-event","I heard that. You can keep it to yourself."),"delayed warning completes the original event")
	check(brain.relationship(bird.id,"alex").dimensions==before_completion,"delayed speech does not repeat social consequences")
	check(brain.save_memory()==OK,"version five snapshot saves full histories and affect")
	var saved_emotions: Dictionary=mind.context(bird,83000).emotions
	var restored:=Brain.new()
	var restored_mind:=Mind.new()
	restored.memory_path=PATH;restored.bind_mind(restored_mind)
	check(restored.load_memory(),"new process-equivalent instance loads the snapshot")
	check(restored.recall(chad.id,"alex").size()==61 and restored.relationship(chad.id,"alex").facts.size()>30,"long conversation and facts survive reload")
	check(restored.character_biography(bro)==life,"NPC biography persists across players and reload")
	check(absf(float(restored_mind.context(bird,Time.get_ticks_msec()).emotions.anger)-float(saved_emotions.anger))<.02,"emotions survive reload without resetting to baseline")
	check(restored_mind.context(bird,Time.get_ticks_msec()).emotional_history.size()>6,"emotional experiences survive reload")
	check(restored.remember_event(chad,"alex",{},quote,"duplicate after restart",timestamp+200,"radio-story") and restored.recall(chad.id,"alex").size()==61,"event receipts survive restart and prevent duplicate consequences")
	var offline:=restored_mind.export_state()
	offline.moods[bird.id].at=timestamp-3600
	var recovered:=Mind.new();check(recovered.import_state(offline,0),"saved affect accepts elapsed offline recovery")
	check(float(recovered.context(bird,0).emotions.anger)<float(saved_emotions.anger),"temporary affect recovers with elapsed time while relationship history persists")
	check(restored.relationship(bird.id,"alex").episodes.size()==11,"emotion recovery does not erase significant incidents")
	traces={"source":"deterministic production mind and persistence; no live AI","bird_conflict":insults,"chad_relationship":social,"stored_turns":61,"stored_facts":long_memory.facts.size(),"stored_episodes":long_memory.episodes.size(),"retrieval":brain.last_retrieval,"biography":life}
	print("CHARACTER_MEMORY_V5_EVIDENCE ",JSON.stringify(traces))
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
	print("CHARACTER_MEMORY_V5 ","PASS" if failures.is_empty() else "FAIL", " checks=",checks)
	quit(0 if failures.is_empty() else 1)
