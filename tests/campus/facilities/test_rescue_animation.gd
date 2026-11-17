extends SceneTree
const Activity=preload("res://scripts/campus/facilities/avatar_activity.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var parent:=Node3D.new();root.add_child(parent)
	var visual:=preload("res://scripts/toon_character.gd").build({});parent.add_child(visual)
	var activity:=Activity.new();parent.add_child(activity);activity.bind_visual(visual)
	var arm:=visual.find_child("ArmR",true,false) as Node3D
	var original:=arm.transform
	activity.apply_event({"activity":"spotting"},false)
	activity._process(.2)
	var ok: bool=visual.has_meta("facility_activity_pose") and arm.transform!=original
	activity.apply_event({"activity":"idle"},false)
	ok=ok and not visual.has_meta("facility_activity_pose") and arm.transform==original
	activity.apply_event({"activity":"assist","target":2},false)
	activity._process(.2)
	ok=ok and visual.has_meta("facility_activity_pose") and arm.transform!=original
	activity._process(2.0)
	ok=ok and not visual.has_meta("facility_activity_pose") and arm.transform==original
	if not ok:push_error("Rescue animation did not pose and restore the helper")
	print("RESCUE_ANIMATION ","PASS" if ok else "FAIL")
	parent.free();quit(0 if ok else 1)
