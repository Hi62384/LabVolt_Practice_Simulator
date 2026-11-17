extends SceneTree
func _initialize():call_deferred("run")
func run():
 var world:=Node3D.new();root.add_child(world)
 var env:=WorldEnvironment.new();var data:=Environment.new();data.background_mode=Environment.BG_COLOR;data.background_color=Color("223643");data.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;data.ambient_light_color=Color.WHITE;data.ambient_light_energy=.8;env.environment=data;world.add_child(env)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);world.add_child(light)
 var config: Dictionary=preload("res://scripts/toon_character.gd").defaults()
 var args:=OS.get_cmdline_user_args();var exercise:=str(args[0]) if not args.is_empty() else "curl"
 if args.size()>1:config.outfit=str(args[1])
 var avatar=preload("res://scripts/toon_character.gd").build(config);world.add_child(avatar)
 var weights=preload("res://scripts/campus/facilities/gym_weights.gd").new()
 var arm=avatar.find_child("ArmR",true,false)
 var pair=weights._pair_model(25.0)
 for child in pair.get_children():
  if child.position.z<0:pair.remove_child(child);child.queue_free()
  else:child.position.z=0
 var hand=preload("res://scripts/campus/facilities/arm_bend.gd").hand_for(arm)
 arm.add_child(pair)
 var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();world.add_child(activity);activity.bind_visual(avatar)
 activity.apply_event({"activity":"exercise","station":"gym/dumbbell/1","exercise":exercise,"phase":1,"half_ms":700,"equipment":"dumbbell"},false)
 for i in 100:activity._process(.02)
 var orientation: Basis=hand.transform.basis.orthonormalized()
 pair.transform=Transform3D(orientation,hand.position+orientation*Vector3(0,0,.038))
 var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(1.6,1.45,2.3);camera.look_at(Vector3(0,1.0,0));camera.fov=38;camera.current=true
 await process_frame;await process_frame;await RenderingServer.frame_post_draw
 var image:=root.get_texture().get_image()
 image.save_png(ProjectSettings.globalize_path("res://.godot/dumbbell-"+exercise+"-"+config.outfit+".png"))
 print("VISUAL dumbbell screenshot saved")
 weights.free();world.queue_free();await process_frame;quit()
