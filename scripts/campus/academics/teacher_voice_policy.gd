extends RefCounted
## Host-side classification of voice activity. No audio or transcript is retained.

static func permitted(peer: int,identity: String,activity: Dictionary,event: Dictionary,now: float) -> bool:
 if peer<=0 or identity.is_empty() or activity.get("phase","")!="lesson" or event.is_empty():return false
 var class_id:=str(activity.get("id",""))
 if class_id.is_empty() or str(event.get("class_id",""))!=class_id or event.get("round")==null:return false
 var student: Dictionary=activity.get("students",{}).get(identity,{})
 if student.is_empty() or int(student.get("peer",0))!=peer or bool(student.get("done",false)):return false
 var round: Object=event.round
 if round.get("closed")==true:return false
 if now<float(event.get("open_at",INF)):return false
 var deadline: Variant=round.get("deadline")
 if not (deadline is int or deadline is float) or now>=float(deadline):return false
 var participants: Variant=round.get("participants")
 if not participants is Dictionary or not participants.has(identity):return false
 if str(round.get("mode"))=="group":return true
 var hands: Object=event.get("hands")
 return hands!=null and str(hands.get("selected"))==identity and float(event.get("called_until",0.0))>now
