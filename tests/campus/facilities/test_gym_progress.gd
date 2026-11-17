extends SceneTree
const Gym=preload("res://scripts/campus/facilities/gym_progress.gd")
func _initialize():
 var state=Gym.empty();assert(Gym.valid(state))
 var strength:=Gym.capacity(state,"curl")
 var reps:=0
 while reps<100:
  var result=Gym.rep(state,"curl",20.0)
  if result.failure:break
  reps+=1
 assert(reps>0 and reps<100)
 assert(state.muscles.has("biceps") and not state.muscles.has("chest"))
 assert(state.muscles.biceps.strength==0.0)
 assert(state.muscles.biceps.size==0.0 and Gym.overall_strength(state)==0.0)
 assert(Gym.capacity(state,"curl")<strength)
 var persisted=state.duplicate(true);Gym.advance(persisted,0.0)
 assert(persisted==state)
 Gym.advance(state,23400.0)
 assert(state.muscles.biceps.strength>0.0 and state.muscles.biceps.size>0.0 and state.muscles.biceps.fatigue==0.0)
 assert(is_equal_approx(Gym.overall_strength(state),(state.muscles.biceps.size+state.muscles.forearms.size)/float(Gym.MUSCLE_GROUPS.size())))
 assert(Gym.muscle_sizes(state).chest==0.0)
 assert(Gym.valid(state))
 var legacy={"muscles":{"biceps":{"fatigue":0.2,"strength":0.3,"stimulus":0.1,"delay":0.0}}}
 assert(Gym.valid(legacy) and is_equal_approx(Gym.muscle_sizes(legacy).biceps,.3))
 Gym.advance(legacy,0.0)
 assert(Gym.valid(legacy) and is_equal_approx(legacy.muscles.biceps.size,.3))
 var near_failure=Gym.empty()
 var failed=Gym.rep(near_failure,"curl",Gym.capacity(near_failure,"curl")*1.01)
 assert(failed.failure and near_failure.muscles.biceps.fatigue>0.0 and near_failure.muscles.biceps.stimulus>0.0)
 assert(near_failure.muscles.biceps.strength==0.0 and near_failure.muscles.biceps.size==0.0)
 var impossible=Gym.empty()
 failed=Gym.rep(impossible,"curl",Gym.capacity(impossible,"curl")*3.0)
 assert(failed.failure and impossible.muscles.is_empty())
 var light=Gym.empty();var count:=0
 while count<500:
  if Gym.rep(light,"squat",2.26796185).failure:break
  count+=1
 assert(count<500)
 print("PASS gym fatigue, failure, recovery and muscle-specific adaptation")
 quit()
