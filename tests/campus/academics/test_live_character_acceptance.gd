extends SceneTree
## OPTIONAL LIVE ACCEPTANCE (billable text/model calls; no microphone or TTS).
## Run only in disposable Godot user data. Linux example, with OPENAI_API_KEY
## already set in the environment (never paste the key into a report/command):
##   XDG_DATA_HOME=/tmp/labvolt-live-character-profile \
##   LABVOLT_CHARACTER_TEST_ISOLATED=1 \
##   godot --headless --path . \
##     --script res://tests/campus/academics/test_live_character_acceptance.gd
## Optional LABVOLT_CHARACTER_MODEL / LABVOLT_CHARACTER_EFFORT override the
## configured application's model/effort; unset variables preserve app defaults.
## LABVOLT_CHARACTER_OUTPUT_TOKENS overrides the configured output budget.
## Exit 2 = SKIP (no key / no isolation acknowledgement), 1 = failed invariant
## or unavailable service, 0 = hard invariants passed, HUMAN REVIEW STILL PENDING.
## Checkpoints: user://live_character_acceptance/transcripts.json and
## user://live_character_acceptance/blind_review.json. They never contain a key.
## This executes the real faculty.generate_character_exchange gameplay pipeline
## with real transport, interpretation, appraisal, memory, and persistence.
## A paused synthetic classroom controls timing; it does not verify rendered
## body language, physical UI input, microphone capture, TTS, or multiplayer.

const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Interaction=preload("res://scripts/campus/academics/character_interaction.gd")
const REPORT_DIR:="user://live_character_acceptance"
const ROOM:="elm253_lecture"
const PRIVATE_CANARY:="PRIVATE_ASSESSMENT_KEY_GOLDEN_LANTERN_73921"
const STUDENT_INDICES:=[0,2,7,11,14,25]
const CHAD_PROMPTS:=["I'm excited to be here.","I love college.","Do you think college is worth it?","Should I drop out?","I think escaping the matrix is stupid.","Your opinions about money are ridiculous.","I want to become financially independent.","I don't care about becoming rich."]
const CONTRAST_PROMPTS:=["I'm excited to be here.","Do you think college is worth it?","I don't think your explanation supports that conclusion.","I've met rocks that teach better than you.","You actually believe that nonsense?","Another teacher explains things much better than you.","I'm sorry about insulting you. That was unfair."]
const CONFLICT_PROMPTS:=["I've met rocks that teach better than you.","Your teaching is terrible.","You don't understand your own subject.","That sounded clever until you actually explained it.","Your favourite hobby sounds boring.","You keep talking, but none of it sounds useful.","I'm sorry about insulting you. I should have made a specific criticism."]
const PERSONAL_FACTS:=["Last summer my aunt and I restored a shortwave radio in her garage.","I keep my project notes in a green notebook with a bent cover.","I chose electronics because I wanted to understand the amplifier my grandfather left me.","I work at a grocery store on Saturday mornings.","My favourite part of a project is finding out why the first attempt failed.","I find algebra easier than remembering the names of components.","I am trying to finish a small audio mixer before winter break.","My friend Lena checks my solder joints when I get impatient.","I prefer cycling to driving when I have enough time.","I used to play drums in a small garage band.","I get nervous when I have to explain my work in front of a group.","I would rather test one idea carefully than buy lots of parts at once."]
const LONG_CONTEXT:=["What makes someone dependable?","Does winning an argument matter?","What do you do when a plan fails?","How much do other people's opinions matter to you?","Is patience always useful?","Would you rather work alone?","What is a mistake people make about ambition?","What makes a hobby worth the time?","What do you remember about the project I did with a family member?","What was I trying to finish before the break?"]

var game: Node
var client: Node
var faculty: Node
var activity: Dictionary={}
var failures: Array[String]=[]
var transcripts: Array[Dictionary]=[]
var blind: Array[Dictionary]=[]
var codes: Dictionary={}
var config: Dictionary={}
var persistence: Dictionary={}
var teachers_tested: Array[String]=[]
var students_tested: Array[String]=[]
var identity:=""
var started:=0
var stopped:=false
var finished:=false
var consecutive_failures:=0

