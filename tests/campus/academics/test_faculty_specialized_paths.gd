extends SceneTree
## Real Main/Faculty paths with a local provider fixture. This verifies timing,
## delivery and privacy contracts; it is not evidence of live model quality.
const ROOM:="ac_lab"
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
var checks:=0
var failures: Array[String]=[]

class FixtureClient extends "res://scripts/campus/ai/host_openai_client.gd":
	signal released
	var online:=false
	var hold_next:=false
	var held:=false
	var requests: Array[Dictionary]=[]
	var replies: Array[String]=[
		"Compare each connection with the diagram on the board before changing it.",
		"Read the instrument scale carefully before you record the measurement.",
		"Watch the connection order while I explain this part of the circuit.",
		"Take a moment to review your notes against the final point on the board.",
		"I am leaving now; the next office-hours shift is yours.",
		"I have arrived for my shift. I will get settled here.",
	]
	func _ready() -> void:pass
	func ready_for_class() -> bool:return online
	func moderate(_input: String) -> Dictionary:return {"ok":true,"flagged":false}
	func interpret_character(_instructions: String,_context: Dictionary,_dialogue: String) -> Dictionary:
		return {"ok":true,"text":JSON.stringify({"event":"chat","tone":"neutral","severity":0.,"meaning":"A colleague is speaking about the office-hours shift.","domain":"conversation","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]})}
	func respond_character(instructions: String,context: Dictionary,dialogue: String,_visual:=false) -> Dictionary:
		var index:=requests.size()
		requests.append({"instructions":instructions,"context":context.duplicate(true),"dialogue":dialogue})
		if hold_next:
			hold_next=false;held=true;busy=true
			await released
			held=false;busy=false
		return {"ok":true,"text":JSON.stringify({"speech":replies[mini(index,replies.size()-1)],"biography":null,
			"interpretation":{"event":"chat","tone":"neutral","severity":0.,"meaning":"A colleague is speaking about the office-hours shift.","domain":"conversation","question_kind":"casual","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]},
			"delivery":{"emotion":str(context.get("emotional_state",{}).get("emotion","steady")),"knowledge_mode":"personal_conversation"}})}

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FACULTY SPECIALIZED FAIL: "+message)

func settle(faculty: Node) -> void:
	var deadline:=Time.get_ticks_msec()+3000
	while faculty.character_jobs>0 and Time.get_ticks_msec()<deadline:await process_frame
	check(faculty.character_jobs==0,"All character callbacks completed")

func run() -> void:
	create_timer(65.).timeout.connect(func():printerr("FACULTY SPECIALIZED TIMEOUT");quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 2:await process_frame
	game.player.set_physics_process(false)
	game.faculty.set_process(false);game.lecture_classes.set_process(false);game.school.set_process(false)
	game.client_preferences.values.teacher_speech=false
	game.client_preferences.values.teacher_subtitles=false
	var original_client: Node=game.host_openai
	original_client.enabled=false
	var client:=FixtureClient.new();game.add_child(client);game.host_openai=client
	var faculty: Node=game.faculty
	var school: Node=game.school
	check(game.front.in_game and faculty._sync_character_profile(),"Actual Singleplayer selected a host namespace")
	var started: Dictionary=school.start_activity({"mode":"Course","course_id":"ELM253","kind":"lab","week":1,"difficulty":0,"ai_teaching":true,"teaching_seconds":420.})
	check(started.get("ok",false),"Actual formal Course start succeeded: "+str(started))
	if not started.get("ok",false):game.queue_free();await process_frame;quit(1);return
	school.phase="lesson";school.remaining=school.teaching_seconds
	school.project.private_specialized_probe="UNRELEASED_FORMAL_SECRET"
	school.activity.private_specialized_probe="UNRELEASED_FORMAL_SECRET"
	game.player.global_position=game.lecture_classes.signs[ROOM].desk
	faculty._sync_lab_teachers()
	var activity: Dictionary=faculty._formal_activity(ROOM)
	var teacher:=str(activity.teacher)
	var listener:="classroom:ELM253"
	check(activity.has("deadline") and absf(float(activity.get("deadline",0.))-game.lecture_classes._now()-float(school.remaining))<.5,"Formal lesson includes its remaining-time deadline")
	check(is_equal_approx(float(activity.get("teaching_seconds",0.)),float(school.teaching_seconds)),"Formal lesson uses the authored teaching duration")
	var serial:=int(faculty.speech_serial.get(ROOM,0))
	var before: int=faculty.brain.recall(teacher,listener).size()
	check(faculty.formal_lesson_ready(),"Offline formal cue releases the lesson wait")
	check(int(faculty.speech_serial.get(ROOM,0))==serial,"Offline formal lesson does not impersonate generated teacher speech")
	check(not str(school.activity.get("ai_status","")).is_empty(),"Offline formal lesson exposes the technical service status")
	check(faculty.brain.recall(teacher,listener).size()==before+1 and str(faculty.brain.recall(teacher,listener).back().get("teacher",""))=="","Offline formal lesson records the observed intention once with no invented speech")
	var trace: Dictionary=faculty.character_interaction.diagnostics.back()
	check(trace.source=="technical_unavailable" and not trace.delivered and trace.speech.is_empty(),"Offline formal cue exposes its actual silent outcome in shared diagnostics")

	client.online=true
	faculty.ai_stage.erase(ROOM)
	before=faculty.brain.recall(teacher,listener).size()
	check(faculty.formal_lesson_ready(),"A completed generated formal cue releases the wait")
	check(client.requests.size()==1,"Formal lesson calls the shared character generation API")
	if not client.requests.is_empty():
		var request: Dictionary=client.requests.back()
		check(request.dialogue=="" and request.context.get("initiate",false),"A lecture is a genuine initiation with no fabricated student quote")
		check(request.context.has("teaching_step") and not request.context.teaching_step.is_empty(),"Generated lecture receives the released lesson board without a duplicate classroom payload")
		check(not JSON.stringify(request).contains("UNRELEASED_FORMAL_SECRET"),"Private formal activity/project fields never reach generation")
	check(faculty.brain.recall(teacher,listener).size()==before+1,"Generated formal cue is recorded exactly once after presentation")
	check(faculty.character_interaction.diagnostics.back().source=="ai","Local provider fixture exercises generation rather than offline recovery")

	# The delayed reply belongs to the lesson phase captured before the await.
	faculty.ai_stage.erase(ROOM);client.hold_next=true
	serial=int(faculty.speech_serial.get(ROOM,0));before=faculty.brain.recall(teacher,listener).size()
	check(not faculty.formal_lesson_ready() and client.held,"Formal lesson waits for the held provider reply")
	school.phase="assignment"
	client.released.emit();await settle(faculty)
	check(int(faculty.speech_serial.get(ROOM,0))==serial,"A late lesson reply cannot speak during assessment")
	check(faculty.brain.recall(teacher,listener).size()==before,"An undelivered late lesson does not enter conversation memory")
	check(not school.activity.get("ai_waiting",false) and not school.activity.has("ai_wait_started") and not school.activity.has("ai_wait_key") and not faculty.ai_stage.has(ROOM),"Cancelled lesson clears its own waiting state and retry key")

	# Advancing the actual lesson clock queues a newer stage while one response
	# is in flight. Completing the older request must preserve the newer wait.
	school.phase="lesson";school.remaining=school.teaching_seconds
	client.hold_next=true
	check(not faculty.formal_lesson_ready() and client.held,"A second held formal request starts")
	var first_key:=str(school.activity.get("ai_wait_key",""))
	school.remaining=20.
	check(not faculty.formal_lesson_ready(),"A later released lesson stage waits while the provider is busy")
	var next_key:=str(school.activity.get("ai_wait_key",""))
	check(not next_key.is_empty() and next_key!=first_key,"The new lesson stage has an independent wait key")
	client.released.emit();await settle(faculty)
	check(school.activity.get("ai_waiting",false) and str(school.activity.get("ai_wait_key",""))==next_key,"An older callback preserves the newer stage's pending state")
	check(faculty.formal_lesson_ready() and not school.activity.get("ai_waiting",false),"The newer stage completes normally after the provider becomes available")
	check(str(faculty.ai_stage.get(ROOM,""))==next_key,"The completed stage is the new released stage")

	# Real office-hours rotation: provider timeout precedes any opening speech.
	school.phase="complete"
	check(school.start_activity({"mode":"Freeplay"}).get("ok",false),"The completed formal session returns to Freeplay")
	faculty._sync_lab_teachers()
	check(faculty._lab_visit(ROOM).get("phase","")=="office_hours","Real office-hours visit is available")
	client.hold_next=true
	serial=int(faculty.speech_serial.get(ROOM,0))
	faculty._rotate(ROOM)
	var exchange: Dictionary=faculty.lab_handoffs.get(ROOM,{})
	check(not exchange.is_empty() and client.held,"Office-hours rotation holds the outgoing generated opening")
	if not exchange.is_empty():
		var outgoing:=str(exchange.outgoing);var incoming:=str(exchange.incoming)
		check(str(exchange.get("handoff",""))=="" and exchange.get("waiting",false),"A pending generated handoff has no spoken opening")
		check(not exchange.has("fallback"),"Pending handoff does not store canned fallback dialogue")
		check(int(faculty.speech_serial.get(ROOM,0))==serial,"A genuinely pending handoff does not start speech playback")
		var outgoing_before: int=faculty.brain.recall(outgoing,incoming).size()
		var incoming_before: int=faculty.brain.recall(incoming,outgoing).size()
		faculty._finish_lab_handoffs(int(exchange.started)+35001)
		check(faculty.current.get(ROOM,"")==incoming and not faculty.lab_handoffs.has(ROOM),"A stalled provider does not prevent the real shift change")
		var received: Array=faculty.brain.recall(incoming,outgoing)
		check(received.size()==incoming_before+1,"Incoming colleague records its observed shift change once")
		if received.size()>incoming_before:
			check(str(received.back().get("student",""))=="" and str(received.back().get("teacher","")).is_empty(),"A busy provider fabricates neither the timed-out opening nor an incoming reply")
		check(faculty.brain.recall(outgoing,incoming).size()==outgoing_before,"Outgoing colleague does not remember an unheard incoming reply")
		var after_outgoing: int=faculty.brain.recall(outgoing,incoming).size()
		var after_incoming: int=faculty.brain.recall(incoming,outgoing).size()
		serial=int(faculty.speech_serial.get(ROOM,0))
		client.released.emit();await settle(faculty)
		check(int(faculty.speech_serial.get(ROOM,0))==serial,"Late outgoing opening is cancelled after the shift changed")
		check(faculty.brain.recall(outgoing,incoming).size()==after_outgoing and faculty.brain.recall(incoming,outgoing).size()==after_incoming,"Late handoff callback creates no duplicate or unheard conversation")

		# An intentionally silent opening has the same empty heard-message contract.
		# Exercise the real incoming handler with that explicit delivery fixture.
		var silent_exchange:={"outgoing":outgoing,"incoming":incoming,"handoff":"","fallback":"This opening was never spoken."}
		var request_count:=client.requests.size()
		await faculty._answer_staff_handoff(ROOM,silent_exchange)
		check(client.requests.size()==request_count+2,"A silent opening generates one incoming initiation and one outgoing listener interpretation")
		if client.requests.size()>request_count:
			var request: Dictionary=client.requests[request_count]
			check(request.dialogue=="" and request.context.get("initiate",false) and request.context.get("observed_event",{}).get("kind","")=="staff_shift_started","Silent handoff is observed as a shift change, with no invented quote")
			check(not JSON.stringify(request).contains("This opening was never spoken."),"Unused handoff fallback is absent from the incoming prompt")
		check(faculty.brain.recall(incoming,outgoing).size()==after_incoming+1 and faculty.brain.recall(outgoing,incoming).size()==after_outgoing+1,"Silent-opening reply is remembered in each heard direction exactly once")

	var walking: Dictionary=faculty._character_action_status("approach",true)
	var gesture: Dictionary=faculty._character_action_status("nod",true)
	check(walking.pending and not walking.completed and not walking.succeeded and walking.status=="started","Accepting a route does not claim completed arrival")
	check(gesture.completed and gesture.succeeded and not gesture.pending,"An immediately applied gesture reports completion")
	check(faculty.character_jobs==0,"No character work remains after specialized paths")
	game.host_openai=original_client
	print("FACULTY_SPECIALIZED_PATHS %s checks=%d failures=%d (local provider fixture, not live AI)"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
