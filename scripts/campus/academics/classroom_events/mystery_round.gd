extends "res://scripts/campus/academics/classroom_events/mistake_round.gd"
## A verified incorrect solution with timed public clues.
func prepare(host: bool,id: String,course: String,week: int,difficulty: int,seed_value: int,ends_at: float,identities: Array,recent_indices: Array=[]) -> bool:
 if not super.prepare(host,id,course,week,difficulty,seed_value,ends_at,identities,recent_indices):return false
 public_question.prompt=public_question.prompt.replace("Find the mistake:","Classroom mystery:")
 mode="mystery"
 return true

func snapshot(identity: String,now: float) -> Dictionary:
 var data: Dictionary=super.snapshot(identity,now)
 var elapsed:=now-started_at
 var clues: Array[String]=[]
 if elapsed>=10.0:clues.append("Clue 1: for one resistor, use I = V / R.")
 if elapsed>=20.0:clues.append("Clue 2: convert amperes to milliamperes before comparing choices.")
 data.clues=clues
 return data
