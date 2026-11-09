extends SceneTree
const School = preload("res://scripts/school_session.gd")
const Clock = preload("res://scripts/campus/academics/class_start/class_start_clock.gd")
const Attendance = preload("res://scripts/campus/academics/attendance_ledger.gd")

class MockFront extends RefCounted:
	var in_game := false
class MockSession extends Node:
	var online := false
	var roster := {}
	var labs := []
class MockGame extends Node:
	var front: MockFront = MockFront.new()
	var session: MockSession = MockSession.new()
	var dc_lab: Node
	var kit_world: Node

var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL CLASS_APPLIED: "+message)

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game := MockGame.new()
	root.add_child(game)
	game.add_child(game.session)
	var school := School.new()
	game.add_child(school)
	school.game=game
	check(game.get_multiplayer().is_server(),"offline fixture is host authority")
	school.start("Freeplay",1)
	check(school.phase=="freeplay" and school.class_start.deadline_usec<0,"Freeplay has no class countdown")
	var clock := Clock.new()
	check(clock.arm("A",1000000),"host arms first class")
	check(is_equal_approx(clock.remaining(120999000),0.001),"119999 ms has one millisecond remaining")
	check(not clock.due(120999000) and clock.due(121000000),"deadline boundary 119999/120000 ms")
	check(not clock.arrive("early",120999000).late,"arrival before cutoff on time")
	check(clock.arrive("late",121000000).late,"arrival at cutoff late")
	check(not clock.arm("A",121000000) and is_equal_approx(clock.remaining(120999000),0.001),"new arrival or duplicate arm does not reset deadline")
	check(not clock.arrive("early",121000001).late,"reconnect preserves first arrival")
	check(clock.begin_if_due(121000000) and not clock.begin_if_due(121000001),"start occurs once")
	check(clock.restore("A",12.0,200000000,{"early":false,"late":true}),"recovery accepts saved remaining")
	check(clock.remaining(200000000)==12.0 and not clock.arrive("early",212000000).late,"recovery preserves remaining time and identity")

	school.mode="Class"
	school.phase="travel"
	school.assessment_id="synthetic-session"
	school.class_start.arm(school.assessment_id,Time.get_ticks_usec())
	var early_profile := "111111111111111111111111111111111111111111111111"
	school.class_students[early_profile]={"done":false}
	game.session.roster[2]={"name":"Early synthetic peer"}
	school._identify(2,early_profile)
	check(school.class_start.arrivals.has(early_profile) and not school.class_start.arrivals[early_profile],"host records early authenticated peer")
	game.session.roster.erase(2)
	school.roster_changed()
	check(not school.begin_lesson() and school.phase=="travel","instructor click cannot start teaching")
	school.class_start.deadline_usec=Time.get_ticks_usec()-1
	game.session.roster[2]={"name":"Returning synthetic peer"}
	school._identify(2,early_profile)
	check(not school.class_start.arrivals[early_profile],"reconnected authenticated peer remains on time")
	var late_profile := "222222222222222222222222222222222222222222222222"
	game.session.roster[3]={"name":"Late synthetic peer"}
	school._identify(3,late_profile)
	check(school.class_start.arrivals.get(late_profile,false),"new peer after cutoff is late before host tick")
	school._process(0.0)
	check(school.phase=="lesson" and school.remaining==school.teaching_seconds,"host starts class with zero participants while menu is open")
	var first_remaining: float=school.remaining
	school._process(0.0)
	check(school.remaining==first_remaining,"duplicate host tick does not restart lesson")
	school.mode="Freeplay";school.phase="freeplay";school.class_start.cancel()
	check(school.can_choose_next_activity(),"host can choose in Freeplay")
	school.mode="Class";school.phase="travel"
	check(not school.can_choose_next_activity(),"countdown blocks next activity")
	school.phase="lesson"
	check(not school.can_choose_next_activity(),"lesson blocks next activity")
	school.phase="assignment"
	check(not school.can_choose_next_activity(),"assessment blocks next activity")
	school.phase="complete"
	check(school.can_choose_next_activity(),"completed class enables next activity")
	school.phase="lesson"
	var old_epoch: int=school.activity_epoch
	var profile := "0123456789abcdef0123456789abcdef0123456789abcdef"
	school.identities[1]=profile
	game.session.roster[1]={"name":"Synthetic host"}
	school.apply(1,{"op":"activity","expected_epoch":old_epoch,"config":{"mode":"Freeplay"}})
	check(school.phase=="lesson" and school.activity_epoch==old_epoch,"stale host activity action rejected during class")
	school.apply(1,{"op":"new","course_id":"ELM253","week":1,"difficulty":4})
	check(school.papers.is_empty(),"class rejects instructor practice request")
	school.apply(1,{"op":"begin_lesson"})
	check(school.phase=="lesson","legacy begin request has no effect")
	var participant := "abcdef0123456789abcdef0123456789abcdef0123456789"
	school.identities.clear()
	school.identities[2]=participant
	game.session.roster[2]={"name":"Synthetic student"}
	school.class_students={participant:{"done":false}}
	school.project={"title":"Synthetic assigned work","course_id":"ELM253","kind":"lecture","week":1,"questions":[]}
	school.round_id=1
	school.remaining=0.0
	school.advance(0.0)
	check(school.phase=="assignment" and school.papers.size()==1,"lesson transition delivers one assigned sheet")
	var assigned_id: int=int(school.papers.keys()[0])
	school.advance(0.0)
	check(school.papers.size()==1 and school.papers.has(assigned_id),"repeat advance does not duplicate assigned work")
	game.session.roster.erase(2)
	school.roster_changed()
	check(school.papers.is_empty() and school.class_students[participant].has("saved"),"disconnect archives assigned sheet")
	game.session.roster[2]={"name":"Synthetic student"}
	school._identify(2,participant)
	check(school.papers.size()==1 and school.papers.has(assigned_id),"reconnect restores same assigned sheet ID")

	var events := {}
	var first: Dictionary=Attendance.record_authoritative(events,true,"A",profile,"ELM253","lecture",1,"2026-11-06T12:00:00",["ELM253"])
	check(first.ok and first.created,"host attendance event created")
	first.event["late"]=true
	events[first.id]=first.event.duplicate(true)
	var again: Dictionary=Attendance.record_authoritative(events,true,"A",profile,"ELM253","lecture",1,"2026-11-06T12:01:00",["ELM253"])
	check(again.ok and not again.created and again.event.late,"repeated result retains first late fact")
	check(events.size()==1,"attendance remains idempotent")
	print("CLASS_APPLIED checks=%d failures=%d"%[checks,failures])
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
