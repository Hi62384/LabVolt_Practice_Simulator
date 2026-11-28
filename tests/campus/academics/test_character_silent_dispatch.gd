extends SceneTree
## Real Main, classmate action dispatch and memory with an authored provider.
## This proves runtime contracts, not live-model naturalness or rendering.
const ROOM := "ac_lab"
var failures: Array[String] = []
var checks := 0

class Provider extends "res://scripts/campus/ai/host_openai_client.gd":
	signal released
	var online := false
	var hold_next := false
	var held := false
	var calls := 0
	var gestures: Array = ["shrug", "wave", "teleport"]
	func _ready() -> void:pass
	func ready_for_class() -> bool:return online
	func moderate(_input: String) -> Dictionary:return {"ok":true,"flagged":false}
	func moderate_context(input: String,_metadata: Dictionary) -> Dictionary:return await moderate(input)
	func respond_character(_instructions: String,_context: Dictionary,_dialogue: String,_visual:=false) -> Dictionary:
		calls += 1
		if hold_next:
			hold_next=false;held=true;busy=true
			await released
			held=false;busy=false
		return {"ok":true,"text":JSON.stringify({"speech":"","behavior":{"mode":"silence","intention":"Return to the current activity."},"nonverbal":gestures,
			"narration":"The student teleports across the classroom.","biography":{"topic":"unspoken_fact","detail":"I once won an invented championship.","value":"invented championship","kind":"historical"},
			"interpretation":{"event":"chat","tone":"neutral","severity":0.,"meaning":"The player attempts casual conversation.","domain":"conversation","question_kind":"casual","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]}})}

func _initialize() -> void:run.call_deferred()

func check(value: bool,message: String) -> void:
	checks += 1
	if not value:failures.append(message);push_error(message)

func run() -> void:
	create_timer(45.).timeout.connect(func():push_error("Silent dispatch timed out");quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 2:await process_frame
	game.player.set_physics_process(false)
	var faculty: Node=game.faculty
	var classes: Node=game.lecture_classes
	var students: Node=classes.classroom_students
	faculty.set_process(false);classes.set_process(false);game.school.set_process(false)
	game.client_preferences.values.teacher_speech=false
	game.client_preferences.values.teacher_subtitles=false
	game.client_preferences.values.teacher_automatic_conversation=false
	var original: Node=game.host_openai;original.enabled=false
	var client:=Provider.new();game.add_child(client);game.host_openai=client
	check(faculty._sync_character_profile(),"Actual Singleplayer establishes its host namespace")
	preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd").seed(students.population,24)
	game.player.global_position=classes.signs[ROOM].desk
	check(classes._start(ROOM,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":0})=="","Actual class starts with existing persistent students")
	var activity: Dictionary=classes.classes[ROOM]
	var member: Dictionary=activity.classmates.values()[0]
	var actor:=str(member.profile.id)
	member.arrival=classes._now()-1.;member.arrived=true;member.position=member.seat
	member.next=classes._now()+300.;member.action="studying";member.erase("gesture")
	game.player.global_position=member.position+Vector3(.65,0,.4)
	classes._publish();students.render(ROOM,classes.public_classes,.1)
	check(not students.nearby_member(1,ROOM,str(activity.id),actor).is_empty(),"Host confirms the selected student is nearby")
	check(is_instance_valid(students.models.get(str(activity.id)+":"+actor)),"The actual selected student model exists")
	faculty.open_conversation(ROOM,actor,str(activity.id))
	check(faculty.conversation.visible and faculty.conversation_student==actor,"The selected student inspector is open")
	client.online=true;client.hold_next=true
	var identity:=str(game.school.identities[1])
	var before: int=faculty.brain.recall(actor,identity).size()
	var serial:=int(faculty.speech_serial.get("classmate",0))
	var first:={"peer":1,"room":ROOM,"class":activity.id,"student":actor,"content":"Do you feel like talking?"}
	faculty._answer_classmate(first)
	check(client.held and faculty.ai_busy.has(1),"A real classmate request waits for the provider")
	check(faculty.brain.recall(actor,identity).size()==before and int(faculty.speech_serial.get("classmate",0))==serial,"A pending response creates no delivered receipt or spoken playback")
	client.released.emit()
	while faculty.ai_busy.has(1):await process_frame
	check(client.calls==1,"Coordinated silence needs one generation request")
	var trace: Dictionary=faculty.character_interaction.diagnostics.back()
	check(trace.source=="intentional_silence" and str(trace.speech).is_empty(),"The final response is intentional silence with empty speech")
	check(trace.nonverbal==["shrug","wave"],"Supported coordinated gestures survive silent preparation and unsupported actions are removed")
	check(member.get("gesture","")=="shrug" and float(member.get("gesture_until",0))>classes._now(),"The actual classroom action dispatcher executes the first gesture")
	check(not member.has("look_at") and member.gesture_point==Vector3.INF,"Silence does not invent a physical target")
	check(int(faculty.speech_serial.get("classmate",0))==serial,"Silent nonverbal behavior starts no speech or TTS serial")
	check(faculty.conversation_text.text.is_empty(),"Unperformed model narration never appears in the conversation")
	var receipts: Array=faculty.brain.recall(actor,identity)
	check(receipts.size()==before+1 and str(receipts.back().teacher).is_empty() and receipts.back().get("delivery_complete",false),"Completed silence persists exactly once as an empty final delivery")
	check(not JSON.stringify(faculty.brain.character_life_records(member.profile)).contains("invented championship"),"Unspoken biography proposals never become personal history")
	# A valid gesture proposal can still be refused by the host's actual action
	# gate while the student is using equipment. No narration claims it happened.
	member.erase("gesture");member.erase("gesture_until");member.using_bench=true
	client.gestures=["nod"]
	faculty.conversation_text.text="Previous conversation text"
	await faculty._answer_classmate({"peer":1,"room":ROOM,"class":activity.id,"student":actor,"content":"Still busy?"})
	trace=faculty.character_interaction.diagnostics.back()
	check(trace.nonverbal==["nod"] and trace.source=="intentional_silence","The second silent turn still carries its supported proposal")
	check(not member.has("gesture") and not member.has("gesture_until"),"The real action gate rejects the gesture while equipment is in use")
	check(faculty.conversation_text.text.is_empty() and int(faculty.speech_serial.get("classmate",0))==serial,"A rejected action creates neither narration nor spoken output")
	check(faculty.brain.recall(actor,identity).size()==before+2,"Each delivered silent turn has one persistent receipt")
	game.host_openai=original
	print("CHARACTER_SILENT_DISPATCH %s checks=%d failures=%d (authored provider; real Main/action dispatch)"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	game.queue_free();await process_frame
	quit(0 if failures.is_empty() else 1)
