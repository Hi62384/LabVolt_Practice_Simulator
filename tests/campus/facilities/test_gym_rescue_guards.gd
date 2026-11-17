extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var profiles: Dictionary={1:Host.empty_profile(),2:Host.empty_profile()}
var positions: Dictionary={1:Vector3.ZERO,2:Vector3.ZERO,3:Vector3.ZERO}
var grounded: Dictionary={1:true,2:true,3:true}
var allow_save:=true
var now:=1000

func _initialize() -> void:
 var host=Host.new()
 host.authority=func():return true
 host.clock=func():return now
 host.context=func(peer):return {"identity":"student_%d"%(1 if peer==3 else peer),"position":positions[peer],"room_id":"gym","allowed":true,"grounded":grounded[peer]}
 host.load_profile=func(identity):return profiles[int(identity.trim_prefix("student_"))].duplicate(true)
 host.commit_profile=func(identity,_dollars,value):
  if not allow_save:return false
  profiles[int(identity.trim_prefix("student_"))]=value.duplicate(true)
  return true
 host.anchors={"gym/benchpress":{"kind":"benchpress","room_id":"gym","position":Vector3.ZERO}}
 var started: Dictionary=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":1})
 # A fixed rack mass must be supplied before this start is valid.
 assert(not started.ok)
 host.barbell_mass=func(_station):return 30.0
 now+=100
 started=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":1})
 assert(started.ok)
 allow_save=false;now+=100
 var cancelled: Dictionary=host.act(1,{"op":"cancel","sequence":2})
 assert(not cancelled.ok and host.active.has(1) and profiles[1].last_sequence==1)
 allow_save=true;now+=100
 cancelled=host.act(1,{"op":"cancel","sequence":2})
 assert(cancelled.ok and not host.active.has(1) and profiles[1].gym.history.size()==1)
 assert(profiles[1].gym.history[0].outcome=="cancelled")
 host.barbell_mass=func(_station):return 1000.0
 now+=100
 var prepared: Dictionary=host.act(2,{"op":"spot","station":"gym/benchpress","sequence":1})
 assert(prepared.ok)
 now+=100
 started=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":3})
 assert(started.ok)
 for _phase in 2:
  now+=int(host.active[1].half_ms)
  var beat: Dictionary=host.act(1,{"op":"beat","sequence":int(profiles[1].last_sequence)+1})
  assert(beat.ok)
 assert(host.active[1].type=="trapped" and host.spotting_station(2)=="gym/benchpress")
 host.clear_activity(1)
 host.clear_spot(2)
 # Build an active trapped state to validate rescue position and participant state.
 host.active[1]={"type":"trapped","station":"gym/benchpress","room_id":"gym","position":Vector3.ZERO,"exercise":"benchpress","weight":50.0,"progress":0.0,"started":now,"trapped_at":now}
 positions[2]=Vector3(2.6,0,0)
 now+=100
 var rescue: Dictionary=host.act(2,{"op":"assist","target":1,"sequence":2})
 assert(not rescue.ok and host.active[1].progress==0.0)
 positions[2]=Vector3.ZERO;grounded[2]=false
 now+=100
 rescue=host.act(2,{"op":"assist","target":1,"sequence":2})
 assert(not rescue.ok and host.active[1].progress==0.0)
 grounded[2]=true;now+=100
 rescue=host.act(2,{"op":"assist","target":1,"sequence":2})
 assert(rescue.ok and host.active[1].progress>0.0)
 var prior: float=float(host.active[1].progress)
 now+=100
 rescue=host.act(2,{"op":"assist","target":1,"sequence":2})
 assert(not rescue.ok and host.active[1].progress==prior)
 host.clear_activity(1)
 var gym=preload("res://scripts/campus/facilities/gym_progress.gd")
 host.active[1]={"type":"exercise","identity":"student_1","station":"gym/pushup","room_id":"gym","position":Vector3.ZERO,"exercise":"pushup","weight":0.0,"body_mass":70.0,"started":now,"reps":1,"initial_muscles":gym.set_snapshot(profiles[1].gym,"pushup")}
 var before_history: int=profiles[1].gym.history.size()
 allow_save=false
 host.clear_activity(1,"interrupted")
 host.active[3]={"type":"exercise","identity":"student_1","station":"gym/pushup","room_id":"gym","position":Vector3.ZERO,"exercise":"pushup","weight":0.0,"body_mass":70.0,"started":now+1,"reps":2,"initial_muscles":gym.set_snapshot(profiles[1].gym,"pushup")}
 host.clear_activity(3,"input_failure")
 assert(not host.active.has(1) and host.pending_sets["student_1"].size()==2 and profiles[1].gym.history.size()==before_history)
 assert(host.private_state(3).pending_workouts==2)
 now+=100
 var pending: Dictionary=host.act(3,{"op":"emote","emote":"wave","sequence":int(profiles[1].last_sequence)+1})
 assert(not pending.ok and host.pending_sets.has("student_1"))
 allow_save=true;now+=100
 pending=host.act(3,{"op":"emote","emote":"wave","sequence":int(profiles[1].last_sequence)+1})
 assert(not pending.ok and not host.pending_sets.has("student_1"))
 assert(profiles[1].gym.history.size()==before_history+2)
 assert(profiles[1].gym.history[before_history].outcome=="interrupted")
 assert(profiles[1].gym.history.back().outcome=="input_failure")
 now+=100
 pending=host.act(3,{"op":"emote","emote":"wave","sequence":int(profiles[1].last_sequence)+1})
 assert(pending.ok and profiles[1].gym.history.size()==before_history+2)
 print("GYM_RESCUE_GUARDS PASS")
 quit(0)
