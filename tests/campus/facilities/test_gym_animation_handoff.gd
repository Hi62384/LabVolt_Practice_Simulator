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
	var mat:=Vector3(2,.09,3)
	var contacts=preload("res://scripts/campus/facilities/gym_mat_pose.gd")
	for exercise in ["pushup","pike_pushup"]:
		for phase in [0,1]:
			activity.apply_event({"activity":"exercise","exercise":exercise,"mat_position":mat,"phase":phase},false)
			for frame in 90:activity._process(1.0/60.0)
			for side in [-1.0,1.0]:
				var nameplate: String="ArmL" if side<0 else "ArmR"
				var palm:=preload("res://scripts/campus/facilities/arm_bend.gd").hand_for(activity.arms[nameplate].node)
				assert(palm.global_position.distance_to(contacts.palm(mat,side,exercise))<.005)
			assert(model.to_global(Vector3.UP*.86).distance_to(contacts.hips(mat,exercise,phase))<.005)
	var bench:=Vector3(2,0,3)
	var rules=preload("res://scripts/campus/facilities/facility_host.gd")
	var pad=preload("res://scripts/campus/facilities/gym_bench.gd")
	for exercise in rules.BENCH_DUMBBELL_EXERCISES:
		activity.apply_event({"activity":"exercise","exercise":exercise,"bench_position":bench,"phase":0},false)
		for frame in 90:activity._process(1.0/60.0)
		var pose: Transform3D=pad.body_pose(exercise,1.0)
		assert(model.global_position.distance_to(bench+pose.origin)<.005)
		assert(model.global_basis.y.normalized().dot(pose.basis.y)>.999)
		assert(model.global_basis.z.normalized().dot(pose.basis.z)>.999)
	print("GYM_ANIMATION_HANDOFF PASS")
	quit(0)
