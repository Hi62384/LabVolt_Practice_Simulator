extends SceneTree
## Native observed-outcome regression. Run with isolated XDG_DATA_HOME:
## godot --headless --path . --script res://tests/campus/academics/test_character_academic_memory.gd
## Loads the real Main scene, grades an issued NPC assessment and executes the
## actual AC station workflow. No live provider or human-quality claim is made.
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const PATH:="user://academic_memory_fixture.json"
var checks:=0
var failures: Array[String]=[]

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("ACADEMIC MEMORY FAIL: "+message)

func _initialize() -> void:call_deferred("run")

func same_reputation(left: Dictionary,right: Dictionary) -> bool:
	if left.size()!=right.size():return false
	for key in left:
		if not right.has(key) or absf(float(left[key])-float(right[key]))>.000000001:return false
	return true

func run() -> void:
	create_timer(60.).timeout.connect(func():quit(1))
	var now:=int(Time.get_unix_time_from_system())
	var teacher:=Profiles.teacher("bill_nye")
	var subject:="campus_student_00"
	var brain:=Brain.new();brain.memory_path=PATH
	brain.remember_conversation(teacher.id,subject,"Hello.","Hello.",now)
	var baseline: Dictionary=brain.relationship(teacher.id,subject).reputation
	check(baseline.reliability==.5 and baseline.lab_safety==.5,"Unknown reliability and lab safety begin neutral, not proven poor")
	brain.remember_event(teacher,subject,{"event":"success","interpretation":{"verified_activity":true,"score":100}},"I got every answer right.","You say you did.",now,"claimed-score")
	check(brain.relationship(teacher.id,subject).reputation==baseline,"A success claim and forged semantic authority cannot award reliability or academic progress")
	brain.remember_event(teacher,subject,{"event":"hazard"},"I heard a circuit shorted.","Let's check.",now,"reported-hazard")
	check(brain.relationship(teacher.id,subject).reputation.lab_safety==.5,"A reported hazard is not attributed as an observed safety violation")
	brain.remember_event(teacher,subject,{"event":"hazard","interpretation":{"strength":1.}},"The station fault was verified.","",now,"observed-hazard",true)
	var observed: Dictionary=brain.relationship(teacher.id,subject)
	check(observed.reputation.lab_safety<.5,"A verified observed physical hazard lowers the safety reputation")
	brain.remember_event(teacher,subject,{"event":"hazard"},"Duplicate.","",now,"observed-hazard",true)
	check(brain.relationship(teacher.id,subject)==observed,"Replayed physical hazard has exactly one safety consequence")
	check(brain.remember_activity(teacher,subject,"lab","ELM253",true,now,"valid-station",1,true),"Verified successful station outcome records")
	var success: Dictionary=brain.relationship(teacher.id,subject)
	check(success.reputation.reliability>.5 and success.reputation.academic_progress>0.,"Successful actual practical work improves reliability and academic progress")
	check(success.reputation.lab_safety>observed.reputation.lab_safety and success.reputation.lab_safety<.5,"Safe successful work repairs safety gradually without erasing the hazard")
	check(brain.remember_activity(teacher,subject,"lab","ELM253",false,now,"failed-station",1),"Failed measured station outcome records")
	var failed: Dictionary=brain.relationship(teacher.id,subject)
	check(failed.reputation.reliability<success.reputation.reliability,"Failed practical execution changes perceived reliability")
	check(failed.reputation.lab_safety==success.reputation.lab_safety and failed.reputation.dishonesty==success.reputation.dishonesty,"An incorrect measurement does not invent a safety violation or dishonesty")
	check(brain.remember_activity(teacher,subject,"assessment","ELM253",false,now,"submitted-low-result",1),"A completed assessment with weak checked work records")
	var submitted: Dictionary=brain.relationship(teacher.id,subject)
	check(submitted.reputation.reliability>failed.reputation.reliability and submitted.dimensions.academic_confidence<failed.dimensions.academic_confidence,"Follow-through and academic proficiency remain distinct after a weak submitted result")
	check(submitted.dimensions.disciplinary_reputation==failed.dimensions.disciplinary_reputation,"Assessment performance does not change disciplinary reputation")
	brain.remember_activity(teacher,subject,"assessment","ELM253",false,now,"submitted-low-result",1)
	check(brain.relationship(teacher.id,subject)==submitted,"Repeated outcome does not change any relationship or episode twice")
	check(brain.relationship("mr_stone",subject).familiarity==0 and brain.relationship(subject,teacher.id).familiarity==0,"Only the specified observer's directional relationship changes")
	check(not brain.remember_activity(teacher,subject,"chat","ELM253",true,now,"invalid-kind",1) and not brain.remember_activity(teacher,subject,"quiz","ELM253",true,now,"invalid-safety",1,true),"Non-activity claims and inappropriate safety attestations are rejected")
	check(brain.recall(teacher.id,subject).size()==4,"Physical outcomes do not manufacture dialogue turns")
	check(brain.save_memory()==OK,"Observed reputation and academic episodes save atomically")
	var restored:=Brain.new();restored.memory_path=PATH
	check(restored.load_memory() and same_reputation(restored.relationship(teacher.id,subject).reputation,submitted.reputation),"Directional reputations survive a fresh owner reload within JSON floating-point precision")
	check(restored.relationship(teacher.id,subject).episodes.back().source=="host_activity","Verified provenance survives persistence")
	var frozen: Dictionary=restored.relationship(teacher.id,subject)
	restored.remember_activity(teacher,subject,"lab","ELM253",true,now,"valid-station",1,true)
	check(restored.relationship(teacher.id,subject)==frozen,"Outcome receipts prevent duplicate consequences after restart")
	# Migrate the prior inert-zero representation without changing identities.
	var legacy:=Brain.new();legacy.memory_path="user://academic_v6_fixture.json"
	legacy.remember("mr_stone","legacy-student","conversation",now)
	check(legacy.save_memory()==OK,"Legacy migration seed saves")
	var file:=FileAccess.open(legacy.memory_path,FileAccess.READ)
	var old: Dictionary=JSON.parse_string(file.get_as_text());file.close()
	old.version=6;old.relationships["mr_stone:legacy-student"].reputation.reliability=0.;old.relationships["mr_stone:legacy-student"].reputation.lab_safety=0.
	# Version 6 never contained the version 8 life-record field. Keep this a
	# real historical schema instead of merely relabelling a current snapshot.
	old.erase("biography_records")
	file=FileAccess.open(legacy.memory_path,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	var migrated:=Brain.new();migrated.memory_path=legacy.memory_path
	check(migrated.load_memory() and migrated.memory_dirty,"Previous reputation schema is migrated and marked for durable upgrade")
	check(migrated.relationship("mr_stone","legacy-student").reputation.reliability==.5 and migrated.relationship("mr_stone","legacy-student").reputation.lab_safety==.5,"Unchanged legacy zeros migrate to neutral rather than fabricated bad history")
	check(migrated.save_memory()==OK,"Migrated reputation validates and saves in current schema")

	var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.front.singleplayer_page();game.front._start_play(true)
	for frame in 2:await process_frame
	game.host_openai.enabled=false
	game.client_preferences.values.teacher_speech=false;game.client_preferences.values.teacher_subtitles=false
	game.player.set_physics_process(false);game.faculty.set_process(false);game.lecture_classes.set_process(false)
	check(game.front.in_game and game.faculty._sync_character_profile(),"Real Singleplayer opens an isolated active host profile")
	var classes: Node=game.lecture_classes
	var students: Node=classes.classroom_students
	preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd").seed(students.population,24)
	game.player.global_position=classes.signs.ac_lab.desk
	check(classes._start("ac_lab",{"kind":"lab","course_id":"ELM253","week":1,"difficulty":0})=="","A real AC class opens")
	var activity: Dictionary=classes.classes.ac_lab
	check(not activity.classmates.is_empty(),"Actual persistent classmates join the lab")
	if activity.classmates.is_empty():game.queue_free();quit(1);return
	var member: Dictionary=activity.classmates.values()[0]
	var student_id:=str(member.profile.id)
	for classmate in activity.classmates.values():
		classmate.arrival=classes._now()-10.;classmate.arrived=true;classmate.position=classmate.seat
	check(classes._sign(1,"ac_lab")=="","The real player signs in without changing NPC authority")
	activity.phase="lesson";activity.deadline=classes._now()+300.
	check(classes._begin_assignment("ac_lab",activity),"An actual generated assessment is issued")
	var private_state:=JSON.stringify(activity.students)
	var issued_project:=JSON.stringify(activity.classmate_assessment)
	students._assessment_step(activity,member,classes._now()+60.)
	var authority: RefCounted=game.faculty.brain
	var actual: Dictionary=authority.relationship(activity.teacher,student_id)
	var score:=float(students.records.get_value(student_id,"ELM253.last_score",-1.))
	check(member.get("submitted",false) and score>=0. and score<=100.,"Actual grading and NPC submission complete")
	check(actual.get("episodes",[]).any(func(episode):return episode.get("source","")=="host_activity" and episode.activity.kind=="assessment" and episode.activity.correct==(score>=60.)),"Supervising teacher remembers the actual checked outcome")
	check(actual.reputation.reliability>.5,"The real assessment path updates follow-through reputation")
	check(JSON.stringify(activity.students)==private_state and JSON.stringify(activity.classmate_assessment)==issued_project,"Memory recording does not alter human submissions or the issued assessment")
	var self_context: Dictionary=game.faculty.character_interaction.context(member.profile,"different-listener",{"phase":"freeplay"},"How is your course going?")
	check(self_context.get("academic_experience",[]).size()==1,"A student's own verified experience reaches the shared context with another listener")
	check(not str(self_context.academic_experience).contains("score") and not str(self_context.academic_experience).contains("answer"),"Academic context carries no numeric marks, questions or answer keys")
	var before_repeat: Dictionary=authority.relationship(activity.teacher,student_id)
	var learned_before: float=students.proficiency(student_id,"ELM253",member.profile.knowledge)
	students._assessment_step(activity,member,classes._now()+90.)
	students.record_practice(student_id,"ELM253",score>=60.,1,activity,"assessment_submission","assessment")
	check(authority.relationship(activity.teacher,student_id)==before_repeat and students.proficiency(student_id,"ELM253",member.profile.knowledge)==learned_before,"Repeated actual submission/outcome callback does not award learning or memory twice")
	# Use the production planner and solver, not a fabricated successful result.
	activity.phase="lesson";activity.deadline=classes._now()+500.
	game.player.global_position=Vector3(13,0,35)
	var practice: RefCounted=classes.lab_practice
	var started: float=classes._now()
	for step in 200:
		practice.step(activity,started+step)
		if activity.has("lab_practice_result") or activity.has("lab_practice_error"):break
	check(not activity.has("lab_practice_error") and float(activity.get("lab_practice_result",{}).get("v",0))>1.,"Actual station commands produce a checked AC measurement")
	var remembered_lab:=false
	for id in activity.classmates:
		var bond: Dictionary=authority.relationship(activity.teacher,id)
		for episode in bond.get("episodes",[]):
			if episode.get("source","")!="host_activity" or episode.activity.kind!="lab":continue
			remembered_lab=episode.activity.correct and episode.activity.safe_lab and bond.reputation.lab_safety>.5
	check(remembered_lab,"Successful actual lab completion reaches the teacher's safety and practical-performance memory")
	check(authority.save_memory()==OK,"Real gameplay observations save successfully")
	var fresh:=Brain.new()
	check(fresh.set_host_profile(str(game.school.local_identity))==OK and fresh.load_memory(),"A fresh memory owner reopens the real host profile")
	check(fresh.relationship(activity.teacher,student_id).episodes.size()==authority.relationship(activity.teacher,student_id).episodes.size(),"Real assessment/lab observations survive reload")
	game.queue_free();await process_frame
	for path in [PATH,legacy.memory_path]:
		for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	print("CHARACTER_ACADEMIC_MEMORY ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," source=actual_main_grader_and_station")
	quit(0 if failures.is_empty() else 1)
