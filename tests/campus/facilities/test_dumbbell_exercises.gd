extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var profile=Host.empty_profile()
var now:=1000
func _initialize():
 var host=Host.new()
 host.authority=func():return true
 host.clock=func():return now
 host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
 host.load_profile=func(_id):return profile.duplicate(true)
 host.commit_profile=func(_id,_d,p):profile=p.duplicate(true);return true
 host.dumbbell_mass=func(_peer):return 10.0
 for exercise in Host.DUMBBELL_EXERCISES:
  now+=100
  var result=host.act(1,{"op":"start","station":"gym/dumbbell","exercise":exercise,"sequence":profile.last_sequence+1})
  assert(result.ok and host.active[1].exercise==exercise and host.active[1].weight==10.0)
  for i in 2:
   now+=int(host.active[1].half_ms)
   result=host.act(1,{"op":"beat","sequence":profile.last_sequence+1})
   assert(result.ok and not result.muscular_failure)
  now+=100
  assert(host.act(1,{"op":"finish","sequence":profile.last_sequence+1}).ok)
 now+=100
 assert(not host.act(1,{"op":"start","station":"gym/dumbbell","exercise":"dip","sequence":profile.last_sequence+1}).ok)
 host.anchors["gym/benchpress"]={"kind":"benchpress","position":Vector3.ZERO,"room_id":"gym"}
 for exercise in Host.BENCH_DUMBBELL_EXERCISES:
  now+=100
  var start=host.act(1,{"op":"start","station":"gym/benchpress","exercise":exercise,"equipment":"dumbbell","sequence":profile.last_sequence+1})
  assert(start.ok and host.active[1].weight==10.0 and host.active[1].equipment=="dumbbell")
  now+=100
  assert(host.act(1,{"op":"cancel","sequence":profile.last_sequence+1}).ok)
 host.dumbbell_mass=func(_peer):return 0.0
 now+=100
 assert(not host.act(1,{"op":"start","station":"gym/benchpress","exercise":"curl","equipment":"dumbbell","sequence":profile.last_sequence+1}).ok)
 host.barbell_mass=func(_station):return 20.0
 for exercise in Host.BENCH_BARBELL_EXERCISES:
  now+=100
  var start=host.act(1,{"op":"start","station":"gym/benchpress","exercise":exercise,"sequence":profile.last_sequence+1})
  assert(start.ok and host.active[1].exercise==exercise and host.active[1].weight==20.0)
  now+=100
  assert(host.act(1,{"op":"cancel","sequence":profile.last_sequence+1}).ok)
 print("PASS portable dumbbell movements use host-owned pair mass")
 quit()
