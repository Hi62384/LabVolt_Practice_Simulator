extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var lab_roots=[]
 for name in ["M101Environment","M103RoomFinish","TeachingFinish_elm253_lecture","TeachingFinish_ety155_lecture"]:
  var lab=game.campus.find_child(name,true,false)
  if lab==null:push_error("Lab lighting root missing: "+name);quit(1);return
  lab_roots.append(lab)
  var shadow_lights=[]
  for light in lab.find_children("*","SpotLight3D",true,false):
   if light.shadow_enabled:shadow_lights.append(light)
  var expected=3 if name=="M101Environment" else 1
  if shadow_lights.size()!=expected:push_error("Unexpected local shadow fixture count in "+name);quit(1);return
  for light in shadow_lights:
   if light.distance_fade_enabled:push_error("Lab shadow fixture changes with camera distance");quit(1);return
 var settings=game.ui.graphics_controller
 settings.set_option("shadows",false)
 for lab in lab_roots:
  for light in lab.find_children("*","SpotLight3D",true,false):
   if light.shadow_enabled:push_error("Shadow setting did not disable a fixture");quit(1);return
 settings.set_option("shadows",true)
 for lab in lab_roots:
  var count=0
  for light in lab.find_children("*","SpotLight3D",true,false):
   if light.shadow_enabled:count+=1
  var expected=3 if lab.name=="M101Environment" else 1
  if count!=expected:push_error("Shadow setting did not restore the stable fixtures");quit(1);return
 print("PASS: lab shadow fixtures remain fixed and graphics setting toggles them")
 quit()
