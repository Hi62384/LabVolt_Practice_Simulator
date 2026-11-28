extends SceneTree
## Real issued assessment, local idle decisions, and controlled delayed social
## generation. Provider replies here are fixtures, not live model evidence.
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Pipeline=preload("res://scripts/campus/academics/character_interaction.gd")
const ROOM:="ac_lab"
var checks:=0
var failures: Array[String]=[]

class FixtureClient extends "res://scripts/campus/ai/host_openai_client.gd":
	signal released
	var online:=true
	var requests: Array[Dictionary]=[]
	var opening_count:=0
	var hold_character:=""
	var held:=false
	var biography_topic:="fixture_delivered_project"
	var biography_detail:="I built a small wooden boat last summer."
	var openings: Array[String]=[
		"I could use a quiet walk after class.",
		"The campus garden looks peaceful today.",
		"I miss spending afternoons at the park.",
		"I enjoy having a little time outside in the evening.",
	]
	func _ready() -> void:pass
	func ready_for_class() -> bool:return online
	func moderate(_input: String) -> Dictionary:return {"ok":true,"flagged":false}
	func moderate_context(input: String,_metadata: Dictionary) -> Dictionary:return await moderate(input)
	func interpret_character(_instructions: String,_context: Dictionary,_dialogue: String) -> Dictionary:
		return {"ok":true,"text":JSON.stringify({"event":"chat","tone":"neutral","severity":0.,"meaning":"A nearby classmate shares a brief unrelated social remark.","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]})}
	func reply(context: Dictionary,speech: String,biography: Variant=null)->Dictionary:
		return {"ok":true,"text":JSON.stringify({"speech":speech,"biography":biography,
			"interpretation":{"event":"chat","tone":"neutral","severity":0.,"meaning":"A nearby classmate shares a brief unrelated social remark.","domain":"conversation","question_kind":"casual","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]},
			"delivery":{"emotion":str(context.get("emotional_state",{}).get("emotion","steady")),"knowledge_mode":"personal_conversation"}})}
	func respond_character(instructions: String,context: Dictionary,dialogue: String,_visual:=false) -> Dictionary:
		requests.append({"instructions":instructions,"context":context.duplicate(true),"dialogue":dialogue})
		if context.character.role=="teacher":return reply(context,"Please work independently on your own paper.")
		if dialogue.is_empty():
			var speech:=openings[mini(opening_count,openings.size()-1)]
			opening_count+=1
			return reply(context,speech)
		if str(context.character.id)==hold_character:
			hold_character="";held=true;busy=true
			await released
			held=false;busy=false
		return reply(context,biography_detail,{"topic":biography_topic,"detail":biography_detail})

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("ASSIGNMENT BEHAVIOR FAIL: "+message)

func settle(faculty: Node) -> void:
	var deadline:=Time.get_ticks_msec()+3000
	while faculty.character_jobs>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(faculty.character_jobs==0,"Delayed character work completed")

func settle_presentation(faculty: Node,actor: String) -> void:
	# This fixture disables local sound/captions, but the real presentation
	# lifecycle still finishes on a process frame rather than synchronously.
	var deadline:=Time.get_ticks_msec()+2000
	while faculty.student_speech_pending(actor) and Time.get_ticks_msec()<deadline:await process_frame
	check(not faculty.student_speech_pending(actor),"The opening presentation completes before the reply is delivered")

func prepared_actor(students: Node,index: int,point: Vector3,now: float,style: String) -> Dictionary:
	var person: Dictionary=students.population.profile_for("campus_student_%02d"%index)
	var t: Dictionary=person.traits
	t.merge({"study_habits":0.,"organization":0.,"academic_motivation":0.,"independence":0.,"curiosity":0.,
		"initiative":0.,"sociability":0.,"playfulness":0.,"mischievousness":0.,"cooperativeness":0.,"generosity":0.,
		"risk_taking":0.,"misbehavior":0.,"respect_for_authority":1.,"energy":1.,"laziness":0.,"attention_span":.5,
		"impulsiveness":0.,"focus":.2,"shyness":0.,"anxiety":0.,"stress_tolerance":1.,"confrontation":0.},true)
	if style=="focused":t.merge({"study_habits":1.,"organization":1.,"academic_motivation":1.,"independence":1.,"focus":1.,"attention_span":1.},true)
	elif style=="tired":t.merge({"energy":0.,"laziness":1.},true)
	elif style=="phone":t.merge({"misbehavior":1.,"respect_for_authority":0.,"risk_taking":1.,"attention_span":.5},true)
	return {"profile":person,"seat":point,"position":point,"arrival":now-1.,"arrived":true,"seated":true,"standing":false,
		"has_seat":true,"walking":false,"action":"listening","next":now,"turns":0,"academic_due":0.,"behavior_started":now}

func render_check(students: Node,activity: Dictionary,member: Dictionary,now: float,seen: Dictionary) -> void:
	var action:=str(member.action)
	if action not in ["sleeping","using phone","working","studying"] or seen.has(action):return
	seen[action]=true
	check(Students._activity_pose(action) in Motion.POSES,"Selected %s has an implemented body pose"%action)
	students.render(ROOM,{ROOM:{"classmates":students.snapshot(activity,now)}},.35)
	var model: Node3D=students.models.get(str(activity.id)+":"+str(member.profile.id))
	check(is_instance_valid(model),"Selected %s renders an actual NPC model"%action)
	if not is_instance_valid(model):return
	if action=="using phone":check(model.get_node("Body/ArmR/StudentPhone").visible,"Phone behavior displays the held phone prop")
	elif action=="sleeping":check(float(model.get_node("Body/Head").rotation.x)>.2,"Sleep behavior visibly lowers the head")
	else:check(model.get_node("StudentNotebook").visible,"Quiet work displays the student's paper/notebook")

func run() -> void:
	create_timer(75.).timeout.connect(func():printerr("ASSIGNMENT BEHAVIOR TIMEOUT");quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 2:await process_frame
	game.player.set_physics_process(false)
	game.faculty.set_process(false);game.lecture_classes.set_process(false);game.school.set_process(false)
	game.client_preferences.values.teacher_speech=false;game.client_preferences.values.teacher_subtitles=false
	var original: Node=game.host_openai;original.enabled=false
	var client:=FixtureClient.new();game.add_child(client);game.host_openai=client
	var classes: Node=game.lecture_classes
	var students: Node=classes.classroom_students
	Legacy.seed(students.population,24) # Explicit historical identities; no offline AI-generation claim.
	var faculty: Node=game.faculty
	game.player.global_position=classes.signs[ROOM].desk
	check(classes._start(ROOM,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":0})=="","Actual lab classroom starts")
	var activity: Dictionary=classes.classes.get(ROOM,{})
	if activity.is_empty():game.queue_free();await process_frame;quit(1);return
	check(classes._sign(1,ROOM)=="","The human participant signs into the actual assessment")
	var now: float=classes._now()
	var point: Vector3=classes.signs[ROOM].desk+Vector3(0,0,-3.)
	var focused:=prepared_actor(students,14,point,now,"focused")
	var tired:=prepared_actor(students,15,point+Vector3(0,0,-4.),now,"tired")
	var phone:=prepared_actor(students,16,point+Vector3(1.2,0,0),now,"phone")
	activity.classmates={focused.profile.id:focused,tired.profile.id:tired,phone.profile.id:phone}
	# Store the controlled independent traits in the same authority used by
	# every subsequent local decision, rather than editing a stale projection.
	for member in activity.classmates.values():students.population.people[member.profile.id]=member.profile.duplicate(true)
	Legacy.sync(students.population)
	for member in activity.classmates.values():faculty.character_mind.moods.erase(member.profile.id)
	activity.phase="lesson";activity.deadline=now+300.
	check(classes._begin_assignment(ROOM,activity),"Real generated assessment is issued")
	activity.classmate_assessment.private_autonomy_probe="UNRELEASED_AUTONOMY_ASSESSMENT"
	var setup_requests:=client.requests.size()
	var human_state:=JSON.stringify(activity.students)
	var project_state:=JSON.stringify(activity.classmate_assessment)
	var papers_state:=JSON.stringify(game.school.papers)
	var marks_state:=JSON.stringify(game.school.archive)
	var deadlines: Dictionary={}
	var actions: Dictionary={}
	var rendered: Dictionary={}
	for member in activity.classmates.values():
		deadlines[member.profile.id]=member.academic_due
		actions[member.profile.id]={}
		check(float(member.next)<float(member.academic_due),"Body behavior can change before its independent submission deadline")
	faculty.character_mind.feel(phone.profile,"idle",1.,Time.get_ticks_msec())
	for tick in 150:
		var at:=now+float(tick)
		students.step(activity,at,.1,ROOM)
		for member in activity.classmates.values():
			actions[member.profile.id][member.action]=true
			check(is_equal_approx(float(member.academic_due),float(deadlines[member.profile.id])),"Body/attention choices preserve the submission clock")
			if at<float(member.academic_due):check(not member.get("submitted",false),"Personality behavior cannot submit work before the academic deadline")
			render_check(students,activity,member,at,rendered)
	check(actions[focused.profile.id].has("working") or actions[focused.profile.id].has("studying"),"Focused student selects supported quiet work")
	check(actions[tired.profile.id].has("sleeping"),"Low-energy student selects real sleep behavior")
	check(actions[phone.profile.id].has("using phone"),"Distractible student can select actual phone use")
	check(actions[focused.profile.id]!=actions[tired.profile.id] and actions[tired.profile.id]!=actions[phone.profile.id],"Contrasting independent traits produce distinct observed activity histories")
	check(client.requests.slice(setup_requests).all(func(request):return request.context.character.role=="teacher" and request.context.has("discipline")),"Routine idle choices make no generation request; only actual perceived discipline may speak")
	for member in activity.classmates.values():
		check(member.get("submitted",false) and not member.get("removed_from_class",false) and not member.has("walk"),"Each student submits through existing authority without leaving the room")
		var self_memory: Dictionary=faculty.brain.relationship(member.profile.id,member.profile.id)
		check(self_memory.get("episodes",[]).filter(func(episode):return episode.get("source","")=="host_activity" and episode.get("activity",{}).get("kind","")=="assessment").size()==1,"Submission adds exactly one authoritative learning-memory event")
	var learned:=JSON.stringify(students.learning)
	students.step(activity,now+180.,.1,ROOM)
	check(JSON.stringify(students.learning)==learned,"Later idle ticks do not award duplicate learning")
	check(JSON.stringify(activity.students)==human_state and JSON.stringify(activity.classmate_assessment)==project_state and JSON.stringify(game.school.papers)==papers_state and JSON.stringify(game.school.archive)==marks_state,"Autonomy leaves human answers, issued work, submissions and official marks unchanged")

	# A socially motivated assessment choice can make one bounded, unrelated
	# aside. The sleeper is not treated as an awake conversation partner.
	tired.action="sleeping";tired.next=now+10000.
	for member in [phone,focused]:
		member.profile.traits.merge({"focus":.2,"talkativeness":1.,"attention_span":.3,"study_habits":0.,"organization":0.,"academic_motivation":0.,"independence":0.,"misbehavior":0.,"initiative":1.,"sociability":1.,"playfulness":1.,"mischievousness":1.,"risk_taking":1.},true)
		faculty.character_mind.moods.erase(member.profile.id)
		member.next=now+180.
		students.population.people[member.profile.id]=member.profile.duplicate(true)
	Legacy.sync(students.population)
	activity.social_next=0.;activity.last_social_at=-1000.;students.social_next_global=0.
	# Independent simulated episodes share a wall-clock minute in this test;
	# the scheduler's real rolling budget is verified separately.
	students.background_turns.clear()
	for tick in 100:
		students.step(activity,now+181.+float(tick)*10.,.1,ROOM)
		if activity.has("classmate_reply"):break
	check(activity.has("classmate_reply") and client.requests.filter(func(request):return request.context.character.role=="student").size()==2,"An actual selected social idle action generates one opening and one response")
	if not activity.has("classmate_reply"):game.host_openai=original;game.queue_free();await process_frame;quit(1);return
	var pending: Dictionary=activity.classmate_reply
	var speaker: Dictionary=activity.classmates[pending.speaker]
	var listener: Dictionary=activity.classmates[pending.listener]
	var heard: Array=faculty.brain.recall(listener.profile.id,speaker.profile.id)
	check(heard.size()==1 and str(heard[0].student)==str(speaker.line) and str(heard[0].teacher)=="","Listener remembers the actual opening before its generated reply is displayed")
	check(not faculty.brain.character_biography(listener.profile).has(client.biography_topic),"Generated biography is not canon before delivery")
	var familiarity:=int(faculty.brain.relationship(listener.profile.id,speaker.profile.id).familiarity)
	check(Pipeline.assessment_output_safe(str(speaker.line)) and Pipeline.assessment_output_safe(str(pending.line)),"Both assessment utterances pass deterministic output protection")
	for request in client.requests.slice(setup_requests):
		check(not request.context.has("teaching_step") and not request.context.has("classroom") and not request.context.has("current_display") and not request.context.has("station_readings"),"Assessment aside contains no work/board/equipment context")
		check(not JSON.stringify(request).contains("UNRELEASED_AUTONOMY_ASSESSMENT"),"Private assessed content never reaches the social generator")
	students._show_preclass_reply(activity,float(pending.at)+.1)
	check(activity.has("classmate_reply") and not faculty.brain.character_biography(listener.profile).has(client.biography_topic),"Pending opening prevents an early reply and biography commit")
	await settle_presentation(faculty,str(speaker.profile.id))
	students._show_preclass_reply(activity,float(pending.at)+.1);await settle(faculty)
	check(faculty.brain.recall(listener.profile.id,speaker.profile.id).size()==1 and int(faculty.brain.relationship(listener.profile.id,speaker.profile.id).familiarity)==familiarity,"Actual reply completes the perceived event without double relationship effects")
	check(faculty.brain.character_biography(listener.profile).get(client.biography_topic,"")==client.biography_detail,"An actually delivered biographical detail becomes canon")
	check(faculty.brain.recall(speaker.profile.id,listener.profile.id).size()==2,"The initiator remembers the response only after hearing it")
	var generated:=client.requests.size()
	for tick in 180:students._before_class(activity,float(activity.last_social_at)+float(tick)/6.,ROOM)
	check(client.requests.size()==generated,"Repeated frames cannot turn the brief aside into constant AI generation")

	# Cancel while response generation is held, after the opening was heard.
	client.biography_topic="fixture_cancelled_project";client.biography_detail="I restored a brass lantern with my aunt."
	client.hold_character=listener.profile.id
	students.background_turns.clear()
	var before_heard: int=faculty.brain.recall(listener.profile.id,speaker.profile.id).size()
	activity.social_pending=true
	students._start_social_exchange(activity,speaker,listener,faculty.brain.relationship(speaker.profile.id,listener.profile.id),faculty.brain.relationship(listener.profile.id,speaker.profile.id),ROOM)
	check(client.held,"The real reply-generation callback is held after perception")
	check(faculty.brain.recall(listener.profile.id,speaker.profile.id).size()==before_heard+1,"Heard input is durable before the held response is generated")
	activity.phase="results";client.released.emit();await settle(faculty)
	check(not activity.has("classmate_reply") and not faculty.brain.character_biography(listener.profile).has(client.biography_topic),"Phase change cancels late speech and prevents unheard biography canon")
	check(str(faculty.brain.recall(listener.profile.id,speaker.profile.id).back().teacher)=="","Cancelled generation retains heard input with no fabricated spoken reply")

	# Cancel a generated reply during its presentation delay as a separate race.
	activity.phase="assignment"
	client.biography_topic="fixture_unshown_project";client.biography_detail="I painted a wooden birdhouse with my brother."
	students.background_turns.clear()
	activity.social_pending=true
	await students._start_social_exchange(activity,speaker,listener,faculty.brain.relationship(speaker.profile.id,listener.profile.id),faculty.brain.relationship(listener.profile.id,speaker.profile.id),ROOM)
	check(activity.has("classmate_reply"),"A generated reply waits for its actual presentation time")
	if activity.has("classmate_reply"):
		var delayed: Dictionary=activity.classmate_reply
		var initiating_turns: int=faculty.brain.recall(speaker.profile.id,listener.profile.id).size()
		activity.phase="results"
		students._show_preclass_reply(activity,float(delayed.at)+.1)
		check(not activity.has("classmate_reply") and not faculty.brain.character_biography(listener.profile).has(client.biography_topic),"An expired class phase discards unshown reply and biography")
		check(str(faculty.brain.recall(listener.profile.id,speaker.profile.id).back().teacher)=="" and faculty.brain.recall(speaker.profile.id,listener.profile.id).size()==initiating_turns,"Unshown reply is absent from both directional histories")

	activity.phase="assignment"
	client.biography_topic="fixture_wrong_host_project";client.biography_detail="I carved a wooden chess piece with my cousin."
	students.background_turns.clear()
	activity.social_pending=true
	await students._start_social_exchange(activity,speaker,listener,faculty.brain.relationship(speaker.profile.id,listener.profile.id),faculty.brain.relationship(listener.profile.id,speaker.profile.id),ROOM)
	check(activity.has("classmate_reply"),"Another reply is prepared under the original host profile")
	if activity.has("classmate_reply"):
		var delayed: Dictionary=activity.classmate_reply
		var profile_id:=str(game.school.local_identity)
		game.school.local_identity="different-host-before-display"
		students._show_preclass_reply(activity,float(delayed.at)+.1)
		game.school.local_identity=profile_id
		check(not activity.has("classmate_reply") and not faculty.brain.character_biography(listener.profile).has(client.biography_topic),"A profile change prevents delayed speech and canonical detail from crossing ownership")

	# An unavailable provider produces no fabricated social dialogue, even
	# for familiar study partners during an assessment.
	client.online=false
	var history: Dictionary=faculty.brain.relationship(speaker.profile.id,listener.profile.id).duplicate(true)
	var reverse: Dictionary=faculty.brain.relationship(listener.profile.id,speaker.profile.id).duplicate(true)
	history.familiarity=4;history.study_sessions=4;reverse.study_sessions=4
	generated=client.requests.size()
	speaker.erase("line");listener.erase("line")
	activity.social_pending=true
	await students._start_social_exchange(activity,speaker,listener,history,reverse,ROOM)
	check(str(speaker.get("line","")).is_empty() and not activity.has("classmate_reply"),"Offline assessment initiation produces no invented character dialogue")
	if activity.has("classmate_reply"):
		var delayed: Dictionary=activity.classmate_reply
		check(Pipeline.assessment_output_safe(str(delayed.line)),"Offline classmate response is safe for individual assessment work")
		students._show_preclass_reply(activity,float(delayed.at)+.1);await settle(faculty)
	check(client.requests.size()==generated,"Offline assessment recovery makes no generation request")
	check(JSON.stringify(activity.students)==human_state and JSON.stringify(activity.classmate_assessment)==project_state and JSON.stringify(game.school.papers)==papers_state and JSON.stringify(game.school.archive)==marks_state,"Social initiation, delay and cancellation never mutate official assessment work")
	game.host_openai=original
	print("ASSIGNMENT_STUDENT_BEHAVIOR %s checks=%d failures=%d actions=%s"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),str(actions)])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
