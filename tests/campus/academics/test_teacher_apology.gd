extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var brain=Brain.new()
	var personality: Dictionary={"difficulty":.9,"focus":.9,"talkativeness":.5}
	brain.consider("mr_stone","student_a","class_message",.6,personality,100000,0.0)
	brain.consider("mr_stone","student_b","class_message",.6,personality,101000,0.0)
	var prior: int=int(brain.incidents["mr_stone:student_a"].count)
	var mood: float=float(brain.teachers.mr_stone.frustration)
	if Dialogue.message_intent("Mr Stone, sorry for interrupting")!="apology":push_error("Addressed apology was not recognized");quit(1);return
	if not brain.accept_apology("mr_stone","student_a",113000):push_error("Recent apology was ignored");quit(1);return
	if int(brain.incidents["mr_stone:student_a"].count)!=prior-1 or float(brain.teachers.mr_stone.frustration)>=mood:push_error("Apology did not ease the active warning");quit(1);return
	if int(brain.incidents["mr_stone:student_b"].count)!=1:push_error("Apology changed another student's warning");quit(1);return
	if brain.accept_apology("mr_stone","student_a",114000) or brain.accept_apology("mr_stone","student_b",170000):push_error("Duplicate or stale apology was accepted");quit(1);return
	if not brain.accept_apology("mr_stone","student_b",120000):push_error("Second student's recent apology was blocked");quit(1);return
	brain.consider("mr_stone","hazard_student","lab_hazard",.8,personality,130000,0.0)
	if brain.accept_apology("mr_stone","hazard_student",143000):push_error("Apology erased a circuit safety incident");quit(1);return
	print("TEACHER_APOLOGY PASS")
	quit(0)
