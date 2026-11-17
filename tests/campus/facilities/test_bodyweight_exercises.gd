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
 host.anchors={"mat":{"kind":"pushup","room_id":"gym","position":Vector3.ZERO},"bar":{"kind":"pullup","room_id":"gym","position":Vector3.ZERO}}
 for row in [["mat","pushup"],["mat","crunch"],["mat","leg_raise"],["mat","pike_pushup"],["bar","pullup"],["bar","hanging_leg_raise"],["bar","dip"]]:
  var seq: int=profile.last_sequence+1
  now+=100
  var result=host.act(1,{"op":"start","station":row[0],"exercise":row[1],"weight":0,"sequence":seq})
  if not result.ok or host.active[1].exercise!=row[1]:push_error("start %s: %s" % [row[1],result]);quit(1);return
  for i in 2:
   now+=int(host.active[1].half_ms);seq+=1
   result=host.act(1,{"op":"beat","sequence":seq})
   if not result.ok or result.muscular_failure:push_error("beat %s: %s" % [row[1],result]);quit(1);return
  if profile.gym.muscles.is_empty():push_error("missing trained muscles");quit(1);return
  now+=100;seq+=1
  result=host.act(1,{"op":"finish","sequence":seq})
  if not result.ok:push_error("finish %s: %s" % [row[1],result]);quit(1);return
 now+=100
 if host.act(1,{"op":"start","station":"mat","exercise":"dip","weight":0,"sequence":profile.last_sequence+1}).ok:push_error("wrong station accepted");quit(1);return
 host.player_body_mass=func(_peer):return 100.0
 host.worn_belt_mass=func(_peer):return 5.0
 now+=100
 var weighted=host.act(1,{"op":"start","station":"bar","exercise":"pullup","weight":0,"sequence":profile.last_sequence+1})
 if not weighted.ok or not is_equal_approx(host.active[1].body_mass,100.0) or not is_equal_approx(host.active[1].weight,5.0):
  push_error("Host did not capture body and belt mass");quit(1);return
 for i in 2:
  now+=int(host.active[1].half_ms)
  weighted=host.act(1,{"op":"beat","sequence":profile.last_sequence+1})
  if not weighted.ok:
   push_error("Weighted pull-up action failed");quit(1);return
 if not weighted.muscular_failure:
  push_error("Heavy body and belt did not affect failure");quit(1);return
 print("PASS seven bodyweight movements and station validation")
 quit()
