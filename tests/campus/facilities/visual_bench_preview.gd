extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("202e3a")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.8
	environment.environment=settings;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);world.add_child(light)
	var bench=preload("res://scripts/campus/facilities/gym_bench.gd").new();bench.position=Vector3(4,0,31);world.add_child(bench);bench.build()
	var args:=OS.get_cmdline_user_args();var exercise:=str(args[0]) if not args.is_empty() else "benchpress"
	var phase:=float(args[1]) if args.size()>1 else 1.0
	var config: Dictionary=preload("res://scripts/toon_character.gd").defaults()
	if args.size()>2:config.outfit=str(args[2])
	if args.size()>3:config.height=float(args[3])
	var avatar=preload("res://scripts/toon_character.gd").build(config);world.add_child(avatar)
	var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();world.add_child(activity);activity.bind_visual(avatar)
	var motion=preload("res://scripts/campus/presentation/decor/m105/gym_equipment_motion.gd").new();world.add_child(motion)
	motion.grip_position=func(_peer):
		var joints=preload("res://scripts/campus/facilities/arm_bend.gd")
		var left: Node3D=joints.hand_for(avatar.find_child("ArmL",true,false) as Node3D)
		var right: Node3D=joints.hand_for(avatar.find_child("ArmR",true,false) as Node3D)
		return (left.global_position+right.global_position)*.5 if is_instance_valid(left) and is_instance_valid(right) else null
	var event:={"activity":"exercise","station":"gym/benchpress","exercise":exercise,"phase":phase,"half_ms":700,"bench_position":Vector3(4,0,31.5)}
	if exercise=="chest_fly":event.equipment="dumbbell"
	activity.apply_event(event,false);motion.on_room_event(1,event);bench.on_room_event(1,event)
	for i in 100:activity._process(.02);motion._process(.02);bench._process(.02)
	var weights: Node
	if exercise=="chest_fly":
		motion.bars["gym/benchpress"].hide()
		weights=preload("res://scripts/campus/facilities/gym_weights.gd").new()
		for side in ["ArmL","ArmR"]:
			var arm: Node3D=avatar.find_child(side,true,false)
			var hand: Node3D=preload("res://scripts/campus/facilities/arm_bend.gd").hand_for(arm)
			var pair: Node3D=weights._pair_model(25.0)
			for child in pair.get_children():
				if child.position.z<0:pair.remove_child(child);child.queue_free()
				else:child.position.z=0
			arm.add_child(pair)
			var orientation:=hand.transform.basis.orthonormalized()
			pair.transform=Transform3D(orientation,hand.position+orientation*Vector3(0,0,.038))
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(6.8,2.0,33.3);camera.look_at(Vector3(4,.9,31.2));camera.fov=35;camera.current=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://.godot/bench-visual-%s-%s-%s-%s.png" % [exercise,phase,config.outfit,config.height]))
	print("BENCH_VISUAL screenshot saved")
	if is_instance_valid(weights):weights.free()
	world.queue_free();await process_frame;quit()
