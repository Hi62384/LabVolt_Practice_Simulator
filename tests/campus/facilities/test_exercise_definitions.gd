extends SceneTree
const Gym=preload("res://scripts/campus/facilities/gym_progress.gd")
func _initialize():
 var data: Dictionary=Gym.exercise_data()
 assert(data.size()>=30)
 for id in data:
  var row: Dictionary=data[id]
  assert(float(row.capacity_kg)>0 and float(row.bodyweight_load_kg)>=0 and not row.muscles.is_empty())
  var state=Gym.empty()
  var result=Gym.rep(state,id,0.0)
  assert(not result.failure)
  assert(state.muscles.size()==row.muscles.size())
  for muscle in state.muscles:assert(row.muscles.has(muscle) and state.muscles[muscle].fatigue>0)
  assert(Gym.valid(state))
 print("PASS exercise definitions and isolated muscle mappings: ",data.size())
 quit()