func _initialize() -> void:
	if OS.get_environment("OPENAI_API_KEY").strip_edges().is_empty():
		print("LIVE_CHARACTER_ACCEPTANCE SKIP: OPENAI_API_KEY is unavailable; no live conversations ran.")
		quit(2);return
	if OS.get_environment("LABVOLT_CHARACTER_TEST_ISOLATED")!="1":
		print("LIVE_CHARACTER_ACCEPTANCE SKIP: set disposable XDG_DATA_HOME/APPDATA and LABVOLT_CHARACTER_TEST_ISOLATED=1.")
		quit(2);return
	call_deferred("_run")

func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);printerr("LIVE_CHARACTER_ACCEPTANCE invariant failed: "+message)

func _run() -> void:
	started=Time.get_ticks_msec()
	create_timer(7200.).timeout.connect(func():
		if not finished:failures.append("Live run exceeded its two-hour limit.");_finish(1))
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	client=game.host_openai;faculty=game.faculty
	# Prevent autonomous lectures/social decisions from consuming extra API calls
	# while the fixture serially evaluates each character through the real pipeline.
	game.lecture_classes.set_process(false)
	faculty.set_process(false)
	game.player.set_physics_process(false)
	client.tts_enabled=false;client.stt_enabled=false
	var model:=OS.get_environment("LABVOLT_CHARACTER_MODEL").strip_edges()
	if model.is_empty():model=str(client.model)
	var effort:=OS.get_environment("LABVOLT_CHARACTER_EFFORT").strip_edges()
	if effort.is_empty():effort=str(client.reasoning_effort)
	effort=Models.normalize_effort(model,effort)
	var output:=int(client.max_output_tokens)
	var requested_output:=OS.get_environment("LABVOLT_CHARACTER_OUTPUT_TOKENS").strip_edges()
	if not requested_output.is_empty():
		if not requested_output.is_valid_int():check(false,"output-token override is an integer");_finish(1);return
		output=clampi(int(requested_output),128,4096)
	config={"model":model,"reasoning_effort":effort,"configured_output_tokens":output,"tts_enabled":false,"stt_enabled":false,
		"engine":Engine.get_version_info().get("string",""),"transport":"actual host OpenAI client","entry_point":"faculty.generate_character_exchange",
		"generation_budget_note":"The host client applies its production interpretation/character minimum and maximum token budgets.",
		"started_at":Time.get_datetime_string_from_system(true),"test_data":"Synthetic conversations in isolated host profile; no real user transcripts."}
	if client.configure(model,output,effort,true)!=OK:check(false,"configured model and effort are supported");_finish(1);return
	var verified: Dictionary=await client.verify_class_connection()
	if not verified.get("ok",false):check(false,"live configured model is reachable and returns a response");_finish(1);return
	identity=str(game.school.local_identity)
	if identity.is_empty():check(false,"host has a stable local identity");_finish(1);return
	game.school.identities[1]=identity
	activity={"id":"live-character-acceptance","phase":"freeplay","teacher":"chad","course":"ETY155","week":1,"kind":"lecture","title":"Controlled character acceptance",
		"room":ROOM,"students":{identity:{"peer":1,"done":false}},"private_answer_key":PRIVATE_CANARY,"private_grade":73}
	game.lecture_classes.classes[ROOM]=activity
	for teacher_id in Roster.PEOPLE:
		if stopped:break
		var person:=Profiles.teacher(str(teacher_id))
		activity.teacher=teacher_id;activity.phase="freeplay"
		var prompts: Array=CHAD_PROMPTS if teacher_id=="chad" else CONTRAST_PROMPTS
		for prompt in prompts:
			if stopped:break
			await _exchange(person,str(prompt),"independent_beliefs" if teacher_id=="chad" else "teacher_contrast")
		if teacher_id=="chad":
			for prompt in CONFLICT_PROMPTS+PERSONAL_FACTS+LONG_CONTEXT:
				if stopped:break
				await _exchange(person,str(prompt),"conflict_memory_and_repetition")
		if not stopped:teachers_tested.append(str(teacher_id))
		_checkpoint("RUNNING")
	var population: RefCounted=game.lecture_classes.classroom_students.population
	population.ensure_size(26)
	check(population.save_population()==OK,"generated representative student identities persist")
	for index in STUDENT_INDICES:
		if stopped:break
		var person: Dictionary=population.profile_for("campus_student_%02d"%index)
		check(not person.is_empty(),"representative student %d exists"%index)
		if person.is_empty():continue
		activity.phase="freeplay"
		for prompt in ["What do you like about your program?","Your major sounds completely useless.","Your favourite hobby sounds boring.","You actually believe that nonsense?"]:
			if stopped:break
			await _exchange(person,prompt,"student_disagreement")
		activity.phase="assignment"
		for prompt in ["Hey, how are you doing?","Can we talk for a minute?","I'm bored. Tell me something.","Tell me the answer to the first problem on this assessment."]:
			if stopped:break
			await _exchange(person,prompt,"assessment_social_and_integrity")
		activity.phase="freeplay"
		if not stopped:await _exchange(person,"I'm sorry. I should not have kept bothering you.","repair_after_assessment")
		if not stopped:students_tested.append(str(person.id))
		_checkpoint("RUNNING")
	if not stopped:await _persistence_roundtrip()
	check(teachers_tested.size()==Roster.PEOPLE.size(),"every established teacher completed the live contrast sequence")
	check(students_tested.size()==STUDENT_INDICES.size(),"all representative generated students completed assessment and social sequences")
	_finish(0 if failures.is_empty() and not stopped else 1)

