extends SceneTree
## Actual Singleplayer attendance, practice/quiz acceptance and human paper
## submission. Uses the real host grader, never a provider or invented marks.
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const ROOM:="ety155_lecture"
const TEACHER:="mr_stone"
const PRIVATE_PROBE:="HUMAN_PRIVATE_ASSESSMENT_CONTENT"
var checks:=0
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> bool:
	checks+=1
	if not ok:failures.append(message);printerr("HUMAN ACADEMIC MEMORY FAIL: "+message)
	return ok

func outcomes(brain: RefCounted,identity: String) -> Array:
	return brain.relationship(TEACHER,identity).get("episodes",[]).filter(func(row):return row.get("source","")=="host_activity")

func private_fields(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key) in ["answer","answers","answer_key","score","marks","feedback","expected","solution","rubric","verification","private_probe"] or private_fields(value[key]):return true
	elif value is Array:
		for item in value:
			if private_fields(item):return true
	return false

func run() -> void:
	create_timer(65.).timeout.connect(func():printerr("HUMAN ACADEMIC MEMORY TIMEOUT");quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.host_openai.enabled=false
	game.client_preferences.values.teacher_speech=false;game.client_preferences.values.teacher_subtitles=false
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 2:await process_frame
	game.player.set_physics_process(false)
	game.faculty.set_process(false);game.lecture_classes.set_process(false);game.school.set_process(false)
	var school: Node=game.school
	var classes: Node=game.lecture_classes
	var faculty: Node=game.faculty
	var brain: RefCounted=faculty.brain
	var identity:=str(school.local_identity)
	check(game.front.in_game and faculty._sync_character_profile() and brain.host_profile()==identity,"Actual Singleplayer selects a stable host memory namespace")
	game.player.global_position=classes.signs[ROOM].desk
	if not check(classes._start(ROOM,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0,"teacher_override":TEACHER})=="","Actual supervised human lecture starts"):
		game.queue_free();await process_frame;quit(1);return
	check(classes._sign(1,ROOM)=="","Actual human attendance authenticates the participant")
	var activity: Dictionary=classes.classes[ROOM]
	activity.phase="lesson";activity.deadline=classes._now()+600.
	var service: Node=classes.classroom_events.service
	var academic_before:=JSON.stringify([school.archive,school.gradebook,activity.students,school.attendance_archive])
	var unrelated_before:=JSON.stringify([brain.relationship("ms_bird_heart",identity),brain.relationship("campus_student_00",identity),brain.relationship(TEACHER,"unrelated-human")])
	var now: float=classes._now()+1.
	if not check(service.start(ROOM,now,[],"practice"),"Actual host service opens a supervised practice question"):
		game.queue_free();await process_frame;quit(1);return
	var round: RefCounted=service.rooms[ROOM].round
	var event_id:=str(round.event_id)
	round.private_assignment.private_probe=PRIVATE_PROBE
	var answer: Variant=round.private_assignment.questions[round.question_index].answer
	check(service.perform(1,ROOM,activity.id,event_id,"submit","clearly incorrect fixture response",now+1.)=="retry","First incorrect practice answer receives the real retry")
	check(outcomes(brain,identity).is_empty(),"A provisional retry creates no completed academic observation")
	check(service.perform(1,ROOM,activity.id,event_id,"submit",answer,now+2.)=="accepted","Corrected practice work is accepted by the actual grader")
	check(outcomes(brain,identity).size()==1 and outcomes(brain,identity)[0].activity.correct,"The supervising teacher remembers the accepted checked practice outcome")
	var after_practice: Dictionary=brain.relationship(TEACHER,identity)
	check(service.perform(1,ROOM,activity.id,event_id,"submit",answer,now+3.)=="already_submitted" and brain.relationship(TEACHER,identity)==after_practice,"Repeated practice RPC has no second memory or reputation consequence")
	check(service.perform(1,ROOM,activity.id,"stale-event","submit",answer,now+4.)=="not_participating" and outcomes(brain,identity).size()==1,"Stale practice event cannot create an observation")
	service.cancel_for_assessment(ROOM,activity.id,now+5.)
	# Actual accepted quiz answers provide enough sequential evidence to expose
	# improvement; correctness alone still does not diagnose a misconception.
	for index in 6:
		now+=10.
		if not check(service.start(ROOM,now,[],"quiz"),"Actual quiz round %d starts"%index):continue
		round=service.rooms[ROOM].round
		answer=round.private_assignment.questions[round.question_index].answer if index>=3 else "clearly incorrect fixture response"
		check(service.perform(1,ROOM,activity.id,round.event_id,"submit",answer,now+1.)=="accepted","Actual quiz round %d accepts one checked answer"%index)
		service.cancel_for_assessment(ROOM,activity.id,now+2.)
	check(outcomes(brain,identity).size()==7,"Seven completed practice/quiz results are recorded once each")
	check(JSON.stringify([school.archive,school.gradebook,activity.students,school.attendance_archive])==academic_before,"Practice memory changes no grade, enrollment, assessment project or attendance record")
	check(JSON.stringify([brain.relationship("ms_bird_heart",identity),brain.relationship("campus_student_00",identity),brain.relationship(TEACHER,"unrelated-human")])==unrelated_before,"Unrelated teachers, classmates and other humans learn none of these outcomes")
	var patterns: Dictionary=brain.academic_patterns(identity,TEACHER)
	check(patterns.courses.ETY155.attempts==7 and patterns.courses.ETY155.successes==4 and patterns.courses.ETY155.trend=="improving","Teacher-owned human patterns reflect the real failed-then-successful quiz sequence")
	check(patterns.misconceptions.is_empty(),"Wrong answers do not invent a specific diagnosed misconception")
	check(classes._begin_assignment(ROOM,activity),"Actual class enrollment issues the human assessment")
	var paper: Dictionary=school.papers.get(int(activity.students[identity].paper),{})
	if not check(not paper.is_empty() and not paper.replay,"Human receives an official first-attempt paper"):
		game.queue_free();await process_frame;quit(1);return
	paper.project.private_probe=PRIVATE_PROBE
	for index in paper.project.questions.size():
		school.apply(1,{"op":"answer","id":paper.id,"key":str(index),"value":str(paper.project.questions[index].answer)})
	var expected: Dictionary=school.course_bridge.grade(paper.project,paper.answers)
	var paper_before:=JSON.stringify([paper.project,paper.answers])
	var pending_before: Dictionary=school.archive[identity].duplicate(true)
	var grade_count: int=school.gradebook.size()
	var deadline: float=activity.deadline
	school.apply(1,{"op":"submit","id":paper.id})
	check(not paper.mark.is_empty() and paper.mark.score==expected.score and paper.mark.feedback==expected.feedback,"Actual human submit retains the authoritative grader's complete result")
	check(JSON.stringify([paper.project,paper.answers])==paper_before and activity.deadline==deadline,"Memory projection leaves the issued paper, answers and assessment deadline intact")
	check(activity.students[identity].done and school.gradebook.size()==grade_count+1 and school.archive[identity].size()==pending_before.size(),"The normal single enrollment settles into one grade and marks the participant done")
	var settled: Array=school.archive[identity].values().filter(func(row):return str(row.get("assessment_id",""))==str(activity.id))
	check(settled.size()==1 and not settled[0].has("pending_assessment_version") and settled[0].score==expected.score and settled[0].course_id=="ETY155" and int(settled[0].week)==1,"Official grading and course metadata remain unchanged by the observation")
	check(outcomes(brain,identity).size()==8 and outcomes(brain,identity).back().activity.kind=="assessment" and outcomes(brain,identity).back().activity.correct==(float(expected.score)>=60.),"Actual human paper completion reaches only the supervising teacher's checked academic history")
	var after_submit: Dictionary=brain.relationship(TEACHER,identity)
	var academic_after:=JSON.stringify([school.archive,school.gradebook,paper.mark,activity.students])
	school.apply(1,{"op":"submit","id":paper.id})
	check(brain.relationship(TEACHER,identity)==after_submit and JSON.stringify([school.archive,school.gradebook,paper.mark,activity.students])==academic_after,"Repeated actual paper submission changes neither memory nor settled academics")
	var context: Dictionary=brain.character_context(Profiles.teacher(TEACHER),identity,"How has my circuit practice improved?")
	check(context.interlocutor_academic_patterns.courses.ETY155.attempts==8,"Teacher dialogue retrieval receives its own verified history of this human's progress")
	check(not private_fields(outcomes(brain,identity)) and not JSON.stringify(context).contains(PRIVATE_PROBE) and not private_fields(context.interlocutor_academic_patterns),"Memory and retrieval exclude answer keys, private project fields, numeric marks and solutions")
	check(brain.academic_patterns(identity,"ms_bird_heart").courses.is_empty() and brain.academic_patterns(TEACHER).courses.is_empty(),"Another teacher and the observing teacher's own proficiency cannot borrow the player's results")
	check(not faculty.record_human_academic_outcome(activity,"unregistered-human","quiz",true,"forged") and not faculty.record_human_academic_outcome(activity,"campus_student_00","quiz",true,"wrong-path"),"The human callback rejects identities outside its enrollment and NPCs")
	var unknown: Dictionary=activity.duplicate(true);unknown.teacher="not_a_teacher"
	check(not faculty.record_human_academic_outcome(unknown,identity,"quiz",true,"unknown-teacher"),"Unknown teacher IDs cannot invent an observer")
	check(brain.save_memory()==OK,"Human academic observations save with the host's persistent character history")
	var restored:=Brain.new()
	check(restored.set_host_profile(identity)==OK and restored.load_memory(),"A fresh memory owner reloads the same human host namespace")
	check(restored.academic_patterns(identity,TEACHER)==brain.academic_patterns(identity,TEACHER) and outcomes(restored,identity).size()==8,"Human outcome patterns and their directional episodes survive reload")
	check(brain.set_host_profile("human-academic-other-host")==OK and brain.load_memory(),"A distinct host namespace can be selected for the stale-completion guard")
	var other_state:=JSON.stringify(brain.relationships)
	check(not faculty.record_human_academic_outcome(activity,identity,"quiz",true,"stale-host-result") and JSON.stringify(brain.relationships)==other_state,"A completion cannot write into a brain bound to a different active human profile")
	check(brain.set_host_profile(identity)==OK and brain.load_memory(),"The original host history is restored after the isolation check")
	var reloaded: Dictionary=brain.relationship(TEACHER,identity)
	check(faculty.record_human_academic_outcome(activity,identity,"assessment",float(expected.score)>=60.,"assessment_submission") and brain.relationship(TEACHER,identity)==reloaded,"Persistent receipts deduplicate a replayed host completion after reload")
	formal_assessment(game)
	game.queue_free();await process_frame
	print("CHARACTER_HUMAN_ACADEMIC_MEMORY ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," source=actual_singleplayer_submit_and_host_grader")
	quit(0 if failures.is_empty() else 1)

func formal_assessment(game: Node) -> void:
	var school: Node=game.school
	var brain: RefCounted=game.faculty.brain
	var identity:=str(school.local_identity)
	var started: Dictionary=school.start_activity({"mode":"Course","course_id":"ETY155","kind":"lecture","week":2,"difficulty":0,"ai_teaching":true,"lecture_room":ROOM})
	if not check(started.get("ok",false),"The real formal Course flow starts after the completed room assignment"):return
	var teacher:=str(school.activity.get("teacher",""))
	check(not teacher.is_empty(),"Formal Course selects its actual supervising character")
	school.phase="lesson";school.remaining=0.
	school.advance(0.)
	var issued: Array=school.papers.values().filter(func(row):return str(row.get("assessment_id",""))==str(school.assessment_id) and not row.lesson)
	if not check(school.phase=="assignment" and issued.size()==1,"Actual formal lesson completion issues one enrolled human paper"):return
	var paper: Dictionary=issued[0]
	if not paper.held:
		var held: int=school.held(1)
		if held>0:school.apply(1,{"op":"stow","id":held})
		game.player.global_position=paper.position
		school.apply(1,{"op":"pickup","id":paper.id})
	for index in game.chairs.size():
		var chair: Node3D=game.chairs[index]
		if int(chair.occupant)==0 and school.room_bridge.contains(str(school.activity.room.id),chair.position):
			game.player.global_position=chair.global_position
			# Place both host position representations in the fixture classroom;
			# the production chair claim still supplies actual seat ownership.
			game.session.poses[1]={"position":game.player.global_position,"yaw":0.,"pitch":0.,"seated":false}
			game._claim_chair(1,index)
			break
	if not check(school._seated(1),"Formal human submission uses actual host-owned classroom seating"):return
	paper.project.private_probe=PRIVATE_PROBE
	for index in paper.project.questions.size():
		school.apply(1,{"op":"answer","id":paper.id,"key":str(index),"value":str(paper.project.questions[index].answer)})
	var expected: Dictionary=school.course_bridge.grade(paper.project,paper.answers)
	var before: int=brain.relationship(teacher,identity).get("episodes",[]).size()
	var grade_count: int=school.gradebook.size()
	school.apply(1,{"op":"submit","id":paper.id})
	check(not paper.mark.is_empty() and paper.mark.score==expected.score and school.gradebook.size()==grade_count+1 and school.class_students[identity].done,"Actual formal human submit settles its normal grade unchanged")
	var remembered: Array=brain.relationship(teacher,identity).get("episodes",[])
	check(remembered.size()==before+1 and remembered.back().source=="host_activity" and remembered.back().activity.kind=="assessment" and remembered.back().activity.week==2,"Formal assessment completion reaches its actual supervising teacher through the same projection")
	check(not private_fields(remembered.back()) and not JSON.stringify(remembered.back()).contains(PRIVATE_PROBE),"The formal route also excludes all private grading and answer contents")
	var frozen:=JSON.stringify([brain.relationship(teacher,identity),school.archive,school.gradebook])
	school.apply(1,{"op":"submit","id":paper.id})
	check(JSON.stringify([brain.relationship(teacher,identity),school.archive,school.gradebook])==frozen,"Formal submission replay cannot duplicate memory or academic records")
