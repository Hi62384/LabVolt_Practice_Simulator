extends SceneTree
## Two real ENet peers with separate user data; tests host-owned character state.
## The first spoken line uses an explicit structured provider fixture. This is
## transport and gameplay integration evidence, never live language-quality proof.
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const ROOM:="ac_lab"
const ACTOR:="campus_student_14"
const PORT:=26363
const WIRE_LINE:="I heard you. We can talk before class starts."
var game: Node
var deadline:=0

class Provider extends Node:
	var busy:=false
	var enabled:=true
	var tts_enabled:=false
	func ready_for_class() -> bool:return true
	func configured() -> bool:return true
	func moderate(_text: String) -> Dictionary:return {"ok":true,"flagged":false}
	func respond_character(_instructions: String,context: Dictionary,_question: String,_visual:=false) -> Dictionary:
		return {"ok":true,"text":JSON.stringify({"speech":"Morning. That depends on the day.",
			"interpretation":{"event":"greeting","tone":"friendly","severity":0.,"meaning":"A classmate greets this student and asks for a casual opinion.","domain":"conversation","question_kind":"opinion","difficulty":0.,"assessment_request":"social","requested_action":"","memories":[]},
			"delivery":{"emotion":str(context.get("emotional_state",{}).get("emotion","steady")),"knowledge_mode":"personal_conversation"}})}

func _initialize() -> void:call_deferred("run")

func fail(message: String) -> void:
	if is_instance_valid(game):
		print("CLASSMATE DEBUG server=",game.multiplayer.is_server()," queued=",game.faculty.questions.size()," busy=",game.faculty.ai_busy," jobs=",game.faculty.character_jobs," serial=",game.faculty.speech_player.last_serial.get("classmate",0))
		if game.multiplayer.is_server():
			for peer in game.session.roster:
				if peer==1:continue
				var identity:=str(game.school.identities.get(peer,""))
				var activity: Dictionary=game.lecture_classes.classes.get(ROOM,{})
				print("CLASSMATE DEBUG records=",game.faculty.brain.recall(ACTOR,identity).size()," nearby=",not game.lecture_classes.classroom_students.nearby_member(peer,ROOM,str(activity.get("id","")),ACTOR).is_empty())
	push_error("CLASSMATE NETWORK: "+message)
	quit(1)

