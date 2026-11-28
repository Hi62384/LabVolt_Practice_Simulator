extends SceneTree
## Actual Main UI, character pipeline and playback bookkeeping. Authored
## provider completions are held across close/reopen/switch races; no API or
## microphone hardware is used or claimed by this regression.
const Faculty=preload("res://scripts/campus/academics/faculty.gd")
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
var checks:=0
var failures: Array[String]=[]

class HeldClient extends "res://scripts/campus/ai/host_openai_client.gd":
	signal released
	var hold_model:=true
	var hold_transcription:=true
	var model_held:=false
	var transcription_held:=false
	var model_calls:=0
	var transcriptions:=0
	var transcription_metadata: Dictionary={}
	func _ready() -> void:enabled=true;tts_enabled=false
	func ready_for_class() -> bool:return true
	func configured() -> bool:return true
	func moderate(_input: String) -> Dictionary:return {"ok":true,"flagged":false}
	func moderate_context(input: String,_metadata: Dictionary) -> Dictionary:return await moderate(input)
	func transcribe_wav_context(_wav: PackedByteArray,metadata: Dictionary) -> Dictionary:
		transcriptions+=1;transcription_metadata=metadata
		if hold_transcription:
			transcription_held=true
			await released
			transcription_held=false
		# Deliberately return success even after cancellation. The faculty must
		# independently reject this stale completion before model generation.
		return {"ok":true,"text":"An authored microphone question."}
	func respond_character(_instructions: String,_context: Dictionary,_question: String,_visual:=false) -> Dictionary:
		model_calls+=1
		var progress: Variant=_context.get("_request_metadata",{}).get("_text_progress")
		if progress is Callable and progress.is_valid():
			progress.call("{\"speech\":\"An authored current conversation reply.\",")
		if hold_model:
			model_held=true
			await released
			model_held=false
		return {"ok":true,"text":JSON.stringify({"speech":"An authored current conversation reply.","action":null,"biography_facts":[],"belief_updates":[],
			"interpretation":{"event":"chat","tone":"neutral","severity":0.1,"meaning":"The player asks an ordinary social question.","question_kind":"casual","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","sincere":true,"memories":[]},
			"behavior":{"mode":"engage","intention":"Respond to the current question."},"delivery":{"emotion":"steady","knowledge_mode":"personal_conversation"}})}

func _initialize() -> void:run.call_deferred()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)

func settle(faculty: Node) -> void:
	var deadline:=Time.get_ticks_msec()+2500
	while (not faculty.ai_busy.is_empty() or faculty.character_jobs>0) and Time.get_ticks_msec()<deadline:await process_frame
	check(faculty.ai_busy.is_empty() and faculty.character_jobs==0,"Guarded asynchronous work releases its original reservation")

func submit(faculty: Node,text: String) -> void:
	faculty.conversation_input.text=text
	faculty._submit_question()

