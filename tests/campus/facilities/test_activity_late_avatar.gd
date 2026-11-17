extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var service=preload("res://scripts/campus/facilities/facility_service.gd").new();root.add_child(service)
	var controller=preload("res://scripts/campus/facilities/facility_controller.gd").new();service.add_child(controller);service.controller=controller;controller.room_event.connect(service._event)
	controller._event(2,{"activity":"exercise","station":"gym/squat","exercise":"squat","phase":1})
	var parent:=Node3D.new();root.add_child(parent)
	var avatar: Node3D=preload("res://scripts/toon_character.gd").build(preload("res://scripts/toon_character.gd").defaults());parent.add_child(avatar)
	service.bind_avatar(2,avatar)
	var activity: Node=service.visuals.get(2)
	var ok: bool=is_instance_valid(activity) and activity.state.get("activity","")=="exercise" and activity.state.get("exercise","")=="squat"
	controller._event(2,{"activity":"idle"})
	service.unbind_avatar(2)
	service.bind_avatar(2,avatar)
	activity=service.visuals.get(2)
	ok=ok and is_instance_valid(activity) and activity.state.get("activity","")=="idle"
	controller._event(2,{"activity":"exercise","station":"gym/squat","exercise":"squat","phase":1})
	controller.reset_presentation()
	ok=ok and controller.visual_states.is_empty() and activity.state.get("activity","")=="idle"
	controller._event(2,{"activity":"spot_assist","duration_ms":1800})
	service.unbind_avatar(2);service.bind_avatar(2,avatar)
	activity=service.visuals.get(2)
	ok=ok and is_instance_valid(activity) and activity.state.get("activity","")=="idle"
	if not ok:push_error("Late-created avatar did not receive the current activity")
	service.free();parent.free()
	print("ACTIVITY_LATE_AVATAR ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
