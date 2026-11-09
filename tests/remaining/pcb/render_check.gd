extends SceneTree
var output := ""
func capture(name: String) -> void:
 for i in 4:await process_frame
 await RenderingServer.frame_post_draw
 var error:=root.get_texture().get_image().save_png(output+"/"+name+".png")
 if error!=OK:push_error("Capture save failed");quit(2)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
 if output.is_empty():quit(2);return
 root.size=Vector2i(1280,800)
 var bp: Dictionary=preload("res://tests/remaining/pcb/pcb_tests.gd").fixture()
 bp.pcb_design.outline=[[0,0],[7,0],[7,5],[4,5],[4,4],[2,4],[2,5],[0,5]]
 var profile=preload("res://scripts/electronics_profile.gd").new();profile.open("pcb_render_private")
 var panel:=PanelContainer.new();panel.position=Vector2(20,20);panel.size=Vector2(1240,760);root.add_child(panel)
 var scroll:=ScrollContainer.new();panel.add_child(scroll)
 var editor=preload("res://scripts/pcb_design/editor.gd").new();editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(editor);editor.build(profile,bp)
 await capture("editor")
 panel.queue_free();await process_frame
 var board: Dictionary=preload("res://scripts/breadboard_model.gd").standalone("ic:render",{"ic:render":bp})
 var canvas=preload("res://scripts/breadboard_canvas.gd").new();root.add_child(canvas);canvas.board=board;canvas.position=Vector2(40,40);canvas.size=Vector2(1200,700);canvas.read_only=true
 await capture("standalone-2d")
 canvas.queue_free();await process_frame
 var viewport:=SubViewport.new();viewport.size=Vector2i(1000,440);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
 canvas=preload("res://scripts/breadboard_canvas.gd").new();viewport.add_child(canvas);canvas.custom_minimum_size=Vector2.ZERO;canvas.size=Vector2(1000,440);canvas.board=board;canvas.read_only=true
 var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("20313c");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color("ecf3ef");settings.ambient_light_energy=.8;environment.environment=settings;root.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);root.add_child(sun)
 var helper=preload("res://scripts/equipment_builder.gd").new();root.add_child(helper)
 helper._box(helper,Vector3(0,-.08,0),Vector3(2.3,.1,1.3),Color("9b8567"))
 var physical=preload("res://scripts/pcb_design/routed_components.gd").new();root.add_child(physical)
 physical.update_models(helper,canvas,{"i":{}})
 var camera:=Camera3D.new();camera.position=Vector3(1.1,1.6,1.6);root.add_child(camera);camera.look_at(Vector3(0,0,0));camera.current=true
 await capture("physical")
 print("PCB_RENDER_CHECK captures=3 success=true")
 quit(0)

