extends RefCounted
## Host-monotonic recovery: offline time does not grant unverified progress.
const EXERCISE_DATA_PATH := "res://assets/campus/gym/exercises.json"
const MUSCLE_GROUPS := ["biceps","triceps","forearms","front_deltoids","side_deltoids","rear_deltoids","chest","lats","trapezius","lower_back","abdominals","quadriceps","hamstrings","glutes","calves"]
static var definitions: Dictionary={}
static var allowed_muscles: Dictionary={}
static func exercise_data() -> Dictionary:
 if definitions.is_empty():
  var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(EXERCISE_DATA_PATH))
  if parsed is Dictionary and parsed.get("version",0)==1 and parsed.get("exercises") is Dictionary:definitions=parsed.exercises
 return definitions
static func known_muscles() -> Dictionary:
 if allowed_muscles.is_empty():
  for definition in exercise_data().values():
   for name in definition.muscles:allowed_muscles[name]=true
 return allowed_muscles
const RECOVERY_SECONDS := 600.0
const RECOVERY_DELAY_SECONDS := 15.0
const HISTORY_LIMIT := 24
const SET_OUTCOMES := ["voluntary","failure","cancelled","input_failure","interrupted"]
static func empty() -> Dictionary:return {"muscles":{}}
static func valid(state: Variant) -> bool:
 if not state is Dictionary or state.size()>2 or not state.get("muscles") is Dictionary:return false
 for key in state:
  if key not in ["muscles","history"]:return false
 var history: Variant=state.get("history",[])
 if not history is Array or history.size()>HISTORY_LIMIT:return false
 for entry in history:
  if not _valid_set(entry):return false
 var allowed:=known_muscles()
 if state.muscles.size()>allowed.size():return false
 for name in state.muscles:
  if name not in allowed:return false
  var m: Variant=state.muscles[name]
  if not m is Dictionary or m.size() not in [4,5]:return false
  for key in m:
   if key not in ["fatigue","strength","size","stimulus","delay"]:return false
  for key in ["fatigue","strength","stimulus","delay"] + (["size"] if m.has("size") else []):
   var value: Variant=m.get(key,null)
   if not (value is int or value is float) or not is_finite(float(value)) or value<0.0 or value>1.0:return false
 return true

static func _valid_set(entry: Variant) -> bool:
 if not entry is Dictionary or entry.size() not in [8,10] or not exercise_data().has(entry.get("exercise","")) or entry.get("outcome","") not in SET_OUTCOMES:return false
 if entry.size()==10:
  for key in ["fatigue_added","stimulus_added"]:
   var value: Variant=entry.get(key,null)
   if not (value is int or value is float) or not is_finite(float(value)) or value<0.0 or value>1.0:return false
 if not entry.get("muscles") is Dictionary or entry.muscles.is_empty() or entry.muscles.size()>32:return false
 var allowed:=known_muscles()
 for name in entry.muscles:
  var value: Variant=entry.muscles[name]
  if not allowed.has(name) or not (value is int or value is float) or not is_finite(float(value)) or value<0.0 or value>1.0:return false
 for key in ["weight_kg","body_kg","duration_seconds","relative_effort","reps"]:
  var value: Variant=entry.get(key,null)
  if not (value is int or value is float) or not is_finite(float(value)) or value<0.0:return false
 if float(entry.weight_kg)>10000.0 or float(entry.body_kg)>160.0 or float(entry.duration_seconds)>86400.0 or float(entry.relative_effort)>10.0:return false
 return float(entry.reps)<=500 and float(entry.reps)==floor(float(entry.reps))

static func record_set(state: Dictionary,active: Dictionary,outcome: String,now_ms: int) -> void:
 var exercise:=str(active.get("exercise",""))
 if not exercise_data().has(exercise) or outcome not in SET_OUTCOMES:return
 var weight:=maxf(0.0,float(active.get("weight",0.0)))
 var body:=clampf(float(active.get("body_mass",70.0)),35.0,160.0)
 var ratio:=effective_load(exercise,weight,body)/maxf(capacity(state,exercise),.001)
 var history: Array=state.get("history",[]).duplicate(true)
 var added:=set_change(state,exercise,active.get("initial_muscles",{}))
 history.append({"exercise":exercise,"weight_kg":weight,"body_kg":body,"reps":clampi(int(active.get("reps",0)),0,500),"duration_seconds":clampf(float(now_ms-int(active.get("started",now_ms)))/1000.0,0.0,86400.0),"relative_effort":clampf(ratio,0.0,10.0),"outcome":outcome,"muscles":exercise_data()[exercise].muscles.duplicate(true),"fatigue_added":added.fatigue,"stimulus_added":added.stimulus})
 while history.size()>HISTORY_LIMIT:history.pop_front()
 state.history=history
