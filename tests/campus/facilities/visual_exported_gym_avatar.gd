extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var coordinator=preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not coordinator.load_catalog(): push_error("Catalog unavailable");quit(1);return
	var customization:={"body":{"width":1.2},"equipped":{"top_inner":{"id":"tops.harbor_fitted_tee","parameters":{}}}}
	var path:="user://gym_visual_custom_avatar.glb"
	if preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd").save_glb(customization,coordinator.catalog,path)!=OK:
		push_error("Avatar export failed");quit(1);return
	var actor: Node3D=preload("res://scripts/avatar_model.gd").build(FileAccess.get_file_as_bytes(path))
	if actor==null: push_error("Avatar import failed");quit(1);return
	var world:=Node3D.new();root.add_child(world);world.add_child(actor)
	var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("202e3a")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color.WHITE;env.ambient_light_energy=.8
	var atmosphere:=WorldEnvironment.new();atmosphere.environment=env;world.add_child(atmosphere)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);world.add_child(light)
	var sizes:={}
	for muscle in preload("res://scripts/campus/facilities/gym_progress.gd").MUSCLE_GROUPS:sizes[muscle]=1.0
	preload("res://scripts/campus/facilities/muscle_visual.gd").apply(actor,sizes)
	var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();world.add_child(activity);activity.bind_visual(actor)
	activity.apply_event({"activity":"exercise","station":"gym/curl","exercise":"curl","phase":1,"half_ms":700},false)
	for i in 80:activity._process(.02)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(1.7,1.7,-4.2);camera.look_at(Vector3(0,1,0));camera.fov=32;camera.current=true
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/gym-exported-muscle.png"))
	print("EXPORTED_GYM_CAPTURE ","PASS" if error==OK else "FAIL")
	world.queue_free();await process_frame;quit(0 if error==OK else 1)
