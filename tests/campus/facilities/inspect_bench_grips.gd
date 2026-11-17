extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var avatar=preload("res://scripts/toon_character.gd").build({});world.add_child(avatar)
	var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();world.add_child(activity);activity.bind_visual(avatar)
	for name in ["benchpress","incline_press","overhead_press","front_raise","curl","wrist_curl","overhead_extension","good_morning","chest_supported_row"]:
		for phase in [0.0,1.0]:
			activity.apply_event({"activity":"exercise","station":"gym/benchpress","exercise":name,"phase":phase,"half_ms":700,"bench_position":Vector3(4,0,31.5)},false)
			for i in 100:activity._process(.02)
			var left: Node3D=avatar.get_node("Body/ArmL/Hand")
			var right: Node3D=avatar.get_node("Body/ArmR/Hand")
			print(name," ",phase," ",(left.global_position+right.global_position)*.5)
		activity.apply_event({"activity":"idle"},false)
	world.free();quit()
