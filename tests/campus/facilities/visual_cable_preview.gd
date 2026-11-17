extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args();var exercise:=str(args[0]) if not args.is_empty() else "cable_row"
	var phase:=float(args[1]) if args.size()>1 else 1.0
	var config: Dictionary=preload("res://scripts/toon_character.gd").defaults()
	if args.size()>2:config.outfit=str(args[2])
	if args.size()>3:config.height=float(args[3])
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("202e3a")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.8;environment.environment=settings;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);world.add_child(light)
	var machine=preload("res://scripts/campus/facilities/gym_cable_machine.gd").new();world.add_child(machine);machine.build("gym/cable_0")
	var avatar=preload("res://scripts/toon_character.gd").build(config);world.add_child(avatar)
	var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();world.add_child(activity);activity.bind_visual(avatar)
	var event:={"activity":"exercise","station":"gym/cable_0","exercise":exercise,"phase":phase,"half_ms":700,"weight":25,"machine_position":Vector3.ZERO,"cable_stance":Vector3(0,0,1.25)}
	activity.apply_event(event,false);machine.on_room_event(1,event,avatar)
	for i in 150:activity._process(.02);machine._process(.02)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(3,2.2,4);camera.look_at(Vector3(0,1.1,.4));camera.fov=38;camera.current=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/cable-%s-%s-%s-%s.png" % [exercise,phase,config.outfit,config.height]))
	world.queue_free();await process_frame;quit()
