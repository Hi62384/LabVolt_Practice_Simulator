extends RefCounted
## Test-only integration boundary; a live RPC must derive peer from its sender.
const Authority=preload("res://scripts/campus/academics/classroom_events/participant_authority.gd")
const Round=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")
const Hands=preload("res://scripts/campus/academics/classroom_events/hand_queue.gd")
var round:=Round.new()
var hands:=Hands.new()
var roster: Dictionary={}
var identities: Dictionary={}
var activity: Dictionary={}

func submit(host: bool,peer: int,inside: bool,class_id: String,event_id: String,response: Variant,now: float) -> String:
 if not host:return "denied"
 var identity:=Authority.resolve(peer,roster,identities,activity,inside)
 if identity.is_empty() or str(activity.get("id",""))!=class_id:return "denied"
 return round.submit(true,identity,event_id,response,now)

func hand(host: bool,peer: int,inside: bool,class_id: String,event_id: String,raised: bool) -> bool:
 if not host:return false
 var identity:=Authority.resolve(peer,roster,identities,activity,inside)
 if identity.is_empty() or str(activity.get("id",""))!=class_id:return false
 return hands.set_hand(true,event_id,identity,raised)

func assessment_started(host: bool) -> bool:
 if not host:return false
 if not round.closed:round.finish(true)
 if not hands.event_id.is_empty():hands.close(true,hands.event_id)
 activity.phase="assignment"
 return true