func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if not game.multiplayer.is_server():game.session.send_pose({"position":game.player.global_position})
		if condition.call():return true
		await create_timer(.05).timeout
	fail("Timed out waiting for "+label)
	return false

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=1 or args[0] not in ["host","client"]:fail("Expected host or client argument");return
	var host:=args[0]=="host"
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	game.client_preferences.values.teacher_speech=false
	game.client_preferences.values.teacher_subtitles=true
	game.client_preferences.values.teacher_automatic_conversation=false
	game.faculty.set_process(false)
	var classes: Node=game.lecture_classes
	classes.set_process(false)
	var students: Node=classes.classroom_students
	deadline=Time.get_ticks_msec()+45000
	game.player.global_position=classes.signs[ROOM].desk
	if host:
		if game.session.host_game("Character host",PORT)!=OK:fail("Host failed");return
		print("CLASSMATE_HOST_READY")
		if not await until(func():return game.session.roster.size()==2 and game.school.identities.size()==2,"client identity"):return
		var peer: int=game.session.roster.keys().filter(func(id):return id!=1)[0]
		var identity:=str(game.school.identities[peer])
		if not await until(func():return classes._inside(peer,ROOM),"client in classroom"):return
		preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd").seed(students.population,24)
		if classes._start(ROOM,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":0})!="":fail("Class did not start");return
		var activity: Dictionary=classes.classes[ROOM]
		if activity.classmates.is_empty():fail("Practical class has no student");return
		var member: Dictionary=activity.classmates.values()[0]
		member.profile=students.population.profile_for(ACTOR)
		member.profile.private_network_marker="Host private biography"
		activity.classmates={ACTOR:member}
		member.arrival=classes._now()-1.
		member.arrived=true
		member.position=member.seat
		member.next=classes._now()+300.
		member.action="studying"
		activity.deadline=classes._now()+300.
		students.social_next_global=classes._now()+300.
		var provider:=Provider.new();game.add_child(provider);game.host_openai=provider
		classes._publish()
		if not await until(func():return not students.nearby_member(peer,ROOM,str(activity.id),ACTOR).is_empty(),"host-confirmed proximity"):return
		member.line="Network proximity confirmed."
		classes._publish()
		if not await until(func():return game.faculty.brain.recall(ACTOR,identity).size()==1,"authenticated student question"):return
		var memories: Array=game.faculty.brain.recall(ACTOR,identity)
		if str(memories[0].get("student",""))!="Good morning. What do you enjoy about this class?":
			fail("A stale or different question reached persistent memory");return
		await create_timer(.5).timeout
		var affect: Dictionary=game.faculty.character_mind.context(member.profile,Time.get_ticks_msec()).emotions.duplicate(true)
		affect.anger=.82
		affect.happiness=.48
		affect.confidence=.72
		game.faculty._notify_classmate(peer,ROOM,activity.id,ACTOR,WIRE_LINE,true,"confident",false,"nod",affect)
		if not await until(func():return game.session.roster.size()==1,"client completed payload checks"):return
		if game.faculty.brain.recall(ACTOR,identity).size()!=1:
			fail("Presenting a network reply duplicated memory");return
		print("CLASSMATE_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Character student",PORT)!=OK:fail("Join failed");return
		if not await until(func():return classes.public_classes.get(ROOM,{}).get("classmates",[]).any(func(member):return member.id==ACTOR),"expanded population snapshot"):return
		var activity: Dictionary=classes.public_classes[ROOM]
		var member: Dictionary=activity.classmates.filter(func(value):return value.id==ACTOR)[0]
		students.render(ROOM,classes.public_classes,.1)
		var public_profile:=Students.profile_for(ACTOR)
		if public_profile.get("id","")!=ACTOR or public_profile.has("biography") or public_profile.has("private_network_marker") or public_profile.has("worldview"):
			fail("Public student profile identity or privacy failed");return
		if member.get("emotions",{}).size()!=16 or member.get("appearance",{}).get("name","").is_empty():
			fail("Expanded appearance or complete affect missing from snapshot");return
		if not is_instance_valid(students.models.get(str(activity.id)+":"+ACTOR)):
			fail("Remote expanded identity did not render");return
		game.player.global_position=member.position+Vector3(.65,0,.45)
		game.session.send_pose({"position":game.player.global_position})
		if not await until(func():return students.visible_member(ROOM,str(activity.id),ACTOR).get("line","")=="Network proximity confirmed.","proximity acknowledgement"):return
		game.faculty.open_conversation(ROOM,ACTOR,str(activity.id))
		game.faculty._send_classmate_question(ROOM,"stale-class",ACTOR,"stale question")
		game.faculty._send_classmate_question(ROOM,str(activity.id),ACTOR,"Good morning. What do you enjoy about this class?")
		if not await until(func():return int(game.faculty.speech_player.last_serial.get("classmate",0))>=1,"actual classmate response"):return
		if game.faculty.reaction_pose.get("classmate",{}).get("affect",{}).size()!=16:
			fail("Generated reply lost the full emotion state");return
		if not await until(func():return int(game.faculty.speech_player.last_serial.get("classmate",0))>=2,"explicit reply gesture payload"):return
		var pose: Dictionary=game.faculty.reaction_pose.get("classmate",{})
		if pose.get("gesture","")!="nod" or pose.get("person_id","")!=ACTOR or not is_equal_approx(float(pose.get("affect",{}).get("anger",0.)),.82):
			print("CLASSMATE PAYLOAD DEBUG gesture=",pose.get("gesture","")," person=",pose.get("person_id","")," affect=",pose.get("affect",{}))
			fail("Student gesture or mixed emotion changed in transit");return
		if game.faculty.conversation_text.text!=WIRE_LINE:
			fail("Remote conversation text changed");return
		# The real client update loop must recover the full expression safely
		# using only the public presentation traits received over the network.
		var before: Dictionary=pose.affect.duplicate(true)
		game.faculty.set_process(true)
		for frame in 12:await process_frame
		game.faculty.set_process(false)
		var recovered: Dictionary=game.faculty.reaction_pose.get("classmate",{}).get("affect",{})
		if recovered.size()!=16 or not Affect.RECOVERY.keys().all(func(key):return recovered.has(key) and is_finite(float(recovered[key])) and float(recovered[key])>=0. and float(recovered[key])<=1.):
			fail("Client Faculty processing corrupted or lost mixed affect");return
		if float(recovered.anger)>=float(before.anger):
			fail("Client emotion did not recover over actual processing frames");return
		var after_profile:=Students.profile_for(ACTOR)
		if after_profile.has("biography") or after_profile.has("worldview") or after_profile.has("private_network_marker") or after_profile.traits.size()!=6 or after_profile.traits.has("optimism") or after_profile.traits.has("emotional_stability"):
			fail("Client recovery required or exposed private traits");return
		print("CLASSMATE_CLIENT PASS")
		game.session.leave()
		await create_timer(.3).timeout
	game.session.leave()
	game.queue_free()
	await process_frame
	quit(0)