func run() -> void:
	create_timer(65.).timeout.connect(func():push_error("Manual conversation lifecycle timed out");quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	var faculty: Node=game.faculty
	var classes: Node=game.lecture_classes
	faculty.set_process(false);classes.set_process(false);game.school.set_process(false);game.player.set_physics_process(false)
	faculty.character_generation.cancel()
	var original: Node=game.host_openai;original.enabled=false
	var fixture:=HeldClient.new();game.add_child(fixture);game.host_openai=fixture
	game.client_preferences.values.teacher_speech=false
	game.client_preferences.values.teacher_subtitles=false
	if faculty.current.get("ac_lab","").is_empty():faculty._rotate("ac_lab")
	if faculty.current.get("dc_lab","").is_empty():faculty._rotate("dc_lab")
	faculty._sync_lab_teachers()
	var visit: Dictionary=faculty._ai_activity("ac_lab")
	var identity:=str(game.school.identities[1])
	game.player.global_position=faculty._teacher_position("ac_lab")
	faculty.open_conversation("ac_lab")
	var first_nonce:=str(faculty.manual_conversation_nonce)
	check(first_nonce.length()==32 and faculty.manual_conversations.has(1),"Opening the actual inspector establishes a selected per-peer conversation")
	var remembered: int=faculty.brain.recall(visit.teacher,identity).size()
	submit(faculty,"Tell me something about your interests.")
	check(fixture.model_held and fixture.model_calls==1,"Typed UI dispatch reaches one held actual character-generation call")
	check("Reply (verifying" in str(faculty.conversation_text.text) and "An authored current conversation reply." in str(faculty.conversation_text.text),"The actual inspector displays a moderated speech candidate before the held metadata finishes")
	var first_request:=str(faculty.manual_latest_request)
	check(not faculty._manual_question_request(1,first_nonce,1,first_request,"Duplicate typed message."),"A repeated typed request ID is rejected before generation")
	faculty.close_conversation()
	check(not faculty.conversation.visible and faculty.manual_detached and faculty.manual_conversation_nonce==first_nonce and faculty._voice_context_valid(1,{"mode":"manual","token":first_nonce,"request_id":first_request,"turn":1,"identity":identity,"room":"ac_lab","class_id":visit.id,"student":"","actor":visit.teacher}),"Hiding the inspector preserves its already submitted turn")
	fixture.released.emit();await settle(faculty)
	var detached_serial:=int(faculty.speech_serial.get("ac_lab",0))
	check(detached_serial>0 and not faculty.speech_player.was_cancelled("ac_lab",detached_serial),"Detached reply reaches the ordinary world speech path")
	check(faculty.brain.recall(visit.teacher,identity).size()>remembered,"A delivered detached response remains in conversation memory")
	faculty.open_conversation("ac_lab")
	check(faculty.manual_conversation_nonce==first_nonce and "authored current conversation reply" in str(faculty.conversation_text.text),"Reopening a detached teacher preserves its delivered reply and original session")
	faculty.close_conversation(true);faculty.open_conversation("ac_lab")
	var second_nonce:=str(faculty.manual_conversation_nonce)
	var fresh_prompt:=str(faculty.conversation_text.text)
	check(first_nonce!=second_nonce and not faculty._begin_manual_session(1,"ac_lab",visit.id,"",visit.teacher,first_nonce),"Explicit Goodbye retires the previous nonce and rejects a late begin")
	check(str(faculty.conversation_text.text)==fresh_prompt,"Reopened inspector starts with its own text state")

	var pcm:=PackedByteArray();pcm.resize(6400)
	var wav: PackedByteArray=Faculty.TeacherAI.wav_16k(pcm)
	faculty._send_voice_question("ac_lab",wav,"",visit.id,"chad" if visit.teacher!="chad" else "mr_bro")
	check(fixture.transcriptions==0 and str(faculty.manual_latest_request).is_empty(),"Manual audio cannot silently replace the explicitly captured selected teacher")
	faculty._send_voice_question("ac_lab",wav,"",visit.id,visit.teacher)
	var microphone_id:=str(faculty.manual_latest_request)
	check(fixture.transcription_held and fixture.transcriptions==1,"Manual microphone dispatch enters one contextual transcription")
	check(str(fixture.transcription_metadata.get("request_id","")).contains(microphone_id) and fixture.transcription_metadata.get("_valid") is Callable,"Transcription carries the unique request identity and live cancellation guard")
	check(not faculty._manual_question_request(1,second_nonce,1,microphone_id,wav) and fixture.transcriptions==1,"A repeated WAV upload cannot create duplicate transcription work")
	faculty.close_conversation();faculty.open_conversation("ac_lab")
	check(bool(fixture.transcription_metadata._valid.call()),"Hiding and reopening the same teacher retains an in-flight transcription")
	faculty.close_conversation(true);faculty.open_conversation("ac_lab")
	check(not bool(fixture.transcription_metadata._valid.call()),"Explicit Goodbye invalidates an in-flight transcription guard immediately")
	var before_models:=fixture.model_calls
	fixture.released.emit();await settle(faculty)
	check(fixture.model_calls==before_models,"A late successful transcript is discarded before model generation")

	submit(faculty,"A question before switching characters.")
	check(fixture.model_held,"The switching race starts from an actual held model request")
	game.player.global_position=faculty._teacher_position("dc_lab")
	faculty.open_conversation("dc_lab")
	var switched_nonce:=str(faculty.manual_conversation_nonce)
	var switched_prompt:=str(faculty.conversation_text.text)
	fixture.released.emit();await settle(faculty)
	check(faculty.conversation_room=="dc_lab" and str(faculty.conversation_text.text)==switched_prompt,"Switching to another NPC rejects the former NPC's late response")
	var dc_visit: Dictionary=faculty._ai_activity("dc_lab")
	check(faculty._begin_manual_session(1,"dc_lab",dc_visit.id,"",dc_visit.teacher,switched_nonce),"Repeating a current begin is idempotent")
	fixture.hold_model=false
	submit(faculty,"A current conversation question.");await settle(faculty)
	check("authored current conversation reply" in str(faculty.conversation_text.text),"The current nonce still delivers a valid model response to the inspector")
	var current_request:=str(faculty.manual_latest_request)
	faculty._begin_manual_session(1,"dc_lab",dc_visit.id,"",dc_visit.teacher,switched_nonce)
	check(not faculty._manual_question_request(1,switched_nonce,1,current_request,"Replay after repeated begin."),"Idempotent begin cannot reset the request deduplication counter")
	var spoken_serial:=int(faculty.speech_serial.get("dc_lab",0))
	check(spoken_serial>0 and faculty.manual_speech.has(faculty._voice_key("dc_lab",spoken_serial)),"The actual spoken reply is bound to its owning manual conversation")
	var anchor:=Node3D.new();game.add_child(anchor)
	faculty.speech_player.accept("independent-peer","Other speaker",1,"An unrelated pending utterance.",3,anchor,null,1.,{"expect_audio":true})
	faculty.close_conversation(true)
	check(faculty.speech_player.was_cancelled("dc_lab",spoken_serial) and faculty.speech_player.has_utterance("independent-peer",1),"Explicit Goodbye cancels the exact reply while preserving another utterance")
	faculty.open_conversation("dc_lab")
	faculty._manual_speech_started(switched_nonce,1,"late-envelope",41)
	check(faculty.speech_player.was_cancelled("late-envelope",41),"A stale in-transit speech registration is tombstoned before its envelope arrives")
	var fresh_text:=str(faculty.conversation_text.text)
	faculty._manual_dialogue_reply("dc_lab",dc_visit.teacher,"Stale UI text",switched_nonce,current_request)
	check(str(faculty.conversation_text.text)==fresh_text,"A delayed reliable status cannot update the next same-NPC session")

	# Independent remote peers use the production host admission and queue.
	# Reserve both while queuing so this section measures no provider activity.
	game.session.roster[2]={"name":"Fixture guest"};game.school.identities[2]="manual_fixture_guest"
	game.session.poses[2]={"position":game.player.global_position}
	faculty.ai_busy[1]="fixture";faculty.ai_busy[2]="fixture"
	var host_nonce:=str(faculty.manual_conversation_nonce)
	var guest_nonce:="22222222222222222222222222222222"
	check(faculty._begin_manual_session(2,"dc_lab",dc_visit.id,"",dc_visit.teacher,guest_nonce),"A second roster identity opens an independent manual conversation")
	check(faculty._manual_question_request(1,host_nonce,1,host_nonce+":1","Host queued turn.") and faculty._manual_question_request(2,guest_nonce,1,guest_nonce+":1","Guest queued turn."),"Identical per-peer turn numbers are independent and both enter the real queue")
	var guest_entry: Dictionary=faculty.questions.filter(func(entry):return int(entry.peer)==2)[0]
	faculty._end_manual_session(1,host_nonce)
	check(faculty.questions.size()==1 and int(faculty.questions[0].peer)==2 and faculty._voice_context_valid(2,guest_entry.voice_context),"Closing one peer removes only its queued work and leaves the other context valid")
	game.school.identities[2]="replacement_profile"
	check(not faculty._voice_context_valid(2,guest_entry.voice_context),"Replacing a connected peer's profile invalidates its old conversation context")
	game.school.identities[2]="manual_fixture_guest"
	faculty._end_manual_session(2,guest_nonce)
	check(not faculty._manual_question_request(2,guest_nonce,2,guest_nonce+":2",wav),"A late upload after host cancellation is rejected without transcription")
	for index in range(40):
		var nonce:="%032x"%(index+50)
		faculty._begin_manual_session(2,"dc_lab",dc_visit.id,"",dc_visit.teacher,nonce)
		faculty._end_manual_session(2,nonce)
	check(faculty.manual_retired_nonces[2].size()==32,"Repeated open/close cycles keep nonce replay history bounded per peer")
	faculty.ai_busy.clear();faculty.question_channels.clear()
	game.session.roster.erase(2);game.school.identities.erase(2);game.session.poses.erase(2)
	faculty._prune_dialogue()
	check(not faculty.manual_retired_nonces.has(2),"Disconnect cleanup removes the former peer's bounded tombstone storage")
	faculty.close_conversation()

	# The same nonce rules apply to actual eligible, rendered classroom students.
	var classmates: Node=classes.classroom_students
	Legacy.seed(classmates.population,24)
	game.player.global_position=classes.signs.ac_lab.desk
	check(classes._start("ac_lab",{"kind":"lab","course_id":"ELM253","week":1,"difficulty":1})=="","A real class starts with the eligible persistent student pool")
	var activity: Dictionary=classes.classes.ac_lab
	var member: Dictionary=activity.classmates.values()[0]
	member.arrival=classes._now()-10.;member.position=member.seat;member.arrived=true
	classes._publish();game.player.global_position=member.position+Vector3(.5,0,0)
	classmates.render("ac_lab",classes.public_classes,.1)
	faculty.open_conversation("ac_lab",member.profile.id,activity.id)
	fixture.hold_model=true
	submit(faculty,"A classmate question before closing.")
	check(fixture.model_held,"Student inspector routes through the same guarded manual request path")
	var student_nonce:=str(faculty.manual_conversation_nonce)
	faculty.close_conversation(true);faculty.open_conversation("ac_lab",member.profile.id,activity.id)
	var student_prompt:=str(faculty.conversation_text.text)
	fixture.released.emit();await settle(faculty)
	check(student_nonce!=str(faculty.manual_conversation_nonce) and str(faculty.conversation_text.text)==student_prompt,"A late classmate response cannot enter a reopened student inspector")
	faculty.close_conversation()
	game.host_openai=original
	print("MANUAL_CONVERSATION_LIFECYCLE %s checks=%d failures=%d source=actual UI and character pipeline, held authored completions, no live API or hardware"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
