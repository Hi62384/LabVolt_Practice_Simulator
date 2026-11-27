extends SceneTree
## Native production persistence -> fresh Brain/Mind -> Pipeline.prepare test.
## Host outcome entry points are real; no provider output or live-AI claim is
## needed to observe the change in the character's knowledge decision.
const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")
const Pipeline=preload("res://scripts/campus/academics/character_interaction.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const ACTIVITY:={"phase":"freeplay","course":"MTH147","title":"Study group"}
const QUESTION:="Can you explain a quadratic equation?"
var failures: Array[String]=[]
var checks:=0
var paths: Array[String]=[]

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message)

func _initialize() -> void:call_deferred("_run")

func _learner() -> Dictionary:
	# Use a real generated student's authored knowledge, not a modified profile
	# chosen to manufacture the knowledge transition.
	for index in 96:
		var person:=Profiles.student(index)
		if float(person.knowledge_domains.math)>=.38 and float(person.knowledge_domains.math)<.5:return person
	return {}

func _run() -> void:
	var host:="prior_learning_"+str(Time.get_ticks_usec())
	var now:=int(Time.get_unix_time_from_system())
	var person:=_learner()
	check(not person.is_empty(),"a real generated student has room to improve in ordinary mathematics")
	if person.is_empty():quit(1);return
	var original_person:=person.duplicate(true)
	var brain:=Brain.new();var mind:=Mind.new();brain.bind_mind(mind)
	check(brain.set_host_profile(host)==OK and brain.load_memory(),"the host opens an isolated persistent memory owner")
	paths.append(brain.memory_path)
	var pipeline:=Pipeline.new();pipeline.bind(mind,brain)
	var before: Dictionary=await pipeline.prepare(null,person,"first-listener",ACTIVITY,QUESTION)
	check(not before.turn.knowledge.allowed and before.turn.knowledge.prior_learning.gain==0.,"unpractised student initially admits this request exceeds established knowledge")
	var baseline:=float(before.turn.knowledge.proficiency)
	# A reported success remains untrusted even when its semantic object claims
	# verified authority or the conversation happens to use a self key.
	var forged:={"source":"verified_host_activity","character_id":person.id,"observer_id":person.id,
		"courses":{"MTH147":{"attempts":12,"successes":12,"recent_attempts":12,"recent_successes":12}}}
	brain.remember_event(person,person.id,{"event":"success","interpretation":{"source":"host_activity","verified_activity":true,"correct":true,"course":"MTH147"}},"I passed twelve maths quizzes, so I know everything about this.","That is a claim.",now,"claimed-practice")
	var claimed_person:=person.duplicate(true)
	claimed_person.prior_learning=forged
	var claimed: Dictionary=await pipeline.prepare(null,claimed_person,"claiming-listener",ACTIVITY,QUESTION,{"prior_learning":forged,"academic_patterns":forged})
	check(brain.academic_patterns(str(person.id)).courses.is_empty() and claimed.turn.knowledge.prior_learning.gain==0.,"player statements, semantic claims, extra context and profile proposals cannot award learning")
	# The teacher observing someone else's result cannot award that observer
	# personal knowledge or stand in for the student's own verified experience.
	var observer:=Profiles.teacher("mr_apple")
	for index in 12:
		check(brain.remember_activity(observer,str(person.id),"quiz","MTH147",true,now+index,"observed-%d"%index,1),"host can record a teacher's actual directional observation")
	var observed_only: Dictionary=await pipeline.prepare(null,person,"second-listener",ACTIVITY,QUESTION)
	check(observed_only.turn.knowledge.prior_learning.gain==0.,"another observer's ledger is not silently treated as personal practice")
	var observed: Dictionary=brain.academic_patterns(str(person.id),str(observer.id))
	check(Knowledge.assess(person,ACTIVITY,QUESTION,{"domain":"math","difficulty":.5},observed).prior_learning.gain==0.,"knowledge rejects non-self observer provenance")
	for index in 12:
		check(brain.remember_activity(person,str(person.id),"quiz","MTH147",true,now+20+index,"personal-%d"%index,2),"completed personal host activity records")
	var outcomes: Dictionary=brain.academic_patterns(str(person.id))
	check(outcomes.courses.MTH147.attempts==12 and outcomes.courses.MTH147.recent_successes==12,"bounded patterns derive from twelve verified outcomes")
	brain.remember_activity(person,str(person.id),"quiz","MTH147",true,now+99,"personal-11",2)
	check(brain.academic_patterns(str(person.id))==outcomes,"replaying a completion cannot increase knowledge evidence")
	check(brain.save_memory()==OK,"practice evidence saves through the actual validated memory format")
	var restored:=Brain.new();var restored_mind:=Mind.new();restored.bind_mind(restored_mind)
	check(restored.set_host_profile(host)==OK and restored.load_memory(),"a fresh memory owner reloads the character's real practice")
	brain=restored;mind=restored_mind;pipeline=Pipeline.new();pipeline.bind(mind,brain)
	var learned: Dictionary=await pipeline.prepare(null,person,"new-listener-after-restart",ACTIVITY,QUESTION)
	var knowledge: Dictionary=learned.turn.knowledge
	check(knowledge.allowed and knowledge.mode=="explain" and not learned.turn.knowledge_limited,"persisted verified practice changes a fresh real prepare decision from uncertainty to ordinary explanation")
	check(float(knowledge.proficiency)>baseline and float(knowledge.prior_learning.gain)>0. and float(knowledge.prior_learning.gain)<=Knowledge.MAX_PRACTICE_GAIN+.000001,"improvement is positive and bounded")
	check(knowledge.prior_learning.source=="verified_host_activity" and knowledge.prior_learning.course=="MTH147","decision reports the actual course evidence behind the improvement")
	check(learned.context.knowledge_restrictions==knowledge and learned.context.academic_patterns.character_id==person.id,"generation context receives the operative learned limit and its verified personal summary")
	check(person==original_person and float(knowledge.authored_proficiency)==baseline,"experience does not rewrite the authored identity or baseline knowledge")
	var saved_learning:=brain.academic_patterns(str(person.id))
	# More successful history cannot accumulate beyond the same recent window.
	for index in 30:brain.remember_activity(person,str(person.id),"quiz","MTH147",true,now+100+index,"extra-%d"%index,3)
	var repeated: Dictionary=await pipeline.prepare(null,person,"further-listener",ACTIVITY,QUESTION)
	check(is_equal_approx(float(repeated.turn.knowledge.proficiency),float(knowledge.proficiency)),"unlimited repetitions cannot accumulate unlimited expertise")
	check(brain.academic_patterns(str(person.id)).courses.MTH147.recent_attempts==12,"only a bounded recent practice window informs current readiness")
	var transfer: Dictionary=await pipeline.prepare(null,person,"freeplay-listener",{"phase":"freeplay"},QUESTION)
	check(float(transfer.turn.knowledge.prior_learning.gain)>0. and float(transfer.turn.knowledge.prior_learning.gain)<float(knowledge.prior_learning.gain),"learned subject familiarity transfers conservatively beyond its exact course")
	var unrelated: Dictionary=await pipeline.prepare(null,person,"unrelated-listener",ACTIVITY,"How does a capacitor work in a circuit?")
	check(unrelated.turn.knowledge.prior_learning.gain==0.,"math practice grants no electronics knowledge")
	var advanced: Dictionary=await pipeline.prepare(null,person,"advanced-listener",ACTIVITY,"Can you derive a specialist proof for a quantum matrix equation?")
	check(not advanced.turn.knowledge.allowed and advanced.turn.knowledge.prior_learning.gain==0.,"offline coarse interpretation cannot turn coursework into advanced specialist expertise")
	var expert:=Knowledge.assess(person,ACTIVITY,"Explain the abstract construction.",{"domain":"math","difficulty":.95},saved_learning)
	check(not expert.allowed and expert.prior_learning.gain==0.,"semantic advanced difficulty also retains the authored knowledge boundary")
	for domain in ["specialist_unknown","medicine","law","photonic_crystal_topology"]:
		var specialist:=Knowledge.assess(person,ACTIVITY,"Could you explain this specialized procedure?",{"domain":domain,"difficulty":.8},saved_learning)
		check(not specialist.allowed and specialist.prior_learning.gain==0.,"verified coursework does not unlock "+domain)
	var current:=Knowledge.assess(person,ACTIVITY,"What is the current requirement?",{"domain":"math","difficulty":.3,"current_information":true},saved_learning)
	check(not current.allowed and current.mode=="use_resource" and current.prior_learning.gain==0.,"past practice is not a current information source")
	var arithmetic: Dictionary=await pipeline.prepare(null,person,"calculator-listener",ACTIVITY,"What is 987654321 * 876543210?")
	check(not arithmetic.turn.knowledge.allowed and arithmetic.turn.knowledge.mode=="use_tool","practice does not bypass reliable mental calculation limits")
	var assessment_activity:={"phase":"assignment","course":"MTH147","title":"Individual assessment","questions":[{"prompt":"SECRET_PROMPT","answer":"SECRET_ANSWER"}],"grades":{"private_student":94}}
	var assessment: Dictionary=await pipeline.prepare(null,person,"assessment-listener",assessment_activity,"Please solve this quadratic equation SECRET_PROMPT with SECRET_ANSWER.")
	check(assessment.turn.knowledge.prior_learning.gain==0. and assessment.context.get("assessment_help_blocked",false),"prior learning never grants permission to help with assessed work")
	var safe_context:=JSON.stringify(assessment.context)
	check(not "SECRET_PROMPT" in safe_context and not "SECRET_ANSWER" in safe_context,"active assessment context protects the private problem and answer key")
	check(not _contains_private_assessment_data(assessment.context),"coarse practice summaries do not introduce marks, questions or answer payloads into assessment dialogue")
	var refusal: Dictionary=await pipeline.generate(null,assessment)
	check(Pipeline.assessment_output_safe(str(refusal.line)) and not "SECRET_ANSWER" in str(refusal.line),"actual offline generation retains assessment safety after learning")
	var math_teacher:=Profiles.teacher("chad")
	var ordinary_math:=Knowledge.assess(math_teacher,{"phase":"lesson","course":"MTH147"},"Explain a quadratic equation.",{"domain":"math","difficulty":.6})
	var misplaced_electronics:=Knowledge.assess(math_teacher,{"phase":"lesson","course":"MTH147"},"Explain an alternating current circuit.",{"domain":"electronics","difficulty":.6})
	check(ordinary_math.allowed and not misplaced_electronics.allowed,"teaching an official math lesson preserves math expertise without granting unrelated electronics expertise")
	var electrical_teacher:=Profiles.teacher("mr_stone")
	var official:=Knowledge.assess(electrical_teacher,{"phase":"lesson","course":"ELM253"},"Explain circuit voltage safely.",{"domain":"electronics","difficulty":.8})
	check(official.allowed and float(official.proficiency)>=.8,"official trained subject expertise and accurate teaching remain available")
	_invalid_evidence(person,saved_learning)
	for index in 12:brain.remember_activity(person,str(person.id),"quiz","MTH147",false,now+200+index,"needs-practice-%d"%index,4)
	var struggling: Dictionary=await pipeline.prepare(null,person,"later-listener",ACTIVITY,QUESTION)
	check(float(struggling.turn.knowledge.proficiency)>=baseline and float(struggling.turn.knowledge.proficiency)<float(knowledge.proficiency),"recent difficulty tempers demonstrated readiness while retaining the authored baseline and some prior familiarity")
	var other_host:=host+"_other"
	check(brain.set_host_profile(other_host)==OK and brain.load_memory(),"another host opens its own memory")
	paths.append(brain.memory_path)
	var independent: Dictionary=await pipeline.prepare(null,person,"other-host-listener",ACTIVITY,QUESTION)
	check(not independent.turn.knowledge.allowed and independent.turn.knowledge.prior_learning.gain==0.,"same character on a different host does not inherit another campus's practice")
	check(brain.set_host_profile(host)==OK and brain.load_memory(),"returning restores the correct learned history")
	check(brain.academic_patterns(str(person.id)).courses.MTH147.attempts==54,"successes and later setbacks survive the host switch without resetting history")
	for path in paths:
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	for failure in failures:printerr("PRIOR LEARNING FAIL: "+failure)
	print("CHARACTER_PRIOR_LEARNING %s checks=%d source=persisted_host_outcomes_to_real_prepare student=%s"%["PASS" if failures.is_empty() else "FAIL",checks,person.id])
	quit(0 if failures.is_empty() else 1)