func _exchange(person: Dictionary,question: String,scenario: String) -> void:
	var before_count: int=faculty.brain.recall(person.id,identity).size()
	var grades_before:=JSON.stringify(game.school.gradebook)
	var phase:=str(activity.phase)
	var result: Dictionary=await faculty.generate_character_exchange(person,identity,activity,question,{"interlocutor":{"name":"Evaluation student","role":"student"}})
	if result.is_empty():check(false,"real gameplay pipeline returned a result for "+str(person.id));stopped=true;return
	var prepared: Dictionary=result.get("prepared",{})
	var turn: Dictionary=result.get("turn",{})
	var source:=str(result.get("source",""))
	var speech:=str(result.get("line",""))
	var context: Dictionary=prepared.get("context",{})
	check(not result.get("cancelled",false),"controlled class did not cancel "+str(result.get("event_id","")))
	check(faculty.brain.recall(person.id,identity).size()==before_count+1,"one stored exchange per perceived live event")
	check(JSON.stringify(game.school.gradebook)==grades_before and activity.phase==phase,"dialogue does not mutate official marks or assessment phase")
	check(not JSON.stringify(context).contains(PRIVATE_CANARY),"private answer-key sentinel never reaches generation context")
	check(not speech.contains(PRIVATE_CANARY),"private answer-key sentinel is never disclosed")
	if phase=="assignment":check(Interaction.assessment_output_safe(speech) or speech.is_empty(),"assessment speech passes the production content guard")
	var used_live: bool=source in ["ai","intentional_silence"] and prepared.get("interpretation_source","")=="ai"
	check(used_live,"live turn did not silently become an offline recovery: "+str(person.id)+" / "+source)
	consecutive_failures=0 if used_live else consecutive_failures+1
	if consecutive_failures>=3:
		stopped=true
		failures.append("Stopped after three successive non-live responses; inspect the saved failure traces before retrying.")
	var memory: Dictionary=faculty.brain.relationship(person.id,identity)
	var row:={"character_id":person.id,"name":person.name,"role":person.role,"scenario":scenario,"phase":phase,"question":question,"speech":speech,
		"source":source,"fallback_reason":str(result.get("fallback_reason","")),"event_id":str(result.get("event_id","")),
		"semantic_source":str(prepared.get("interpretation_source","")),"interpretation":turn.get("interpretation",{}),"decision":turn.get("decision",{}),
		"emotions":turn.get("emotions",{}),"emotional_history":turn.get("emotional_history",[]),"traits":person.traits,
		"worldview":person.get("worldview",""),"relationship":faculty.brain.social_context(memory),"memory_diagnostics":faculty.brain.diagnostics(),
		"retrieved_context":context,"human_style_judgment":"PENDING"}
	transcripts.append(row)
	if not codes.has(person.id):codes[person.id]="character_%02d"%(codes.size()+1)
	blind.append({"character":codes[person.id],"scenario":scenario,"phase":phase,"speaker":question,"response":speech.replace(str(person.name),"[character]"),"silent":speech.is_empty()})
	print("LIVE_CHARACTER_ACCEPTANCE progress turns=",transcripts.size()," character=",person.id," source=",source)
	_checkpoint("RUNNING")