static func set_snapshot(state: Dictionary,exercise: String) -> Dictionary:
 var result:={}
 for name in exercise_data()[exercise].muscles:
  var muscle: Dictionary=state.get("muscles",{}).get(name,{})
  result[name]={"fatigue":float(muscle.get("fatigue",0.0)),"stimulus":float(muscle.get("stimulus",0.0))}
 return result
static func set_change(state: Dictionary,exercise: String,initial: Dictionary) -> Dictionary:
 var result:={"fatigue":0.0,"stimulus":0.0};var total:=0.0
 for name in exercise_data()[exercise].muscles:
  var weight: float=exercise_data()[exercise].muscles[name]
  var before: Dictionary=initial.get(name,{})
  var after: Dictionary=state.get("muscles",{}).get(name,{})
  for key in result:result[key]+=weight*maxf(0.0,float(after.get(key,0.0))-float(before.get(key,0.0)))
  total+=weight
 if total>0.0:
  for key in result:result[key]=clampf(float(result[key])/total,0.0,1.0)
 return result
static func advance(state: Dictionary,seconds: float) -> void:
 for muscle in state.muscles.values():
  # Legacy saves contain strength but no separate size; preserve their progress.
  if not muscle.has("size"):muscle.size=float(muscle.strength)
  var wait_seconds: float=float(muscle.delay)*RECOVERY_DELAY_SECONDS
  var recovery_seconds:=maxf(0.0,seconds-wait_seconds)
  muscle.delay=maxf(0.0,float(muscle.delay)-seconds/RECOVERY_DELAY_SECONDS)
  var portion:=clampf(recovery_seconds/RECOVERY_SECONDS,0.0,1.0)
  var before: float=muscle.fatigue
  muscle.fatigue=maxf(0.0,before-portion)
  var restored: float=minf(before,portion)
  if before>0.0:
   var adapted: float=float(muscle.stimulus)*restored/before
   muscle.stimulus=maxf(0.0,float(muscle.stimulus)-adapted)
   muscle.strength=minf(1.0,float(muscle.strength)+adapted*.012*(1.0-float(muscle.strength)))
   muscle.size=minf(1.0,float(muscle.size)+adapted*.008*(1.0-float(muscle.size)))
static func muscle_sizes(state: Dictionary) -> Dictionary:
 var result:={}
 for name in MUSCLE_GROUPS:
  var muscle: Dictionary=state.get("muscles",{}).get(name,{})
  result[name]=clampf(float(muscle.get("size",muscle.get("strength",0.0))),0.0,1.0)
 return result
static func overall_strength(state: Dictionary) -> float:
 var sizes:=muscle_sizes(state);var total:=0.0
 for value in sizes.values():total+=float(value)
 return total/float(MUSCLE_GROUPS.size())
static func capacity(state: Dictionary,exercise: String) -> float:
 var weighted:=0.0;var total:=0.0
 for name in exercise_data()[exercise].muscles:
  var weight: float=exercise_data()[exercise].muscles[name]
  var muscle: Dictionary=state.muscles.get(name,{"fatigue":0.0,"strength":0.0,"stimulus":0.0,"delay":0.0})
  weighted+=weight*(1.0+float(muscle.strength)*.75)*(1.0-float(muscle.fatigue))
  total+=weight
 return float(exercise_data()[exercise].capacity_kg)*weighted/total
static func body_mass(profile: Dictionary) -> float:
 var raw: Variant=profile.get("avatar_cosmetics",{}).get("body",{})
 var body: Dictionary=preload("res://scripts/avatar_cosmetics/core/avatar_core.gd").sanitize_body(raw if raw is Dictionary else {})
 # Approximate mass from the saved body dimensions; 70 kg is the existing baseline.
 var build_factor: float={"slim":.92,"average":1.0,"heavy":1.12,"muscular":1.06}.get(body.build,1.0)
 var growth: float=overall_strength(profile.get("facilities",{}).get("gym",empty()))
 return clampf(70.0*pow(float(body.height),1.5)*pow(float(body.width),1.2)*build_factor*(1.0+.12*growth),35.0,160.0)
