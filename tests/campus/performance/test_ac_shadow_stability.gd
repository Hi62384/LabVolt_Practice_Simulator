extends SceneTree
## Rendered check: returning to the same view after crossing the lab should not
## change the ceiling lighting or floor shadows.
func _initialize() -> void:call_deferred("run")
func capture(game: Node, position: Vector3) -> Image:
 game.player.global_position=position
 game.campus.set_viewer_position(position)
 await create_timer(.4).timeout
 await RenderingServer.frame_post_draw
 return root.get_texture().get_image()
func run() -> void:
 if DisplayServer.get_name()=="headless":printerr("Rendered shadow test needs a display");quit(2);return
 DisplayServer.window_set_size(Vector2i(1280,720))
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game);game.front.entered()
 game.player.enabled=false;game.camera.current=true
 game.player.rotation.y=0;game.player.yaw_target=0;game.player.eyes.rotation.x=0;game.player.pitch_target=0
 await capture(game,Vector3(0,0,5))
 await create_timer(4.0).timeout
 var initial: Image=await capture(game,Vector3(0,0,5))
 await capture(game,Vector3(6,0,5))
 await capture(game,Vector3(-6,0,5))
 var final: Image=await capture(game,Vector3(0,0,5))
 for region in [[.15,.30],[.60,.80]]:
  var difference:=0.0;var count:=0
  for y in range(int(initial.get_height()*region[0]),int(initial.get_height()*region[1]),6):
   for x in range(int(initial.get_width()*.10),int(initial.get_width()*.80),6):
    var a:=initial.get_pixel(x,y);var b:=final.get_pixel(x,y)
    difference+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b);count+=3
  var mean:=difference/maxi(count,1)
  print("AC_SHADOW_STABILITY region=%s mean_color_difference=%.5f samples=%d"%[region,mean,count])
  if mean>.02:push_error("AC lighting changed after crossing the room");quit(1);return
 quit()

