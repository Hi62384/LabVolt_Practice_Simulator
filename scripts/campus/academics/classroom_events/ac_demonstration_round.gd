extends "res://scripts/campus/academics/classroom_events/demonstration_round.gd"
## A frequency-change prediction solved by the existing RMS AC network model.
const Network=preload("res://scripts/ac_network.gd")
const Catalog=preload("res://scripts/equipment_catalog.gd")
var before_hz:=50.0
var after_hz:=60.0

func prepare(host: bool,id: String,course: String,week: int,difficulty: int,seed_value: int,ends_at: float,identities: Array,_recent_indices: Array=[]) -> bool:
 if not host or course!="ELM253" or week not in [3,4,5] or id.is_empty() or difficulty not in range(5) or identities.is_empty() or identities.size()>MAX_STUDENTS or not is_finite(ends_at):return false
 for identity in identities:
  if not identity is String or identity.is_empty() or participants.has(identity):participants.clear();return false
  participants[identity]=true
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 var resistance: float=float(Catalog.LOADS.R.values[rng.randi_range(0,2)])
 var inductance: float=float(Catalog.LOADS.L.values[rng.randi_range(0,2)])
 var voltage:=24.0
 topology="series" if week==3 else ("parallel" if week==4 else "mixed")
 var before: Dictionary=_solve(voltage,resistance,inductance,before_hz)
 var after: Dictionary=_solve(voltage,resistance,inductance,after_hz)
 if before.get("fault","")!="" or after.get("fault","")!="":participants.clear();return false
 initial_ma=(before.get("currents",{}).get("source",Vector2(NAN,NAN)) as Vector2).length()*1000.0
 changed_ma=(after.get("currents",{}).get("source",Vector2(NAN,NAN)) as Vector2).length()*1000.0
 if not is_finite(initial_ma) or not is_finite(changed_ma):participants.clear();return false
 var candidates: Array[float]=[changed_ma]
 for candidate in [initial_ma,changed_ma*.5,changed_ma*1.5,changed_ma*2.0,changed_ma+10.0]:
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
 var layout: String="R and L in series" if topology=="series" else ("R and L in parallel" if topology=="parallel" else "R in series with a parallel R/L branch")
 public_question={"prompt":"Teacher demonstration: a %.0f V RMS source drives %s (R = %.0f Ω, L = %.1f H). Frequency changes from %.0f to %.0f Hz. Predict the new source RMS current before the AC network is solved."%[voltage,layout,resistance,inductance,before_hz,after_hz],"summary":"%s · %.0f → %.0f Hz"%[layout,before_hz,after_hz],"options":choices}
 private_assignment={"questions":[{"answer":choices[correct_option]}],"demonstration":{"voltage_rms":voltage,"resistance_ohms":resistance,"inductance_henry":inductance,"before_hz":before_hz,"after_hz":after_hz,"topology":topology}}
 present=participants.duplicate();event_id=id;deadline=ends_at;started_at=ends_at-30.0;mode="demonstration";question_index=0
 return true

func _solve(voltage: float,resistance: float,inductance: float,frequency: float) -> Dictionary:
 var branches: Array=[{"id":"source","type":"voltage","a":"A","b":"0","value":Vector2(voltage,0)}]
 var reactance:=TAU*frequency*inductance
 if topology=="series":
  branches.append_array([{"id":"R0","type":"impedance","a":"A","b":"j","value":Vector2(resistance,0)},{"id":"L0","type":"impedance","a":"j","b":"0","value":Vector2(0,reactance)}])
 elif topology=="parallel":
  branches.append_array([{"id":"R0","type":"impedance","a":"A","b":"0","value":Vector2(resistance,0)},{"id":"L0","type":"impedance","a":"A","b":"0","value":Vector2(0,reactance)}])
 else:
  branches.append_array([{"id":"R0","type":"impedance","a":"A","b":"j","value":Vector2(resistance,0)},{"id":"R1","type":"impedance","a":"j","b":"0","value":Vector2(resistance,0)},{"id":"L0","type":"impedance","a":"j","b":"0","value":Vector2(0,reactance)}])
 return Network.new().solve(["0","A","j"] if topology!="parallel" else ["0","A"],branches)

func reveal() -> Dictionary:
 if not closed:return {}
 return {"answer":public_question.options[correct_option],"initial_ma":initial_ma,"changed_ma":changed_ma,"source":"AC network solver"}
