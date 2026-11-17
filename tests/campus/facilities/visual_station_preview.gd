extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args:=OS.get_cmdline_user_args();var exercise:=str(args[0]) if not args.is_empty() else "pullup"
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("202e3a")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.8;environment.environment=settings;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);world.add_child(light)
	for side in [-1.0,1.0]:
		_part(world,Vector3(side*.9,1.3,0),Vector3(.12,2.6,.12))
		_part(world,Vector3(side*.48,1.05,.38),Vector3(.09,.09,.8))
	_part(world,Vector3(0,2.6,0),Vector3(2,.12,.12))
	var avatar=preload("res://scripts/toon_character.gd").build({});world.add_child(avatar)
	var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();world.add_child(activity);activity.bind_visual(avatar)
	var grip:=Vector3(0,1.05,.75) if exercise=="dip" else Vector3(0,2.6,0)
	activity.apply_event({"activity":"exercise","station":"gym/pullup","exercise":exercise,"phase":1,"half_ms":700,"grip_anchor":grip},false)
	for i in 150:activity._process(.02)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(3,2.2,4);camera.look_at(Vector3(0,1.4,.1));camera.fov=38;camera.current=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/station-"+exercise+".png"))
	world.queue_free();await process_frame;quit()
func _part(parent: Node3D,pos: Vector3,size: Vector3) -> void:
	var part:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;part.mesh=mesh;part.position=pos;parent.add_child(part)
