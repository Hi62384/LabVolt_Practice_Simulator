extends SceneTree
## Run only through run_character_process_restart.py. Two separate native
## processes open the same disposable Singleplayer save. Provider output for one
## delivered biography is a deterministic fixture, never live-model evidence.
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const BIO_TOPIC:="training.partners.nora_restart"
const BIO_DETAIL:="I trained with Nora at a warehouse gym for two winters."
var checks:=0
var failures: Array[String]=[]
var game: Node
var mode:=""
var evidence_path:=""

class BiographyProvider extends Node:
	var busy:=false
	func ready_for_class() -> bool:return true
	func moderate(_text: String) -> Dictionary:return {"ok":true,"flagged":false}
	func interpret_character(_instructions: String,_context: Dictionary,_question: String) -> Dictionary:
		return {"ok":true,"text":JSON.stringify({"event":"chat","tone":"friendly","severity":0.,"meaning":"The speaker asks about a past training partner.","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]})}
	func respond_character(_instructions: String,context: Dictionary,_question: String,_visual:=false) -> Dictionary:
		return {"ok":true,"text":JSON.stringify({"speech":BIO_DETAIL,"biography":{"topic":BIO_TOPIC,"detail":BIO_DETAIL},
			"interpretation":{"event":"chat","tone":"friendly","severity":0.,"meaning":"The speaker asks about a past training partner.","domain":"conversation","question_kind":"personal_experience","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]},
			"delivery":{"emotion":str(context.get("emotional_state",{}).get("emotion","steady")),"knowledge_mode":"personal_conversation"}})}

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("CHARACTER RESTART FAIL: "+message)

func same(left: Variant,right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):return absf(float(left)-float(right))<=.000000001
	if left is Dictionary and right is Dictionary:
		if left.size()!=right.size():return false
		for key in left:
			if not right.has(key) or not same(left[key],right[key]):return false
		return true
	if left is Array and right is Array:
		if left.size()!=right.size():return false
		for index in left.size():
			if not same(left[index],right[index]):return false
		return true
	return left==right

func run() -> void:
	mode=OS.get_environment("LABVOLT_CHARACTER_RESTART_MODE")
	evidence_path=OS.get_environment("LABVOLT_CHARACTER_RESTART_EXPECTED")
	if OS.get_environment("LABVOLT_CHARACTER_TEST_ISOLATED")!="1" or mode not in ["write","read"] or evidence_path.is_empty():
		printerr("Use the isolated two-process wrapper.");quit(2);return
	if mode=="write" and FileAccess.file_exists(evidence_path):
		printerr("Refusing to reuse an existing writer fixture.");quit(1);return
	create_timer(70.).timeout.connect(func():printerr("Character restart phase timed out.");quit(1))
	print("CHARACTER_RESTART_PROCESS ",JSON.stringify({"phase":mode,"pid":OS.get_process_id()}))
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.host_openai.enabled=false
	game.client_preferences.values.teacher_speech=false;game.client_preferences.values.teacher_subtitles=false
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 2:await process_frame
	game.player.set_physics_process(false);game.faculty.set_process(false);game.lecture_classes.set_process(false)
	check(game.front.in_game and not game.session.online and game.faculty._sync_character_profile(),"Actual Main enters Singleplayer with an active host namespace")
	check(not str(game.school.local_identity).is_empty() and game.faculty.brain.host_profile()==game.school.local_identity,"Game and memory select the same stable local identity")
	if mode=="write":await write_phase()
	else:read_phase()
	game.queue_free();await process_frame
	print("CHARACTER_PROCESS_RESTART ","PASS" if failures.is_empty() else "FAIL"," phase=",mode," pid=",OS.get_process_id()," checks=",checks)
	quit(0 if failures.is_empty() else 1)

func write_phase() -> void:
	var faculty: Node=game.faculty
	var identity:=str(game.school.local_identity)
	var students: Node=game.lecture_classes.classroom_students
	preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd").seed(students.population,31)
	var custom_id:="campus_student_30"
	students.population.people[custom_id].name="Iris Restart Fixture"
	students.population.people[custom_id].traits.patience=.317
	students.population.dirty=true
	preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd").sync(students.population)
	# The fixture began as historical profiles. Resolve their authoritative
	# dossier projection in this process, exactly as a loaded population does,
	# before comparing the complete runtime roster across the process boundary.
	for id in students.population.people:students.population.people[id]=students.population.profile_for(id)
	var student: Dictionary=students.population.profile_for(custom_id)
	var scene:={"phase":"freeplay","course":"","title":"Synthetic restart fixture"}
	var tokens:={}
	for index in 20:
		var question:="I spent Sunday restoring radio fixture %d with my aunt in her garage."%index
		var result: Dictionary=await faculty.generate_character_exchange(Profiles.teacher("ms_bird_heart"),identity,scene,question)
		check(not result.get("cancelled",false) and result.get("event_id","")!="","Actual gameplay records personal-story turn %d"%index)
		if result.has("event_id"):tokens[result.event_id]=true
	for question in ["You're an idiot.","I've met rocks that teach better than you.","Your teaching is terrible.","You are stupid.","You suck.","You have no idea what you are doing.","I'm sorry for insulting you.","I still think that was a terrible explanation."]:
		var result: Dictionary=await faculty.generate_character_exchange(Profiles.teacher("brian"),identity,scene,question)
		check(not result.get("cancelled",false) and result.get("event_id","")!="","Actual gameplay records the evolving conflict and apology")
		if result.has("event_id"):tokens[result.event_id]=true
	for question in ["I keep my notes in a green notebook.","I work with my aunt on weekends.","Your favorite hobby sounds boring."]:
		var result: Dictionary=await faculty.generate_character_exchange(student,identity,scene,question)
		check(not result.get("cancelled",false) and result.get("event_id","")!="","Saved student identity participates in the gameplay pipeline")
		if result.has("event_id"):tokens[result.event_id]=true
	check(tokens.size()==31,"Each observed gameplay turn has a distinct event identifier")
	check(faculty.brain.relationship("ms_bird_heart",identity).get("facts",{}).size()>=20,"Ordinary personal stories produced retained factual memory")
	check(faculty.brain.relationship("brian",identity).dimensions.resentment>0.,"Conflict creates a persistent directional feeling before restart")
	# Use the same Faculty entry point with authored provider output, and delay
	# canonization until the real conversation widget displays the complete line.
	var original_client: Node=game.host_openai
	var fixture:=BiographyProvider.new();root.add_child(fixture);game.host_openai=fixture
	var biography: Dictionary=await faculty.generate_character_exchange(Profiles.teacher("mr_bro"),identity,scene,"Tell me about an old training partner.",{"defer_record":true})
	game.host_openai=original_client
	check(biography.get("source","")=="ai" and biography.get("line","")==BIO_DETAIL,"Fixture biography passes the real structured generation and validation path")
	check(not faculty.brain.character_biography(Profiles.teacher("mr_bro")).has(BIO_TOPIC),"Undelivered generated biography is not canonized")
	game.school.mode="Freeplay"
	faculty.current["ac_lab"]="mr_bro"
	faculty.open_conversation("ac_lab")
	check(faculty._selected_conversation_current(),"The actual conversation UI selects the current office-hours teacher")
	faculty._dialogue_reply("ac_lab","mr_bro",str(biography.get("line","")))
	check(faculty.conversation_text.text==BIO_DETAIL,"The actual conversation UI receives the whole biography sentence")
	check(faculty.character_interaction.record(biography,true),"Delivery records the previously deferred event")
	check(faculty.brain.character_biography(Profiles.teacher("mr_bro")).get(BIO_TOPIC,"")==BIO_DETAIL,"Delivered specific biography becomes canon")
	faculty.close_conversation();fixture.queue_free()
	check(students.population.save_population()==OK,"The expanded customized roster saves")
	check(faculty.brain.save_memory()==OK,"Full gameplay memory and bound mind save before process exit")
	var brain: RefCounted=faculty.brain
	var snapshot:={"kind":"synthetic native process restart fixture; offline and authored provider output","writer_pid":OS.get_process_id(),
		"host_profile":identity,"selected_character":str(game.characters.selected),"saved_at":int(Time.get_unix_time_from_system()),
		"relationships":brain.relationships,"conversations":brain.conversations,"biographies":brain.biographies,"biography_records":brain.biography_records,
		"processed_events":brain.processed_events,"belief_revisions":brain.belief_revisions,"mind":faculty.character_mind.export_state(),
		"population":students.population.people,"next_index":students.population.next_index,"custom_student":custom_id}
	var file:=FileAccess.open(evidence_path,FileAccess.WRITE)
	check(file!=null,"Synthetic expected invariants file opens")
	if file!=null:file.store_string(JSON.stringify(snapshot));file.flush();file.close()

func read_phase() -> void:
	var parser:=JSON.new()
	check(parser.parse(FileAccess.get_file_as_string(evidence_path))==OK,"Reader opens the writer's synthetic expectations")
	if not parser.data is Dictionary:return
	var expected: Dictionary=parser.data
	var faculty: Node=game.faculty
	var brain: RefCounted=faculty.brain
	var students: Node=game.lecture_classes.classroom_students
	var identity:=str(game.school.local_identity)
	check(OS.get_process_id()!=int(expected.writer_pid),"Reader is a different native operating-system process")
	check(identity==str(expected.host_profile) and str(game.characters.selected)==str(expected.selected_character),"Restart reselects the same actual host/character identity without injection")
	for field in ["relationships","conversations","biographies","biography_records","processed_events","belief_revisions"]:
		check(same(brain.get(field),expected[field]),"Complete persisted %s survives the actual Main restart"%field)
	check(same(students.population.people,expected.population) and students.population.next_index==int(expected.next_index),"Every saved roster profile and allocator index survives process restart")
	var student: Dictionary=students.population.profile_for(expected.custom_student)
	check(student.name=="Iris Restart Fixture" and absf(float(student.traits.patience)-.317)<.000000001,"Customized identity and independent trait were loaded, not regenerated from an index")
	check(faculty.brain.character_biography(Profiles.teacher("mr_bro")).get(BIO_TOPIC,"")==BIO_DETAIL,"Delivered biography is available to a fresh process and any listener")
	check(brain.recall("ms_bird_heart",identity).size()==20 and brain.relationship("ms_bird_heart",identity).facts.size()>=20,"Long conversation and all personal facts remain attached to the actual player")
	check(brain.recall("ms_bird_heart","unrelated-reader").is_empty(),"A different speaker receives no inherited personal conversation")
	var recalled: Dictionary=brain.character_context(Profiles.teacher("ms_bird_heart"),identity,"What did I do with my aunt in her garage?","mechanics")
	check("radio fixture" in str(recalled.reported_facts) and not recalled.topic_summaries.is_empty(),"Fresh-process retrieval uses the saved narratives and grounded topic summaries")
	check(same(faculty.character_mind.disengagements,expected.mind.disengagements),"Individual conversation decisions survive session startup")
	var recovered_dimensions:=0
	for id in expected.mind.moods:
		check(faculty.character_mind.moods.has(id),"Saved affect owner %s remains present"%id)
		if not faculty.character_mind.moods.has(id):continue
		var person: Dictionary=Profiles.teacher(id) if Roster.has(id) else students.population.profile_for(id)
		var saved: Dictionary=expected.mind.moods[id]
		var actual: Dictionary=faculty.character_mind.context(person,Time.get_ticks_msec())
		check(actual.emotions.size()==16 and same(faculty.character_mind.moods[id].history,saved.history),"All emotional dimensions and the full saved experience history survive for %s"%id)
		var elapsed:=maxf(0.,float(Time.get_unix_time_from_system())-float(saved.at))
		var predicted: Dictionary=saved.values.duplicate(true)
		Affect.recover(predicted,person.traits,elapsed)
		for emotion in saved.values:
			var value:=float(actual.emotions[emotion])
			check(is_finite(value) and value>=0. and value<=1. and absf(value-float(predicted[emotion]))<.006,"Restart %s/%s agrees with elapsed recovery rather than reset"%[id,emotion])
			if absf(value-float(saved.values[emotion]))>.00001:recovered_dimensions+=1
	check(int(Time.get_unix_time_from_system())>int(expected.saved_at) and recovered_dimensions>0,"A real elapsed interval produces gradual recovery in the fresh process")
	check(faculty.character_mind.context(Profiles.teacher("brian"),Time.get_ticks_msec()).emotions.anger>.1,"Meaningful anger is retained rather than cleared by startup")
	check(not brain.memory_blocked and not students.population.persistence_blocked,"Both restored persistence systems remain usable")