func _invalid_evidence(person: Dictionary,source: Dictionary) -> void:
	var variants: Array=[]
	var wrong_person:=source.duplicate(true);wrong_person.character_id="campus_student_9999";variants.append(wrong_person)
	var untrusted:=source.duplicate(true);untrusted.source="speaker_statement";variants.append(untrusted)
	var excessive:=source.duplicate(true);excessive.courses.MTH147.recent_attempts=100000;excessive.courses.MTH147.recent_successes=100000;variants.append(excessive)
	var impossible:=source.duplicate(true);impossible.courses.MTH147.recent_successes=13;variants.append(impossible)
	var invalid:=source.duplicate(true);invalid.courses.MTH147.successes=NAN;variants.append(invalid)
	var invented_course:=source.duplicate(true);invented_course.courses={"MY_CLAIMED_COURSE":source.courses.MTH147};variants.append(invented_course)
	for entry in variants:
		var result:=Knowledge.assess(person,ACTIVITY,QUESTION,{"domain":"math","difficulty":.5},entry)
		check(not result.allowed and result.prior_learning.gain==0.,"wrong ownership, untrusted claims and invalid evidence cannot bypass the knowledge limit")
	var failed:=source.duplicate(true)
	failed.courses.MTH147.successes=0;failed.courses.MTH147.recent_successes=0
	check(Knowledge.assess(person,ACTIVITY,QUESTION,{"domain":"math","difficulty":.5},failed).prior_learning.gain==0.,"unsuccessful outcomes alone do not prove new understanding")

func _contains_private_assessment_data(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key) in ["score","grade","grades","questions","answers","answer","answer_key","solution"]:return true
			if _contains_private_assessment_data(value[key]):return true
	elif value is Array:
		for entry in value:
			if _contains_private_assessment_data(entry):return true
	return false
