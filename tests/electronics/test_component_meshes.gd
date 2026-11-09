extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var physical=game.dc_lab.physical_boards[0]
 var board=load("res://scripts/breadboard_model.gd").empty()
 board.parts=[{"id":"lamp","type":"led","a":"A1","b":"F1"},{"id":"r","type":"r1000","a":"A2","b":"F2"}]
 var state={"board":board,"result":{"i":{"board/lamp":.01}},"board_owner":1}
 physical.update_state(state)
 assert(physical.component_models.get_child_count()>3)
 var mat=physical.component_models.lights["board/lamp"].mesh.material_override
 assert(mat.emission_enabled)
 state.result.i["board/lamp"]=0.;physical.update_state(state);assert(not mat.emission_enabled)
 if DisplayServer.get_name()!="headless":
  game.process_mode=Node.PROCESS_MODE_DISABLED
  for child in game.get_children():
   if child is CanvasLayer:child.hide()
  var camera=Camera3D.new();root.add_child(camera);camera.position=physical.global_position+Vector3(0,1.1,1);camera.look_at(physical.global_position,Vector3.UP);camera.make_current()
  await process_frame;await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("C:/Users/User1/Documents/Codex/2026-11-03/bas/work/dc_expansion/components_review.png")
 print("PASS: raised physical components and LED emission follow actual device current")
 quit()


