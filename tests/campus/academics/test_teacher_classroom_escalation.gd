extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Behavior=preload("res://scripts/campus/academics/character_behavior.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var strict=Brain.new()
	var patient=Brain.new()
	var early: Dictionary=strict.consider("mr_stone","student","class_message",.5,{"difficulty":.95,"focus":.9,"talkativeness":.5},100000,0.0)
	if early.get("level","")!="calm":push_error("First interruption was not calm");quit(1);return
	var later: Dictionary={}
	for i in 5:
		later=strict.consider("mr_stone","student","class_message",.5,{"difficulty":.95,"focus":.9,"talkativeness":.5},113000+i*13000,0.0)
	if later.get("level","")!="firm":push_error("Repeated interruption never escalated");quit(1);return
	var patient_later: Dictionary={}
	for i in 6:
		patient_later=patient.consider("ms_clocks","student","class_message",.5,{"difficulty":.15,"focus":.9,"talkativeness":.5},100000+i*13000,0.0)
	if patient_later.get("level","")!="calm":push_error("Patient teacher escalated too quickly");quit(1);return
	var calm_text: String=Dialogue.respond("mr_stone","class_message",{"phase":"lesson","level":"calm"},0)
	var firm_text: String=Dialogue.respond("mr_stone","class_message",{"phase":"lesson","level":"firm"},0)
	var assessment_text: String=Dialogue.respond("mr_stone","class_message",{"phase":"assignment","level":"firm"},0)
	if not calm_text.is_empty() or not firm_text.is_empty() or not assessment_text.is_empty():
		push_error("Legacy event handlers fabricated ordinary character speech");quit(1);return
	var person:=Profiles.teacher("mr_stone")
	var mild:=Mind.new().observe(person,{},"A student interrupts the class.",0,"learner","disruption","mild",{"phase":"lesson","severity":.2})
	var loud:=Mind.new().observe(person,{},"A student repeatedly interrupts the class.",0,"learner","disruption","loud",{"phase":"lesson","severity":.95})
	assert(float(loud.emotions.irritation)>float(mild.emotions.irritation),"Host perception intensity reaches actual character affect")
	assert(Behavior.priorities(person,"Which answer is right?",{},"assignment").goal=="protect_assessment","Assessment integrity remains independent of ordinary dialogue generation")
	print("TEACHER_CLASSROOM_ESCALATION PASS")
	quit(0)
