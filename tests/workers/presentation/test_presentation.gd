extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var physical=game.dc_lab.physical_boards[0]
 var board=load("res://scripts/breadboard_model.gd").empty()
 board.parts=[{"id":"lamp","type":"led_green","a":"A3","b":"F3"},{"id":"r","type":"r1000","a":"A6","b":"F6"},{"id":"c","type":"c10","a":"A9","b":"F9"},{"id":"diode","type":"diode","a":"A12","b":"F12"},{"id":"switch","type":"toggle","a":"A15","b":"F15"},{"id":"mcu","type":"lv_mcu","a":"A20","b":"F22","pins":["A20","A21","A22","F20","F21","F22"]},{"id":"sound","type":"speaker","a":"A26","b":"F26"}]
 var state={"board":board,"result":{"i":{"board/lamp":.01}},"board_owner":1}
 physical.update_state(state)
 var models=physical.component_models
 var old= models.lights["board/lamp"].mesh.get_instance_id()
 board.controls={"board/switch":{"pressed":true}}
 physical.update_state(state)
 assert(models.lights["board/lamp"].mesh.get_instance_id()==old,"State changes must not rebuild geometry")
 assert(models.actuators["board/switch"].mesh.rotation.x<0,"Controls must use authoritative state")
 var labels=0
 for child in models.get_children():
  if child is Label3D and child.has_meta("pin_index"):
   labels+=1;assert(child.position.is_finite())
 assert(labels==18,"All physical pins need catalog labels")
 state.result.i["board/lamp"]=0.;physical.update_state(state)
 assert(not models.lights["board/lamp"].mesh.material_override.emission_enabled)
 if DisplayServer.get_name()!="headless":
  game.process_mode=Node.PROCESS_MODE_DISABLED
  for child in game.get_children():
   if child is CanvasLayer:child.hide()
  var camera=Camera3D.new();root.add_child(camera);camera.position=physical.global_position+Vector3(0,1.05,.55);camera.look_at(physical.global_position+Vector3(-.2,0,0),Vector3.UP);camera.make_current()
  for i in 4:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://../outputs/components-review.png")
 print("PASS: stable mesh identity, authoritative controls, pin labels, LED solved state and rendered review")
 quit()
