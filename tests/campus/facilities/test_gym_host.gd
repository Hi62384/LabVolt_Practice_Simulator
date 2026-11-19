extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var profile=Host.empty_profile()
var now:=1000
func _initialize():
 var host=Host.new()
 host.authority=func():return true
 host.dumbbell_mass=func(_peer):return 20.0
 host.clock=func():return now
 host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
 host.load_profile=func(_id):return profile.duplicate(true)
 host.commit_profile=func(_id,_d,p):profile=p.duplicate(true);return true
 host.anchors={"curl":{"kind":"curl","room_id":"gym","position":Vector3.ZERO}}
 var result=host.act(1,{"op":"start","station":"curl","weight":20,"sequence":1})
 assert(result.ok)
 var seq:=1;var failed:=false
 for i in 30:
  now+=int(host.active[1].half_ms);seq+=1
  result=host.act(1,{"op":"lower","sequence":seq})
  assert(result.ok)
  now+=int(host.active[1].half_ms);seq+=1
  result=host.act(1,{"op":"beat","sequence":seq})
  assert(result.ok)
  if result.muscular_failure:failed=true;break
 assert(failed and profile.gym.muscles.biceps.fatigue>0)
 assert(profile.gym.muscles.biceps.strength==0)
 assert(Host.valid_profile(profile))
 print("PASS gym host persists fatigue and ends physically failed set")
 quit()
