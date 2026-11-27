extends SceneTree
## Extractive retrieval and verified academic pattern regression. These fixtures
## exercise production memory and Pipeline.prepare; provider text is deterministic.
## Run with isolated XDG_DATA_HOME and the normal native Godot runtime.
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Pipeline=preload("res://scripts/campus/academics/character_interaction.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const PATH:="user://memory_summaries_fixture.json"
var checks:=0
var failures: Array[String]=[]

class Probe extends Node:
	var busy:=false
	var interpreted_context: Dictionary={}
	func ready_for_class() -> bool:return true
	func moderate(_text: String) -> Dictionary:return {"ok":true,"flagged":false}
	func interpret_character(_instructions: String,context: Dictionary,_question: String) -> Dictionary:
		interpreted_context=context.duplicate(true)
		return {"ok":true,"text":JSON.stringify({"event":"chat","tone":"neutral","severity":0.,"meaning":"The speaker asks how the character is feeling.","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]})}

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("MEMORY SUMMARIES FAIL: "+message)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var brain:=Brain.new();brain.memory_path=PATH
	var teacher:=Profiles.teacher("bill_nye")
	var person:=Profiles.student(0)
	var timestamp:=int(Time.get_unix_time_from_system())
	var stories:=[
		{"text":"I restored a shortwave radio with my aunt in her garage.","domain":"mechanics"},
		{"text":"I keep my college notes in a green notebook.","domain":"education"},
		{"text":"My friend Lena helped me finish a difficult project.","domain":"friendship"},
		{"text":"I prefer playing cooperative games with my brother.","domain":"gaming"},
		{"text":"I train at a gym near my old neighborhood.","domain":"fitness"},
		{"text":"I am studying equations carefully this semester.","domain":"math"}]
	for index in 30:
		var story: Dictionary=stories[index%stories.size()]
		var line:=str(story.text)+" That was experience %d."%index
		brain.remember_event(teacher,"alex",{"event":"initiative","interpretation":{"meaning":"Alex described a personal experience.","importance":.9 if index==0 else .5,"memories":[{"subject":"story_%d"%index,"quote":line,"domain":story.domain}]}},line,"I remember that experience.",timestamp+index,"story-%d"%index)
	var source: Dictionary=brain.relationship(teacher.id,"alex")
	var originals:=JSON.stringify({"relationship":source,"turns":brain.recall(teacher.id,"alex")})
	var summaries:=brain.conversation_summaries(teacher.id,"alex","What did I do with my aunt in her garage?")
	check(not summaries.is_empty() and summaries.size()<=4,"Retrieval supplies a bounded set of structured topic summaries")
	check(summaries[0].topic=="mechanics","Relevant old topic ranks before unrelated recent topics")
	check(summaries[0].summary_kind=="extractive_records" and summaries[0].fact_count>=5,"Topic view identifies its extractive source and counts retained facts")
	check(summaries[0].first_at<=summaries[0].last_at,"Summary timeline preserves source timestamps")
	var grounded:=true
	for summary in summaries:
		for entry in summary.notable_experiences:
			grounded=grounded and source.episodes.any(func(original):return str(original.get("description","")).begins_with(entry.excerpt) and original.get("event_id","")==entry.event_id)
		for entry in summary.reported_facts:
			grounded=grounded and source.facts.has(entry.subject) and str(source.facts[entry.subject].statement).begins_with(entry.excerpt) and entry.source=="speaker_statement"
	check(grounded,"Every episode/fact excerpt is traceable to the retained original and its provenance")
	check(JSON.stringify({"relationship":brain.relationship(teacher.id,"alex"),"turns":brain.recall(teacher.id,"alex")})==originals,"Creating summaries does not rewrite or discard original history")
	check(brain.conversation_summaries(teacher.id,"other-player").is_empty() and brain.conversation_summaries("mr_stone","alex").is_empty(),"Topic views preserve both speaker and character isolation")
	var question:="Can we discuss my friendship with Lena?"
	brain.remember_event(teacher,"alex",{"event":"chat"},question,"",timestamp+31,"unanswered")
	var unanswered:=brain.conversation_summaries(teacher.id,"alex",question)
	check(unanswered.any(func(summary):return summary.unanswered_questions.any(func(entry):return entry.event_id=="unanswered" and entry.excerpt==question)),"A perceived question with no delivered answer remains identifiable")
	check(brain.complete_event(teacher,"alex","unanswered","We can talk about how you get along."),"Delayed actual speech completes the source event")
	check(not brain.conversation_summaries(teacher.id,"alex",question).any(func(summary):return summary.unanswered_questions.any(func(entry):return entry.event_id=="unanswered")),"Completing the original exchange removes its unanswered marker")
	check(brain.character_context(teacher,"alex",question).topic_summaries.size()<=4,"The production context includes the derived topic view")

	brain.remember_activity(person,person.id,"quiz","MTH147",false,timestamp,"first-difficulty",1)
	var first:=brain.academic_patterns(person.id)
	check(first.source=="verified_host_activity" and first.character_id==person.id and first.observer_id==person.id,"Academic source ownership is explicit")
	check(first.courses.MTH147.attempts==1 and first.courses.MTH147.trend=="insufficient_evidence","One wrong checked answer does not establish a persistent weakness")
	check(first.courses.MTH147.practice_needs.is_empty() and first.misconceptions.is_empty(),"No misconception or repeated difficulty is invented from one mistake")
	for index in 5:
		brain.remember_activity(person,person.id,"quiz","MTH147",index>=2,timestamp+index+1,"math-outcome-%d"%index,1)
	var developing:=brain.academic_patterns(person.id)
	check(developing.courses.MTH147.attempts==6 and developing.courses.MTH147.successes==3 and developing.courses.MTH147.difficulties==3,"Patterns count actual checked outcomes")
	check(developing.courses.MTH147.trend=="improving","Repeated early difficulty followed by successful checked work produces an improvement trend")
	check(not developing.courses.MTH147.practice_needs.is_empty() and "not been diagnosed" in developing.courses.MTH147.uncertainty,"Remaining difficulty carries explicit causal uncertainty")
	check(developing.courses.MTH147.weeks["1"].attempts==6 and developing.courses.MTH147.weeks["1"].difficulties==3,"Week-level evidence retains both success and difficulty")
	for index in 14:
		brain.remember_activity(person,person.id,"lab","ETY155",true,timestamp+40+index,"safe-practice-%d"%index,2,true)
	var proficient:=brain.academic_patterns(person.id)
	check(proficient.courses.ETY155.attempts==14 and proficient.courses.ETY155.recent_attempts==12 and proficient.courses.ETY155.recent_successes==12,"Recent evidence is capped independently from total retained experience")
	check(proficient.courses.ETY155.strengths.size()==1 and proficient.courses.ETY155.practice_needs.is_empty(),"Repeated checked success establishes an evidence-limited strength")
	check(proficient.courses.ETY155.domain=="electronics" and proficient.courses.MTH147.domain=="math","Only known courses map to knowledge domains")
	var prior_pattern:=proficient.duplicate(true)
	brain.remember_event(person,person.id,{"event":"success","interpretation":{"verified_activity":true}},"I aced every electronics test.","Sure.",timestamp+70,"speech-claim")
	check(brain.academic_patterns(person.id)==prior_pattern,"Speech claims and semantic authority markers cannot become verified learning evidence")
	check(brain.academic_patterns("other-student").courses.is_empty() and brain.academic_patterns(person.id,"mr_stone").courses.is_empty(),"Academic patterns do not leak between subjects or unobserving teachers")
	brain.remember_activity(teacher,person.id,"assessment","ETY155",true,timestamp+80,"teacher-observed",2)
	check(brain.academic_patterns(person.id,teacher.id).courses.ETY155.attempts==1 and brain.academic_patterns(person.id).courses.ETY155.attempts==14,"Observer and self evidence remain directional and independent")
	check(brain.character_context(person,"other-listener","How is your course going?").academic_patterns.courses.ETY155.strengths.size()==1,"Verified learning patterns reach the student's shared conversational context")
	check(brain.character_context(teacher,person.id,"How is the class going?").interlocutor_academic_patterns.courses.ETY155.attempts==1,"The supervising teacher receives only their observed student pattern")
	check(not str(prior_pattern).contains("expected") and not str(prior_pattern).contains("answer_key") and not str(prior_pattern).contains("score"),"Compact academic evidence contains no mark or solution-bearing feedback")
	check(brain.save_memory()==OK,"Underlying sources save in the current validated memory schema")
	var fresh:=Brain.new();fresh.memory_path=PATH
	check(fresh.load_memory(),"A fresh memory owner reloads the sources")
	check(fresh.academic_patterns(person.id)==brain.academic_patterns(person.id),"Academic patterns reconstruct identically after persistence")
	check(fresh.conversation_summaries(teacher.id,"alex",question)==brain.conversation_summaries(teacher.id,"alex",question),"Grounded topic summaries reconstruct identically after persistence")

	# A raw academic source must not re-enter protected assessment context through
	# the new nested summaries after the existing history filter removed it.
	brain.remember_conversation(teacher.id,"exam-listener","What result did we get?","The answer is 774411 volts.",timestamp+90)
	check("774411" in str(brain.conversation_summaries(teacher.id,"exam-listener")),"Private-source sentinel genuinely exists in ordinary summaries before filtering")
	var mind:=Mind.new()
	var pipeline:=Pipeline.new();pipeline.bind(mind,brain)
	var provider:=Probe.new();root.add_child(provider)
	var prepared: Dictionary=await pipeline.prepare(provider,teacher,"exam-listener",{"phase":"assignment","course":"ETY155"},"How are you feeling?")
	check(not provider.interpreted_context.has("topic_summaries") and not "774411" in JSON.stringify(provider.interpreted_context),"Interpretation receives no unsafe summary or answer sentinel during an assessment")
	check(not prepared.context.has("topic_summaries") and not "774411" in JSON.stringify(prepared.context),"Regenerated response context cannot reintroduce unsafe summaries")
	check(brain.recall(teacher.id,"exam-listener")[0].teacher.contains("774411"),"Assessment privacy filtering preserves the original stored record")
	provider.queue_free();await process_frame
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(PATH+suffix)
	print("CHARACTER_MEMORY_SUMMARIES ","PASS" if failures.is_empty() else "FAIL"," checks=",checks)
	quit(0 if failures.is_empty() else 1)
