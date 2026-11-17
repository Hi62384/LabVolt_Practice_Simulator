extends "res://scripts/campus/academics/classroom_events/demonstration_round.gd"
## Three host-checked steps of one circuit problem, passed between enrolled students.
var step_index:=0
var step_answers: Array=[]
var turn_order: Array=[]

func prepare(host: bool,id: String,course: String,week: int,difficulty: int,seed_value: int,ends_at: float,identities: Array,recent_indices: Array=[]) -> bool:
 if not super.prepare(host,id,course,week,difficulty,seed_value,ends_at,identities,recent_indices):return false
 turn_order=participants.keys();turn_order.sort()
 public_question={"prompt":"Pass the problem: use the source voltage and both resistor values to work toward the changed current. The host checks each step before passing it on.","options":[]}
 mode="pass"
 return true

func step_prompt() -> String:
 var circuit: Dictionary=private_assignment.demonstration
 match step_index:
  0:return "Step 1: What is the source voltage in volts?"
  1:return "Step 2: What is the changed resistance in ohms?"
  2:return "Step 3: What is the changed current in mA? Round to 2 decimals."
 return "The class has completed the problem."

func current_student() -> String:
 if step_index>=3 or turn_order.is_empty():return ""
 for offset in turn_order.size():
  var identity: String=str(turn_order[(step_index+offset)%turn_order.size()])
  if present.has(identity):return identity
 return ""

func snapshot(identity: String,now: float) -> Dictionary:
 var data: Dictionary=super.snapshot(identity,now)
 data.question=public_question.duplicate(true)
 data.question.prompt="%.0f V source · %.0f Ω initially · %.0f Ω after change.\n%s"%[float(private_assignment.demonstration.volts),float(private_assignment.demonstration.initial_ohms),float(private_assignment.demonstration.changed_ohms),step_prompt()]
 data.pass_step=step_index
 data.pass_total=3
 data.pass_turn=not identity.is_empty() and identity==current_student()
 data.pass_completed=step_answers.size()
 data.can_submit=not closed and now<deadline and data.pass_turn and step_index<3
 data.submitted=step_index>=3
 return data

func submit(host: bool,identity: String,id: String,response: Variant,now: float) -> String:
 if not host or closed or not is_finite(now) or now>=deadline:return "closed"
 if id!=event_id or not present.has(identity):return "not_participating"
 if step_index>=3:return "already_submitted"
 if identity!=current_student():return "not_your_turn"
 if not response is String or response.length()>40 or not response.is_valid_float():return "invalid"
 var value:=float(response)
 if not is_finite(value):return "invalid"
 var circuit: Dictionary=private_assignment.demonstration
 var expected: float=[float(circuit.volts),float(circuit.changed_ohms),changed_ma][step_index]
 var correct:=absf(value-expected)<=maxf(.011,expected*.0002)
 step_answers.append({"step":step_index+1,"student":identity,"correct":correct,"value":value})
 submissions[identity]={"correct":correct,"reason":"Step %d: expected %.2f."%[step_index+1,expected]}
 submitted_at[identity]=now
 step_index+=1
 return "accepted"

func reveal() -> Dictionary:
 if not closed:return {}
 var public_steps: Array=[]
 for step in step_answers:public_steps.append({"step":step.step,"correct":step.correct,"value":step.value})
 return {"answer":"%.2f mA"%changed_ma,"steps":public_steps,"source":"circuit solver"}

func result(identity: String) -> Dictionary:
 if not closed or not participants.has(identity):return {}
 var attempted:=0
 var correct:=0
 for step in step_answers:
  if step.student!=identity:continue
  attempted+=1
  if step.correct:correct+=1
 if attempted==0:return {}
 return {"correct":correct==attempted,"points":correct*25,"reason":"%d of %d steps correct. The verified final current is %.2f mA."%[correct,attempted,changed_ma]}
