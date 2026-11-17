extends "res://scripts/campus/academics/classroom_events/practice_round.gd"
## Prediction from a live, host-owned AC station. Existing equipment actions make the change.
var bench: int=-1
var channel: int=-1
var first_voltage:=0.0
var final_voltage:=0.0
var initial_revision: int=-1
var observed_revision: int=-1
var fault: String=""
var measurement_valid:=false

func prepare_live(host: bool,id: String,lab: RefCounted,station: int,ends_at: float,identities: Array) -> bool:
 if not host or lab==null or not private_assignment.is_empty() or id.is_empty() or station<0 or not is_finite(ends_at) or identities.is_empty() or identities.size()>MAX_STUDENTS:return false
 if not bool(lab.powered) or not str(lab.readings.get("fault","")).is_empty():return false
 var readings: Variant=lab.readings.get("voltmeters",[])
 if not readings is Array or readings.is_empty():return false
 for i in readings.size():
  var value:=float(readings[i])
  if is_finite(value) and value>0.01 and (channel<0 or value>first_voltage):channel=i;first_voltage=value
 if channel<0:return false
 for identity in identities:
  if not identity is String or identity.is_empty() or participants.has(identity):participants.clear();return false
  participants[identity]=true
 bench=station;initial_revision=int(lab.revision);observed_revision=initial_revision;event_id=id;deadline=ends_at;started_at=ends_at-30.0;present=participants.duplicate();mode="physical"
 public_question={"prompt":"AC station %d · voltmeter %d reads %.2f V RMS. Adjust the connected circuit using the normal equipment controls. Predict whether that reading will increase, decrease, or stay about the same. The host will measure the live station after the change."%[bench+1,channel+1,first_voltage],"options":["Increase","Decrease","Stay about the same"]}
 private_assignment={"physical":true}
 return true

func observe_live(host: bool,lab: RefCounted) -> bool:
 if not host or closed or lab==null or int(lab.revision)<=observed_revision:return false
 observed_revision=int(lab.revision)
 fault=str(lab.readings.get("fault",""))
 if not fault.is_empty() or not bool(lab.powered):
  measurement_valid=false
  return false
 var readings: Variant=lab.readings.get("voltmeters",[])
 if not readings is Array or channel<0 or channel>=readings.size():
  measurement_valid=false
  return false
 var value:=float(readings[channel])
 if not is_finite(value):
  measurement_valid=false
  return false
 final_voltage=value
 measurement_valid=true
 return true

func snapshot(identity: String,now: float) -> Dictionary:
 var data: Dictionary=super.snapshot(identity,now)
 data.station=bench+1
 data.measurement_changed=measurement_valid and fault.is_empty()
 data.equipment_fault=not fault.is_empty()
 return data

func submit(host: bool,identity: String,id: String,response: Variant,now: float) -> String:
 if not host or closed or not is_finite(now) or now>=deadline:return "closed"
 if id!=event_id or not present.has(identity):return "not_participating"
 if submissions.has(identity):return "already_submitted"
 if not response is String or not response.is_valid_int() or int(response) not in range(3):return "invalid"
 submissions[identity]={"prediction":int(response)};submitted_at[identity]=now
 return "accepted"

func finish(host: bool) -> bool:
 if not host or closed:return false
 closed=true
 var measured:=measurement_valid and fault.is_empty()
 var tolerance:=maxf(.05,first_voltage*.01)
 var answer:=0 if final_voltage>first_voltage+tolerance else (1 if final_voltage<first_voltage-tolerance else 2)
 for identity in submissions:
  var response: Dictionary=submissions[identity]
  response.correct=measured and int(response.prediction)==answer
  response.reason=("Measured %.2f V RMS after the change."%final_voltage) if measured else ("The station tripped: "+fault.left(160) if not fault.is_empty() else "No valid live equipment change was measured.")
 return true

func reveal() -> Dictionary:
 if not closed:return {}
 if not fault.is_empty():return {"fault":fault.left(160),"source":"live AC station"}
 if not measurement_valid:return {"status":"No live equipment change measured","source":"live AC station"}
 var tolerance:=maxf(.05,first_voltage*.01)
 var answer:=0 if final_voltage>first_voltage+tolerance else (1 if final_voltage<first_voltage-tolerance else 2)
 return {"answer":public_question.options[answer],"before_v":first_voltage,"after_v":final_voltage,"channel":channel+1,"source":"live AC station"}
