extends "res://scripts/campus/academics/classroom_events/practice_round.gd"
## A computed function change, with its graph released after predictions close.
var correct_option := -1
var result_value := 0
var target_x := 0
var worked_text := ""
var diagram: Dictionary = {}

func prepare(host: bool,id: String,course: String,week: int,difficulty: int,seed_value: int,ends_at: float,identities: Array,_recent_indices: Array=[]) -> bool:
 if not host or course not in ["MTH147","MTH255"] or id.is_empty() or week<1 or difficulty not in range(5) or identities.is_empty() or identities.size()>MAX_STUDENTS or not is_finite(ends_at):return false
 for identity in identities:
  if not identity is String or identity.is_empty() or participants.has(identity):participants.clear();return false
  participants[identity]=true
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 var slope:=rng.randi_range(2,4)
 var offset:=rng.randi_range(-2,2)
 var x:=rng.randi_range(2,4)
 target_x=x
 var changed_slope:=slope+1
 result_value=changed_slope*x+offset
 worked_text="y = %d × %d %s %d = %d"%[changed_slope,x,"+" if offset>=0 else "-",absi(offset),result_value]
 var before: Array=[]
 var after: Array=[]
 for sample_x in range(-4,5):
  before.append({"x":sample_x,"y":slope*sample_x+offset})
  after.append({"x":sample_x,"y":changed_slope*sample_x+offset})
 diagram={"kind":"graph","curves":[{"kind":"samples","label":"original","points":before},{"kind":"samples","label":"changed","points":after}],"domain":[-4,4],"range":[-20,24],"x_label":"x","y_label":"y"}
 var candidates: Array[int]=[result_value,slope*x+offset,result_value+x,result_value-x]
 for i in range(candidates.size()-1,0,-1):
  var j:=rng.randi_range(0,i)
  var value:=candidates[i];candidates[i]=candidates[j];candidates[j]=value
 correct_option=candidates.find(result_value)
 var choices: Array[String]=[]
 for candidate in candidates:choices.append(str(candidate))
 var input_options: Array=[]
 for i in choices.size():input_options.append({"id":str(i),"label":choices[i]})
 public_question={"prompt":"Teacher demonstration: y = %dx %s %d. The slope changes to %d while the intercept stays fixed. Predict y when x = %d before the new graph is shown."%[slope,"+" if offset>=0 else "-",absi(offset),changed_slope,x],"summary":"Slope %d → %d · intercept %d · x = %d"%[slope,changed_slope,offset,x],"options":choices,"input":{"kind":"choice","options":input_options}}
 private_assignment={"questions":[{"answer":choices[correct_option]}]}
 present=participants.duplicate();event_id=id;deadline=ends_at;started_at=ends_at-30.0;mode="demonstration";question_index=0
 return true

func submit(host: bool,identity: String,id: String,response: Variant,now: float) -> String:
 if not host or closed or not is_finite(now) or now>=deadline:return "closed"
 if id!=event_id or not present.has(identity):return "not_participating"
 if submissions.has(identity):return "already_submitted"
 if not response is String or not response.is_valid_int():return "invalid"
 var selected:=int(response)
 if selected<0 or selected>=public_question.options.size():return "invalid"
 submissions[identity]={"correct":selected==correct_option,"reason":"The changed function evaluates to %d at the given x."%result_value}
 submitted_at[identity]=now
 return "accepted"

func reveal() -> Dictionary:
 if not closed:return {}
 return {"answer":public_question.options[correct_option],"diagram":diagram.duplicate(true),"explanation":worked_text}
