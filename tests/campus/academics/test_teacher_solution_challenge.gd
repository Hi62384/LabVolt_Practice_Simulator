extends SceneTree
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Behavior=preload("res://scripts/campus/academics/character_behavior.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if Dialogue.message_intent("Mr Stone, your answer is wrong?")!="challenge":push_error("Teacher solution challenge was not recognized");quit(1);return
	if Dialogue.message_intent("I made a mistake on my answer")!="chat":push_error("Student's own mistake became a teacher challenge");quit(1);return
	var general: String=Dialogue.respond("mr_stone","challenge",{"phase":"lesson","round_mode":"practice"},0)
	var active: String=Dialogue.respond("mr_stone","challenge",{"phase":"lesson","round_mode":"mistake"},0)
	if not general.is_empty() or not active.is_empty():
		push_error("Worked-example modes selected canned character dialogue");quit(1);return
	var person:=Profiles.teacher("mr_stone")
	var challenge:=Mind.new().observe(person,{},"Your answer is wrong.",0,"student","challenge","solution-challenge",{"phase":"lesson","domain":"electronics","severity":.4})
	assert(challenge.event=="challenge" and not challenge.closed and challenge.strategy=="defend_belief","A challenge creates the teacher's actual disagreement decision")
	assert(Behavior.priorities(person,"Your answer is wrong.",{},"assignment","steady",{"event":"challenge","domain":"electronics"}).goal=="protect_assessment","A challenge cannot bypass independent-assessment rules")
	print("TEACHER_SOLUTION_CHALLENGE PASS")
	quit(0)
