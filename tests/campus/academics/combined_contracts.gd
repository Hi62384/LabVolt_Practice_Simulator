extends SceneTree
## Run after integrator combines academics, world and curriculum source deliveries.
const School = preload("res://scripts/school_session.gd")
const Fixtures = preload("res://tests/campus/academics/test_academics.gd")
var failures := 0
var checks := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("COMBINED FAIL: "+label)
	else:print("COMBINED PASS: "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not ResourceLoader.exists("res://scripts/campus/courses/course_provider.gd") or not ResourceLoader.exists("res://scripts/campus/world/room_registry.gd"):
		push_error("Combined contracts require the world and curriculum deliveries.");quit(2);return
	var game := Fixtures.GameStub.new();root.add_child(game);game.add_child(game.session);game.add_child(game.ui);game.add_child(game.sfx)
	game.session.roster={1:{"name":"Student"}};game.chairs=[{"occupant":1,"position":Vector3.ZERO}]
	var school := School.new();game.add_child(school);school.game=game;school.local_identity="a".repeat(48);school.identities={1:school.local_identity}
	school.configure_campus()
	check(school.course_bridge.weeks("ETY155","lecture").size()==12,"Provider has 12 ETY155 lecture weeks")
	check(school.course_bridge.weeks("ETY155","lab").size()==12,"Provider has 12 ETY155 lab weeks")
	for course in ["ELM253","ETY155"]:
		for meta in school.course_bridge.weeks(course,"lecture"):
			var week := int(meta.week)
			var result := school.start_activity({"mode":"Course","course_id":course,"kind":"lecture","week":week,"difficulty":2,"teaching_seconds":420})
			check(result.ok,"%s week %d starts through real provider"%[course,week])
			if not result.ok:continue
			check(str(school.activity.room.number)==("M202" if course=="ETY155" else "M201"),"Course room uses world registry")
			game.session.poses[1].position=school.room_bridge.point(school.activity.room.center)
			game.chairs[0].position=game.session.poses[1].position
			check(school.begin_lesson(),"Actual room and authoritative seat begin teaching")
			school.advance(420)
			var paper: Dictionary=school.papers.values().filter(func(p):return not p.lesson)[0]
			for i in paper.project.questions.size():paper.answers[str(i)]=str(paper.project.questions[i].answer)
			school._mark(paper,false)
			check(is_equal_approx(float(paper.mark.score),100),"Actual generated answer key earns 100% written credit")
			school.advance(0)
	check(int(school.course_summary("ETY155").lecture_count)==12,"Twelve ETY155 official lecture attempts retained")
	check(int(school.course_summary("ELM253").lecture_count)==school.course_bridge.weeks("ELM253","lecture").size(),"ELM253 records retained independently")
	var current_source_assignment := school.course_bridge.generate("ETY155",12,"lab",2,123)
	check(not preload("res://scripts/campus/academics/equipment_evidence.gd").new().supports(current_source_assignment).ok,"Unsupported ideal current-source practical explicitly gated")
	school.free();game.free()
	print("COMBINED_CONTRACTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
