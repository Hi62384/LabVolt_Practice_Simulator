extends "res://scripts/campus/academics/classroom_events/practice_round.gd"
## A host-solved circuit change. Students predict before the computed result is released.
const Solver=preload("res://scripts/electronics_solver.gd")
var initial_ma:=0.0
var changed_ma:=0.0
var correct_option:=-1
var topology:=""

func prepare(host: bool,id: String,course: String,week: int,difficulty: int,seed_value: int,ends_at: float,identities: Array,_recent_indices: Array=[]) -> bool:
 if not host or course!="ETY155" or week not in range(1,7) or id.is_empty() or difficulty not in range(5) or identities.is_empty() or identities.size()>MAX_STUDENTS or not is_finite(ends_at):return false
 var ordered:=identities.duplicate();ordered.sort()
 for identity in ordered:
  if not identity is String or identity.is_empty() or participants.has(identity):participants.clear();return false
  participants[identity]=true
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 var volts:=float([6,9,12][rng.randi_range(0,2)])
 var first:=float([100,150,220][rng.randi_range(0,2)])
 var second:=first*2.0
 var parts: Array=[{"id":"source","kind":"V","a":"p","b":"n","value":volts}]
 var changed_id:="resistor"
 var prompt:=""
 if week==4:
  topology="series"
  changed_id="r2"
  parts.append_array([{"id":"r1","kind":"R","a":"p","b":"m","value":first},{"id":"r2","kind":"R","a":"m","b":"n","value":first}])
  prompt="Teacher demonstration: a %.0f V source feeds two %.0f Ω resistors in series. The second changes to %.0f Ω. Predict the new source current."%[volts,first,second]
 elif week==5:
  topology="parallel"
  changed_id="r2"
  parts.append_array([{"id":"r1","kind":"R","a":"p","b":"n","value":first},{"id":"r2","kind":"R","a":"p","b":"n","value":first}])
  prompt="Teacher demonstration: a %.0f V source feeds two %.0f Ω branches in parallel. The second changes to %.0f Ω. Predict the new total source current."%[volts,first,second]
 elif week==6:
  topology="mixed"
  changed_id="r3"
  parts.append_array([{"id":"r1","kind":"R","a":"p","b":"m","value":first},{"id":"r2","kind":"R","a":"m","b":"n","value":first},{"id":"r3","kind":"R","a":"m","b":"n","value":first}])
  prompt="Teacher demonstration: a %.0f V source feeds %.0f Ω in series with two %.0f Ω parallel branches. One branch changes to %.0f Ω. Predict the new total source current."%[volts,first,first,second]
 else:
  topology="single"
  parts.append({"id":"resistor","kind":"R","a":"p","b":"n","value":first})
  prompt="Teacher demonstration: a %.0f V DC source drives one %.0f Ω resistor. The teacher changes it to %.0f Ω. Predict the new current before the circuit is solved."%[volts,first,second]
 var before: Dictionary=Solver.new().solve(parts)
 for part in parts:
  if str(part.id)==changed_id:part.value=second
 var after: Dictionary=Solver.new().solve(parts)
 if not before.get("ok",false) or not after.get("ok",false):participants.clear();return false
 initial_ma=absf(float(before.i.get("source",NAN)))*1000.0
 changed_ma=absf(float(after.i.get("source",NAN)))*1000.0
 if not is_finite(initial_ma) or not is_finite(changed_ma):participants.clear();return false
 var candidates: Array[float]=[changed_ma]
 for candidate in [initial_ma,changed_ma*.5,changed_ma*1.5,changed_ma*2.0,changed_ma*3.0,changed_ma+5.0]:
  var label:="%.2f mA"%candidate
  var duplicate:=false
  for existing in candidates:
   if "%.2f mA"%existing==label:duplicate=true;break
  if not duplicate:candidates.append(candidate)
  if candidates.size()==4:break
 if candidates.size()!=4:participants.clear();return false
 for i in range(candidates.size()-1,0,-1):
  var j:=rng.randi_range(0,i)
  var value:=candidates[i];candidates[i]=candidates[j];candidates[j]=value
 correct_option=candidates.find(changed_ma)
 var choices: Array[String]=[]
 for candidate in candidates:choices.append("%.2f mA"%candidate)
 public_question={"prompt":prompt,"options":choices}
 private_assignment={"questions":[{"answer":choices[correct_option]}],"demonstration":{"volts":volts,"initial_ohms":first,"changed_ohms":second,"topology":topology}}
 present=participants.duplicate();event_id=id;deadline=ends_at;started_at=ends_at-30.0;mode="demonstration";question_index=0
 return true

func submit(host: bool,identity: String,id: String,response: Variant,now: float) -> String:
 if not host or closed or not is_finite(now) or now>=deadline:return "closed"
 if id!=event_id or not present.has(identity):return "not_participating"
 if submissions.has(identity):return "already_submitted"
 if not response is String or not response.is_valid_int():return "invalid"
 var selected:=int(response)
 if selected<0 or selected>=public_question.options.size():return "invalid"
 submissions[identity]={"correct":selected==correct_option,"reason":"The host circuit solver measured %.2f mA after the change."%changed_ma}
 submitted_at[identity]=now
 return "accepted"

func reveal() -> Dictionary:
 if not closed:return {}
 return {"answer":public_question.options[correct_option],"initial_ma":initial_ma,"changed_ma":changed_ma,"source":"circuit solver"}
