extends RefCounted
## Isolated Godot fixture; deliberately not connected to live classroom code.
const MAX_STUDENTS:=32
const CORE_RESERVE:=45.0
const TRANSITIONS:={
 "proposed":["preparing","cancelled"],"preparing":["announcing","cancelled"],
 "announcing":["active","cancelled"],"active":["resolving","interrupted","timed_out","cancelled"],
 "interrupted":["active","timed_out","cancelled"],"resolving":["complete","cancelled"]}
var event: Dictionary={}
var sequence:=0
var recent: Array[String]=[]
var completed:=0

func propose(host: bool,phase: String,seconds_left: float,course: String,definitions: Array,students: Array,roll: int) -> Dictionary:
 if not host or phase!="lesson" or not event.is_empty() or completed>=3 or not is_finite(seconds_left):return {}
 if students.is_empty() or students.size()>MAX_STUDENTS:return {}
 var unique:={}
 for identity in students:
  if not identity is String or identity.is_empty() or unique.has(identity):return {}
  unique[identity]=true
 var choices:=[];var total:=0
 for item in definitions:
  if not item is Dictionary:continue
  var id:=str(item.get("id",""));var weight:=int(item.get("weight",0));var duration:=float(item.get("seconds",0))
  if id.is_empty() or id in recent or weight<1 or weight>1000 or not is_finite(duration) or duration<=0:continue
  if course not in item.get("courses",[]) or duration+CORE_RESERVE>seconds_left:continue
  choices.append(item);total+=weight
 if choices.is_empty():return {}
 var pick:=posmod(roll,total);var selected: Dictionary=choices.back()
 for item in choices:
  if pick<int(item.weight):selected=item;break
  pick-=int(item.weight)
 sequence+=1
 event={"id":str(sequence),"definition":str(selected.id),"state":"proposed","resource":str(selected.get("resource","")),"participants":students.duplicate(),"seconds":float(selected.seconds)}
 return event.duplicate(true)

func advance(host: bool,event_id: String,target: String) -> bool:
 if not host or event.is_empty() or event.id!=event_id or target not in TRANSITIONS.get(event.state,[]):return false
 event.state=target
 if target in ["complete","cancelled","timed_out"]:
  recent.append(event.definition)
  if recent.size()>6:recent.pop_front()
  if target=="complete":completed+=1
  event.clear()
 return true

func assessment_started(host: bool) -> bool:
 if not host:return false
 if not event.is_empty():
  recent.append(event.definition)
  if recent.size()>6:recent.pop_front()
  event.clear()
 return true

func participant_disconnected(host: bool,identity: String) -> bool:
 if not host or event.is_empty() or identity not in event.participants:return false
 event.participants.erase(identity)
 if event.participants.is_empty():advance(true,event.id,"cancelled")
 return true
