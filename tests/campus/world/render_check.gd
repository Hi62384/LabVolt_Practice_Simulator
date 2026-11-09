extends SceneTree
var campus: Node3D
var camera: Camera3D
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var environment:=WorldEnvironment.new()
 var settings:=Environment.new()
 settings.background_mode=Environment.BG_COLOR
 settings.background_color=Color("9cbcc3")
 settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 settings.ambient_light_color=Color("d5e4de")
 settings.ambient_light_energy=.8
 environment.environment=settings;root.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=.7;sun.shadow_enabled=true;root.add_child(sun)
 campus=preload("res://scenes/campus/Campus.tscn").instantiate();root.add_child(campus)
 camera=Camera3D.new();camera.current=true;camera.fov=75;root.add_child(camera)
 var output:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
 if output.is_empty():push_error("Pass absolute --output directory");quit(2);return
 var views: Array=[
  ["entrance",Vector3(13,1.65,-18),Vector3(13,1.65,10)],
  ["shop",Vector3(12,1.65,3),Vector3(26,1.65,3)],
  ["labs",Vector3(14,1.65,3),Vector3(0,1.65,3)],
  ["stairs",Vector3(11.5,1.65,48),Vector3(11.5,5.2,61)],
  ["upper",Vector3(13,6.65,-2),Vector3(13,6.65,32)]
 ]
 for view in views:
  camera.position=view[1];camera.look_at(view[2]);campus.set_viewer_position(camera.position)
  for i in 5:await process_frame
  await RenderingServer.frame_post_draw
  var error:=root.get_texture().get_image().save_png(output+"/"+view[0]+".png")
  if error!=OK:push_error("Could not write screenshot");quit(3);return
 print("WORLD_RENDER_CHECK views=5 ",JSON.stringify(campus.metrics()))
 campus.queue_free();camera.queue_free();environment.queue_free();sun.queue_free();await process_frame;quit(0)
