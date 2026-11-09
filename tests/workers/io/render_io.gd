extends SceneTree
const Catalog=preload("res://scripts/io_devices/catalog.gd")
const Surface=preload("res://scripts/io_devices/surface.gd")
const Physical=preload("res://scripts/io_devices/physical_surface.gd")
const D=preload("res://scripts/io_devices/devices.gd")
const Solver=preload("res://scripts/electronics_solver.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,900)
	root.content_scale_size=Vector2i(1280,900)
	var background := ColorRect.new();background.size=Vector2(1280,900);background.color=Color("111c26");root.add_child(background)
	var index := 0
	for kind in Catalog.all():
		var surface := Surface.new();surface.position=Vector2(20+(index%5)*250,45+(index/5)*280);surface.size=Vector2(220,220);root.add_child(surface)
		var n: Array=[]
		for pin in Catalog.all()[kind].pins.size():n.append("n"+str(pin))
		var expanded := D.expand(Catalog.all()[kind],kind,n,{}, {},{})
		var solved := Solver.new().solve(expanded.filter(func(p):return p.kind!="io_device"),[],.0005)
		var state := D.tick(expanded[0],solved,{},.0005)
		surface.present(kind,state)
		var label := Label.new();label.position=surface.position+Vector2(0,224);label.text=Catalog.all()[kind].name;label.add_theme_font_size_override("font_size",13);root.add_child(label)
		index+=1
	# Physical adapter renders the same pixels into an actual 3D surface.
	var sub := SubViewport.new();sub.size=Vector2i(256,256);sub.own_world_3d=true;sub.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(sub)
	var physical := Physical.new();sub.add_child(physical)
	physical.present("io_encoder",{"control":{"detent":3}})
	var camera := Camera3D.new();sub.add_child(camera);camera.position=Vector3(0,.1,0);camera.rotation_degrees.x=-90.;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.1
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../work/io-disconnected-preview.png")
	var result := root.get_texture().get_image().save_png(path)
	var physical_result := sub.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/io-physical-preview.png"))
	var commands: Array=[]
	physical.command_requested.connect(func(command):
		commands.append(command)
		var accepted := preload("res://scripts/io_devices/controls.gd").apply("io_keypad",physical.surface.control,command)
		if accepted.ok:physical.present("io_keypad",{"control":accepted.state})
	)
	physical.present("io_keypad",{"control":{"revision":0,"keys":0}});physical.set_interact(true)
	physical.pointer_event(Vector3(-.03,0,-.03),true)
	await process_frame
	physical.pointer_event(Vector3(.03,0,.03),false)
	await process_frame
	var interaction: bool=commands.size()==2 and commands[0].key==9 and commands[1].key==9 and commands[0].pressed and not commands[1].pressed and commands[1].revision==1
	print("IO PHYSICAL INPUT ","PASS" if interaction else "FAIL", " ",commands)
	print("IO RENDER ","PASS" if result==OK and physical_result==OK else "FAIL"," ",path)
	quit(0 if result==OK and physical_result==OK and interaction else 1)
