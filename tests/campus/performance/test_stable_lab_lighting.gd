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
 var representative: SpotLight3D=lab_roots[0].find_children("*","SpotLight3D",true,false)[0]
 var base_energy:=representative.light_energy
 var base_tint:=representative.light_color
 settings.set_option("indoor_intensity",1.4)
 if not is_equal_approx(representative.light_energy,base_energy*1.4):push_error("Fixture intensity did not update");quit(1);return
 settings.set_option("lighting_tone","Warm")
 if representative.light_color==base_tint:push_error("Fixture tone did not update");quit(1);return
 settings.set_option("brightness",1.2)
 var environment: WorldEnvironment=game.find_child("WorldEnvironment",true,false)
 if not is_equal_approx(environment.environment.tonemap_exposure,1.2):push_error("Brightness did not change exposure");quit(1);return
 settings.set_option("bloom_quality",0)
 if environment.environment.glow_enabled:push_error("Bloom Off did not disable glow");quit(1);return
 print("PASS: stable shadow fixtures, indoor intensity, tone, exposure and bloom")
 quit()
