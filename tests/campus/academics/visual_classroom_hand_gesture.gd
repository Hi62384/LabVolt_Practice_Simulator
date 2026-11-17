extends SceneTree
const Toon=preload("res://scripts/toon_character.gd")
const Avatar=preload("res://scripts/avatar_model.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var scene:=Node3D.new();root.add_child(scene)
 var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(0,1.45,3.3);camera.look_at(Vector3(0,1.15,0));camera.current=true
 var light:=DirectionalLight3D.new();scene.add_child(light);light.rotation=Vector3(deg_to_rad(-45),deg_to_rad(25),0)
 var environment:=WorldEnvironment.new();scene.add_child(environment)
 var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("283d48");settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color.WHITE;settings.ambient_light_energy=.8;environment.environment=settings
 var raised:=Toon.build(Toon.defaults());scene.add_child(raised);raised.position.x=-.7
 var neutral:=Toon.build(Toon.defaults());scene.add_child(neutral);neutral.position.x=.7
 Avatar.raise_hand(raised,true,1.0)
 assert(raised.find_child("ArmR",true,false).rotation.z>neutral.find_child("ArmR",true,false).rotation.z+1.0)
 for i in 8:await process_frame
 await RenderingServer.frame_post_draw
 var path:=ProjectSettings.globalize_path("res://.godot/classroom-hand-gesture.png")
 assert(root.get_texture().get_image().save_png(path)==OK)
 print("CLASSROOM_HAND_CAPTURE PASS ",path)
 scene.queue_free();await process_frame;quit()
