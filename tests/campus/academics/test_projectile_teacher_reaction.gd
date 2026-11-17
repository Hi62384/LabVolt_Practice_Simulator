extends SceneTree
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
func _initialize() -> void:
	var brain:=Brain.new()
	var decision: Dictionary=brain.consider("bill_nye","student","thrown_object",1.0,{"difficulty":1.0,"focus":1.0},50000,0.0,1.0)
	assert(decision.get("intent","")=="throw")
	var response:=Dialogue.respond("bill_nye","throw",{"impact_kind":"student"},0)
	assert(response.contains("student"))
	print("PROJECTILE_TEACHER_REACTION PASS")
	quit()
