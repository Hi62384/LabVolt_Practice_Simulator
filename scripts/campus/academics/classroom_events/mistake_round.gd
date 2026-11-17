extends "res://scripts/campus/academics/classroom_events/demonstration_round.gd"
## A deliberately incorrect worked current, checked against the solver result.
func prepare(host: bool,id: String,course: String,week: int,difficulty: int,seed_value: int,ends_at: float,identities: Array,recent_indices: Array=[]) -> bool:
 if not super.prepare(host,id,course,week,difficulty,seed_value,ends_at,identities,recent_indices):return false
 var wrong: String=""
 for i in public_question.options.size():
  if i!=correct_option:
   wrong=str(public_question.options[i]);break
 var source: Dictionary=private_assignment.demonstration
 public_question.prompt="Find the mistake: a %.0f V source is connected across a %.0f Ω resistor. The teacher writes ‘current = %s’. Which value corrects the worked example?"%[float(source.volts),float(source.changed_ohms),wrong]
 mode="mistake"
 return true
