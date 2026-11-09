extends SceneTree
const School = preload("res://scripts/school_session.gd")
const Policy = preload("res://scripts/campus/academics/grade_policy.gd")
const Evidence = preload("res://scripts/campus/academics/equipment_evidence.gd")
const Allocator = preload("res://scripts/campus/academics/bench_allocator.gd")
var failures := 0
var checks := 0
class SessionStub extends Node:
	signal roster_changed
	signal restarted
	signal leaving
	var roster := {1:{"name":"A"},2:{"name":"B"}}
	var poses := {1:{"position":Vector3.ZERO},2:{"position":Vector3.ZERO}}
	var labs: Array=[]
	var online := false
	@rpc("authority","call_remote","reliable")
	func _notice(_message: String) -> void:pass
class UiStub extends Node:
	func log_message(_message: String) -> void:pass
class SoundStub extends Node:
	func play(_sound: String) -> void:pass
class FrontStub extends RefCounted:
	var in_game := false
class GameStub extends Node:
	var session=SessionStub.new()
	var ui=UiStub.new()
	var sfx=SoundStub.new()
	var front=FrontStub.new()
	var chairs: Array=[]
	var dc_lab: Node
	var kit_world: Node
	var electronics: Node
class DcStub extends Node:
	var benches: Array=[]
class RoomStub extends RefCounted:
	func activity_room(_course: String,_kind: String) -> Dictionary:
		return {"id":"fixture","number":"T1","building":"Test","floor":0,"name":"Test room","teacher_position":Vector3.ZERO,"entrance":Vector3(0,0,-10),"desks":[Vector3(0,.895,1)]}
	func room_contains(_id: String,position: Vector3) -> bool:return position.length()<5
class ProviderStub extends RefCounted:
	func weeks(_course: String,_kind: String) -> Array:
		var result: Array=[]
		for i in 12:result.append({"week":i+1,"title":"Fixture"})
		return result
	func generate(course: String,week: int,kind: String,difficulty: int,seed_value: int) -> Dictionary:
		return {"course_id":course,"week":week,"kind":kind,"difficulty":difficulty,"title":"Verified fixture","topic":0,"seed":seed_value,"theory":"Ohm's law","data":"10 V, 1 kΩ","procedure":"Wire with power off","source":"test","questions":[{"prompt":"I","answer":.01,"options":[],"unit":"A","explanation":"10/1000"},{"prompt":"P","answer":.1,"options":[],"unit":"W","explanation":"VI"}]}
	func lesson(_course: String,_week: int,_kind: String,duration: int) -> Dictionary:
		return {"stages":[{"title":"First","text":"V=IR","duration_seconds":duration/2},{"title":"Second","text":"P=VI","duration_seconds":duration-duration/2}]}
	func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
		return preload("res://scripts/course_generator.gd").grade(assignment,answers)

class ClockSchool extends "res://scripts/school_session.gd":
	var now := 1000.0
	var recovery_fixture := {}
	var reward_calls := 0
	var reward_calls_by_id := {}
	var rewarded := {}
	func _academic_now() -> float:return now
	func _read_academic_recovery() -> Dictionary:return recovery_fixture.duplicate(true)
	func _save(_path: String,_data: Dictionary) -> void:pass
	func checkpoint() -> void:pass
	func _notice(_peer: int,_message: String) -> void:pass
	func _apply_reward(record: Dictionary) -> void:
		reward_calls+=1
		var id := str(record.id)
		reward_calls_by_id[id]=int(reward_calls_by_id.get(id,0))+1
		rewarded[id]=true

const A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error("FAIL: "+label)
	else:print("PASS: "+label)
func _initialize() -> void:call_deferred("run")
func make_fixture() -> Dictionary:
	var game := GameStub.new();root.add_child(game)
	game.add_child(game.session);game.add_child(game.ui);game.add_child(game.sfx)
	var school := ClockSchool.new();game.add_child(school);school.game=game
	school.local_identity=A;school.identities={1:A,2:B}
	school.configure_campus(RoomStub.new(),ProviderStub.new())
	return {"game":game,"school":school}
func issue(school: Node) -> Dictionary:
	var config := {"mode":"Course","course_id":"ETY155","kind":"lab","week":1,"teaching_seconds":300,"assessment_seconds":10}
	check(school.start_activity(config).ok,"start class")
	check(school.begin_lesson(),"begin teaching")
	school.advance(300)
	var paper: Dictionary=school.papers.values().filter(func(p):return not p.lesson and p.owner==1)[0]
	paper.answers={"0":".01"}
	return paper
