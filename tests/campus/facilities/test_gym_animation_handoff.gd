extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var model: Node3D = preload("res://scripts/avatar_model.gd").build(FileAccess.get_file_as_bytes("res://assets/default_avatar.glb"))
	if model == null:
		push_error("Could not load default avatar")
		quit(1);return
	root.add_child(model)
	var activity: Node3D = preload("res://scripts/campus/facilities/avatar_activity.gd").new()
	root.add_child(activity)
	activity.bind_visual(model)
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	preload("res://scripts/avatar_model.gd").animate(model, true)
	if not player.is_playing():
		push_error("Walking animation did not start")
		quit(1);return
	activity.apply_event({"activity":"exercise", "exercise":"curl", "station":"test"}, false)
	preload("res://scripts/avatar_model.gd").animate(model, true)
	if player.is_playing() or not model.get_meta("facility_activity_pose", false):
		push_error("Walking animation overwrote exercise")
		quit(1);return
	activity.apply_event({"activity":"idle"}, false)
	preload("res://scripts/avatar_model.gd").animate(model, true)
	if not player.is_playing() or model.has_meta("facility_activity_pose"):
		push_error("Walking animation did not resume")
		quit(1);return
	print("GYM_ANIMATION_HANDOFF PASS")
	quit(0)
