extends SceneTree
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if Dialogue.message_intent("Mr Stone, your answer is wrong?")!="challenge":push_error("Teacher solution challenge was not recognized");quit(1);return
	if Dialogue.message_intent("I made a mistake on my answer")!="chat":push_error("Student's own mistake became a teacher challenge");quit(1);return
	var general: String=Dialogue.respond("mr_stone","challenge",{"phase":"lesson","round_mode":"practice"},0)
	var active: String=Dialogue.respond("mr_stone","challenge",{"phase":"lesson","round_mode":"mistake"},0)
	if general==active or not general.contains("step") or not active.contains("before I reveal it"):
		push_error("Challenge response did not respect active worked example");quit(1);return
	print("TEACHER_SOLUTION_CHALLENGE PASS")
	quit(0)