func journal(school: Node) -> Dictionary:
	# Serialized transport is replaced; recover_activity itself is the real method.
	return {"ok":true,"data":{"schema":1,"host_identity":A,"activity":school.activity.duplicate(true),"project":school.project.duplicate(true),"presentation":school.presentation.duplicate(true),"papers":school.papers.duplicate(true),"students":school.class_students.duplicate(true),"identities":school.identities.duplicate(true),"allocation":school.allocation.duplicate(true),"phase":school.phase,"remaining":school.remaining,"round_id":school.round_id,"next_id":school.next_id,"assessment_id":school.assessment_id,"deadline":school.assessment_deadline,"saved_at":school.now}}
func abandonment_boundaries() -> void:
	for request_path in [false,true]:
		for offset in [-0.001,0.0,0.001]:
			var fixture := make_fixture();var s=fixture.school
			var paper := issue(s);var id: String=s.assessment_id
			s.now=s.assessment_deadline+offset
			if request_path:s.apply(1,{"op":"abandon","confirmed":true})
			else:s.abandon(1)
			var expected := 0.0 if offset<0 else 50.0
			check(paper.mark.score==expected,"direct/request abandonment boundary score %s/%s"%[request_path,offset])
			check(("Intentional abandonment" in paper.mark.reason) if offset<0 else ("Deadline reached" in paper.mark.reason),"boundary uses correct settlement reason")
			check(s.class_students[A].done,"boundary completes participant")
			check(s.archive[A].size()==1 and s.reward_calls==1 and s.rewarded.size()==1,"one record and exactly one reward-sink invocation")
			# Try both entry points and a cleared stale copy after the original settlement.
			s.abandon(1);s.apply(1,{"op":"abandon","confirmed":true});s._mark(paper,true)
			var stale: Dictionary=paper.duplicate(true);stale.mark={};s._mark(stale,true)
			check(s.archive[A].size()==1 and s.reward_calls==1 and s.reward_calls_by_id[Policy.attempt_id(id,A)]==1,"repeated/stale settlement does not call reward sink again")
			fixture.game.free()
func host_exit_boundaries() -> void:
	for offset in [-0.001,0.0,0.001]:
		var fixture := make_fixture();var s=fixture.school;var paper := issue(s)
		s.now=s.assessment_deadline+offset;s.prepare_host_exit(true)
		check(paper.mark.score==(0.0 if offset<0 else 50.0),"intentional host exit obeys same deadline boundary")
		fixture.game.free()
func submitted_host_exit_at_deadline() -> void:
	var fixture := make_fixture();var school=fixture.school;var paper := issue(school)
	school._mark(paper,false)
	var other: Dictionary=school.papers.values().filter(func(p):return not p.lesson and p.owner==2)[0]
	other.answers={"0":".01"}
	school.now=school.assessment_deadline;school.prepare_host_exit(true)
	check(school.phase=="complete" and other.mark.score==50,"already-submitted host departure still settles expired classmates")
	check(school.archive[A].size()==1 and school.archive[B].size()==1 and school.reward_calls==1,"submitted host expiry keeps its reward invocation count unchanged")
	fixture.game.free()
func recovery_paths() -> void:
	var source := make_fixture();var s=source.school;issue(s)
	s.suspend_for_host_loss()
	var saved := journal(s)
	# Actual recover_activity calls on new trusted-host instances; no suspended reset.
	for now in [900.0,1006.0,1010.0,1011.0]:
		var fixture := make_fixture();var fresh=fixture.school
		fixture.game.session.roster={1:{"name":"A"}}
		fresh.identities={};fresh.now=now;fresh.recovery_fixture=saved.duplicate(true)
		var recovered: Dictionary=fresh.recover_activity()
		check(recovered.ok,"actual recover_activity accepts injected journal")
		check(fresh.assessment_deadline==1010,"recovery preserves original deadline")
		var expected := minf(10,maxf(0,1010-now))
		check(fresh.remaining==expected,"recovery never expands saved budget, including rollback")
		check(not fresh.suspended,"trusted recovery restores authority state")
		if now>=1010:
			check(fresh.phase=="complete" and fresh.class_students[A].done and fresh.class_students[B].done,"expired host downtime voids every unresolved participant")
			check(fresh.archive.is_empty() and fresh.gradebook.is_empty() and fresh.reward_calls==0,"expired recovery has no official zero or reward invocation")
			check(fresh.class_students[A].saved.lesson and fresh.class_students[A].saved.class_round==0 and fresh.class_students[A].saved.mark.score==50,"expired recovery keeps partial work as practice feedback")
			fresh.abandon(1);fresh.advance(0)
			check(fresh.archive.is_empty() and fresh.reward_calls==0,"voided recovery cannot later become abandonment penalty")
		else:
			check(fresh.phase=="assignment" and not fresh.class_students[A].done,"unexpired recovery resumes assignment")
			check(fresh.papers.values().any(func(p):return not p.lesson and p.identity==A and p.answers.get("0","")==".01"),"real recovery rebinds saved answers")
			fresh.now=1010;fresh.abandon(1)
			check(fresh.class_students[A].saved.mark.score==50 and fresh.reward_calls==1,"resumed assessment expires with partial credit")
		fixture.game.free()
	var fixture := make_fixture();var fresh=fixture.school
	fresh.recovery_fixture={"ok":false,"error":"read failure fixture"}
	check(not fresh.recover_activity().ok and fresh.activity.is_empty(),"failed journal read leaves activity idle")
	fixture.game.free();source.game.free()