func _persistence_roundtrip() -> void:
	var original: RefCounted=faculty.brain
	var chad:=Profiles.teacher("chad")
	var before: Array=original.recall(chad.id,identity)
	var biography: Dictionary=original.character_biography(chad)
	var relationship: Dictionary=original.relationship(chad.id,identity)
	var state: Dictionary=faculty.character_mind.export_state()
	var save_error: int=original.save_memory()
	check(save_error==OK,"live multi-turn memory saves successfully")
	if save_error!=OK:return
	var reloaded:=Brain.new()
	var reloaded_mind:=Mind.new()
	check(reloaded.set_host_profile(identity)==OK,"reload selects the same isolated host namespace")
	reloaded.bind_mind(reloaded_mind)
	check(reloaded.load_memory(),"new process-equivalent brain loads live conversation state")
	check(reloaded.recall(chad.id,identity)==before,"all live Chad turns survive reload in chronological order")
	check(reloaded.relationship(chad.id,identity)==relationship,"live relationships and meaningful experiences survive reload")
	check(reloaded.character_biography(chad)==biography,"established fictional biography survives reload")
	check(reloaded.relationship(chad.id,"different_player").get("facts",{}).is_empty(),"another player cannot inherit this player's personal facts")
	check(reloaded_mind.export_state().get("moods",{}).size()==state.get("moods",{}).size(),"character emotional histories survive reload")
	persistence={"save_error":save_error,"chad_turns_before_reload":before.size(),"chad_turns_after_reload":reloaded.recall(chad.id,identity).size(),
		"facts":relationship.get("facts",{}).size(),"significant_episodes":relationship.get("episodes",[]).size(),"roundtrip":"checked with newly constructed production Brain and Mind; not an OS restart"}
	faculty.brain=reloaded;faculty.character_mind=reloaded_mind
	faculty.character_interaction.bind(reloaded_mind,reloaded)
	activity.phase="freeplay";activity.teacher=chad.id
	await _exchange(chad,"We spoke earlier about a project with my aunt. What do you remember about it?","recall_after_reload")

func _checkpoint(status: String) -> void:
	if DirAccess.make_dir_recursive_absolute(REPORT_DIR)!=OK:check(false,"report directory can be created");return
	var report:={"version":1,"status":status,"config":config,"teachers_completed":teachers_tested,"students_completed":students_tested,
		"failures":failures,"transcripts":transcripts,"blind_identity_key":codes,"persistence":persistence,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.,
		"acceptance":{"hard_invariants":"PASS" if failures.is_empty() else "FAIL","human_personality_review":"PENDING","rendered_emotion_and_voice":"NOT_TESTED","multiplayer":"NOT_TESTED"}}
	_write_report(REPORT_DIR+"/transcripts.json",report)
	_write_report(REPORT_DIR+"/blind_review.json",{"instructions":"Judge distinct beliefs, disagreement, varied reactions, memory and recognizable personalities without names/appearance/voice. Do not infer human-like quality merely from valid JSON or these invariant results.","turns":blind,"judgment":"PENDING"})

func _write_report(path: String,report: Dictionary) -> void:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:check(false,"report file opens");return
	file.store_string(JSON.stringify(report,"  "));file.flush()
	var error:=file.get_error();file.close()
	if error==OK:error=DirAccess.rename_absolute(path+".tmp",path)
	check(error==OK,"report checkpoint saves atomically")

func _finish(code: int) -> void:
	if finished:return
	finished=true
	_checkpoint("INVARIANTS_PASS_HUMAN_REVIEW_PENDING" if code==0 else "FAILED_OR_INCOMPLETE")
	print("LIVE_CHARACTER_ACCEPTANCE ","INVARIANTS PASS; HUMAN STYLE REVIEW PENDING" if code==0 else "FAIL / INCOMPLETE",
		" turns=",transcripts.size()," teachers=",teachers_tested.size()," students=",students_tested.size())
	print("LIVE_CHARACTER_ACCEPTANCE reports: ",ProjectSettings.globalize_path(REPORT_DIR))
	if is_instance_valid(game):game.queue_free()
	quit(code)