static func effective_load(exercise: String,kg: float,body_kg: float=70.0) -> float:
 return float(exercise_data()[exercise].bodyweight_load_kg)*clampf(body_kg,35.0,160.0)/70.0+maxf(0.0,kg)
static func rep(state: Dictionary,exercise: String,kg: float,body_kg: float=70.0) -> Dictionary:
 var available:=capacity(state,exercise)
 var required:=effective_load(exercise,kg,body_kg)
 if required>available:
  # A near-miss is a genuine effort, but an impossibly heavy load cannot be farmed.
  var effort:=clampf(2.0-required/maxf(available,.001),0.0,1.0)
  if effort>0.0:
   for name in exercise_data()[exercise].muscles:
    if not state.muscles.has(name):state.muscles[name]={"fatigue":0.0,"strength":0.0,"size":0.0,"stimulus":0.0,"delay":0.0}
    var muscle: Dictionary=state.muscles[name]
    var impact: float=exercise_data()[exercise].muscles[name]
    muscle.delay=1.0
    muscle.fatigue=clampf(float(muscle.fatigue)+.025*impact*effort,0.0,1.0)
    muscle.stimulus=clampf(float(muscle.stimulus)+.003*impact*effort*(1.0-float(muscle.stimulus)),0.0,1.0)
  return {"failure":true,"capacity":available,"load":required}
 var relative:=clampf(required/maxf(available,.001),0.0,1.0)
 for name in exercise_data()[exercise].muscles:
  if not state.muscles.has(name):state.muscles[name]={"fatigue":0.0,"strength":0.0,"size":0.0,"stimulus":0.0,"delay":0.0}
  var muscle: Dictionary=state.muscles[name]
  var impact: float=exercise_data()[exercise].muscles[name]
  muscle.delay=1.0
  muscle.fatigue=clampf(float(muscle.fatigue)+(.012+.038*relative)*impact,0.0,1.0)
  muscle.stimulus=clampf(float(muscle.stimulus)+(.001+.012*relative*relative)*impact*(1.0-float(muscle.stimulus)),0.0,1.0)
 return {"failure":false,"capacity":available,"load":required}

static func effort(state: Dictionary,exercise: String,ratio: float,travel: float) -> void:
 var effort_scale:=clampf((2.0-ratio)/.65,0.0,1.0)
 if effort_scale<=0.0:return
 var intensity:=clampf(ratio,0.0,1.0)
 for name in exercise_data()[exercise].muscles:
  if not state.muscles.has(name):state.muscles[name]={"fatigue":0.0,"strength":0.0,"size":0.0,"stimulus":0.0,"delay":0.0}
  var muscle: Dictionary=state.muscles[name]
  var dose: float=exercise_data()[exercise].muscles[name]*effort_scale*(.025+travel)
  muscle.delay=1.0
  muscle.fatigue=clampf(float(muscle.fatigue)+dose*(.010+.035*intensity),0.0,1.0)
  muscle.stimulus=clampf(float(muscle.stimulus)+dose*(.0007+.009*intensity*intensity)*(1.0-float(muscle.stimulus)),0.0,1.0)

static func drain_lift(progress: float,rate: float,seconds: float) -> float:
 # Integrate dp/dt = -rate * (1 + 5*p²), independent of tick rate.
 const CURVE_ROOT := 2.2360679775
 return maxf(0.0,tan(maxf(0.0,atan(progress*CURVE_ROOT)-rate*CURVE_ROOT*seconds))/CURVE_ROOT)

static func lift_parameters(available: float, required: float) -> Vector3:
 var ratio := required / maxf(available, .001)
 var strain := clampf(ratio, 0.0, 1.0)
 var gain := lerpf(.18, .072, strain)
 var decay := lerpf(.055, .21, strain)
 var overload := maxf(0.0, ratio - 1.0)
 gain /= 1.0 + overload * 3.8
 decay += overload * .33
 return Vector3(gain, decay, ratio)

static func movement_ms(state: Dictionary,exercise: String,kg: float,base_ms: int,body_kg: float=70.0) -> int:
 var ratio:=effective_load(exercise,kg,body_kg)/maxf(capacity(state,exercise),.001)
 return int(round(base_ms*clampf(1.0+maxf(0.0,ratio-.65)*1.3,1.0,1.7)))
