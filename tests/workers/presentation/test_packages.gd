extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var B=load("res://scripts/breadboard_model.gd");var source=B.empty()
 source.parts=[{"id":"button","type":"button","a":"A3","b":"F3"},{"id":"lamp","type":"led","a":"A20","b":"F20"}]
 var bp=B.blueprint(source,"Portable PCB")
 bp.package="PCB";bp.footprint={"width":12,"height":10,"color":"24775b","thickness_mm":12.};bp.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]};bp.marking="PACKAGE CONTRACT v1";bp.orientation_marker="triangle"
 var connectors=["male_header","female_header","through_hole","terminal_block"]
 for i in bp.pins.size():bp.pins[i].position={"x":0 if i%2==0 else 11,"y":0 if i<2 else 9};bp.pins[i].id="stable_"+str(i);bp.pins[i].role="ground" if i==1 else "bidirectional";bp.pins[i].connector=connectors[i]
 var board=B.standalone("ic:pcb",{"ic:pcb":bp})
 var physical=game.dc_lab.physical_boards[0]
 physical.update_state({"board":board,"result":{"i":{"board/pcb/lamp":.01}},"board_owner":1})
 assert(physical.external_ports.size()==4)
 assert(physical.external_ports.X1.x<physical.external_ports.X2.x)
 assert(physical.external_ports.X1.z<physical.external_ports.X3.z)
 assert(abs(physical.external_ports.X1.y-.062)<.00001)
 assert(abs(physical.component_models.elevations["board/pcb/button"]-.012)<.00001)
 for child in physical.controls.get_children():
  if child.get_meta("role","")=="dc_port":assert(child.get_meta("pin_id","").begins_with("stable_"))
 if DisplayServer.get_name()!="headless":
  game.process_mode=Node.PROCESS_MODE_DISABLED
  for child in game.get_children():
   if child is CanvasLayer:child.hide()
  var camera=Camera3D.new();root.add_child(camera);camera.position=physical.global_position+Vector3(0,1.1,.7);camera.look_at(physical.global_position,Vector3.UP);camera.make_current()
  for i in 4:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("user://package-review.png")
 print("PASS: optional package thickness, marking, explicit indexed pin geometry, connectors, exposed elevations without editor dependency")
 quit()

