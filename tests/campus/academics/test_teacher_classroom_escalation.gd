extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
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
	if calm_text==firm_text or not firm_text.contains("Stop") or not assessment_text.contains("assessment"):
		push_error("Firm classroom response did not reflect phase");quit(1);return
	print("TEACHER_CLASSROOM_ESCALATION PASS")
	quit(0)