func grade_policy_cases() -> void:
	var records := {"malformed_null":null,"malformed_array":[],"malformed_string":"bad","malformed_number":7}
	for course in ["ELM253","ETY155","MTH147","MTH255"]:
		records[course+"lecture"]={"profile":A,"course_id":course,"kind":"lecture","score":80+["ELM253","ETY155","MTH147","MTH255"].find(course)}
		records[course+"intzero"]={"profile":A,"course_id":course,"kind":"lab","score":0}
		records[course+"floatzero"]={"profile":A,"course_id":course,"kind":"lab","score":0.0}
		records[course+"missing"]={"profile":A,"course_id":course,"kind":"lab"}
		for i in range(8):
			var bad_scores: Array=[null,true,"0",[],{},NAN,INF,-INF]
			records[course+"invalid"+str(i)]={"profile":A,"course_id":course,"kind":"lab","score":bad_scores[i]}
		records[course+"practice"]={"profile":A,"course_id":course,"kind":"lab","score":100,"lesson":true}
		records[course+"otherprofile"]={"profile":B,"course_id":course,"kind":"lab","score":100}
	for course in ["ELM253","ETY155","MTH147","MTH255"]:
		var summary := Policy.summary(records,A,course)
		check(summary.lecture==80+["ELM253","ETY155","MTH147","MTH255"].find(course) and summary.lab==0 and summary.overall==(80.0+["ELM253","ETY155","MTH147","MTH255"].find(course))/2.0,"course categories include genuine zeros "+course)
		check(summary.attempts==3 and summary.lecture_count==1 and summary.lab_count==2,"course ignores malformed/missing/practice/other-profile records "+course)
	check(Policy.summary({},A,"ELM253").overall==null,"empty gradebook has no average")
	check(Policy.summary({"missing":{"profile":A,"score":null}},A,"ELM253").attempts==0,"null-only gradebook has no attempts")
func practice_and_replay() -> void:
	var fixture := make_fixture();var s=fixture.school
	var paper := issue(s)
	var practice_id: int=s._give(1,ProviderStub.new().generate("ETY155",1,"lab",0,1),true,false)
	s._mark(s.papers[practice_id],false)
	check(s.gradebook.is_empty() and s.reward_calls==0,"practice marking excludes official record and reward sink")
	s._mark(paper,false)
	check(s.reward_calls==1 and s.rewarded.size()==1,"official mark invokes reward sink once")
	var record: Dictionary=s.archive[A].values()[0]
	s._receive_grade(record)
	check(s.reward_calls==2 and s.rewarded.size()==1,"delivery replay invokes adapter again; unique IDs alone do not prove payout exactly once")
	fixture.game.free()
func expired_answer_request() -> void:
	var fixture := make_fixture();var school=fixture.school;var paper := issue(school)
	school.now=school.assessment_deadline
	school.apply(1,{"op":"answer","id":paper.id,"key":"1","value":".1"})
	check(school.phase=="complete" and paper.mark.score==50 and paper.answers.size()==1,"deadline request rejects late answer before next frame")
	check(school.reward_calls==1,"deadline answer request settles once")
	fixture.game.free()
func run() -> void:
	expired_answer_request();abandonment_boundaries();host_exit_boundaries();submitted_host_exit_at_deadline();recovery_paths();grade_policy_cases();practice_and_replay()
	print("ACADEMIC_STATE_V2_RESULT checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
