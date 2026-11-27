extends RefCounted
## A shared rule for host-verified human and NPC incidents. Dialogue can explain
## a decision; it cannot manufacture evidence, marks, inventory or punishment.
const INCIDENTS:=["class_message","voice_noise","phone_use","seat_departure","thrown_object","lab_hazard"]

static func consider(person: Dictionary,evidence: Dictionary,previous: Dictionary={},now_ms: int=0) -> Dictionary:
	if not bool(evidence.get("verified",false)) or not bool(evidence.get("perceived",false)):return {}
	var kind:=str(evidence.get("kind",""))
	var phase:=str(evidence.get("phase",""))
	var event_id:=str(evidence.get("event_id",""))
	var severity:=float(evidence.get("severity",0.))
	if kind not in INCIDENTS or phase not in ["lesson","assignment"] or event_id.is_empty() or not is_finite(severity):return {}
	var record:=previous.duplicate(true)
	# Callers may attach a diagnostic decision snapshot. It is not history and
	# must not recursively contain earlier full records on every incident.
	record.erase("decision")
	var recent: Array=record.get("events",[])
	if event_id in recent:return {}
	recent.append(event_id)
	if recent.size()>64:recent.pop_front()
	record.events=recent
	var count:=clampi(int(record.get("count",0))+1,1,100)
	record.count=count
	record.last_incident=now_ms
	severity=clampf(severity,0.,1.)
	var traits: Dictionary=person.get("traits",{})
	var strict:=float(traits.get("strictness",person.get("strictness",.5)))
	var effort:=float(traits.get("teaching_effort",.5))
	var patience:=float(traits.get("patience",.5))
	var temper:=float(traits.get("temper",.5))
	var tolerance:=1.+(1.-strict)*3.+patience*2.+(1.-effort)*2.
	var urgency:=severity*.9+float(count)/tolerance*.4+temper*.15
	var action:="ignore"
	var reason:="Minor interruption does not outweigh the current lesson."
	var safety:=kind=="lab_hazard"
	if safety:
		action="stop_activity"
		reason="Verified laboratory hazard requires an immediate intervention."
	elif now_ms-int(record.get("last_action_at",-30000))<6000:
		reason="Incident recorded; let the previous instruction take effect."
	elif count>=maxi(5,ceili(tolerance*1.7)) and int(record.get("warnings",0))>=2:
		action="move" if phase=="assignment" else "remove"
		reason="Disruption continued after repeated, perceived warnings. Preserve access to unfinished assessment work."
	elif kind=="phone_use" and count>=maxi(3,ceili(tolerance)) and int(record.get("phone_requests",0))>=1:
		action="confiscate"
		reason="The phone remained in use after a perceived put-away instruction; use the existing custody system and return rules."
	elif kind=="phone_use" and (count>=2 or strict>.75):
		action="put_away"
		reason="The visible personal item is interrupting the class."
	elif count>=maxi(3,ceili(tolerance)) and int(record.get("warnings",0))>=1:
		action="move"
		reason="Changing seats can separate the recurring distraction."
	elif urgency>.75:
		action="warning"
		reason="The repeated or serious interruption warrants a clear warning."
	elif urgency>.47:
		action="remark"
		reason="Address the observed behavior before escalating it."
	elif urgency>.29:
		action="look"
		reason="A visible glance may be enough to redirect attention."
	if action!="ignore":
		record.last_action_at=now_ms
		record.last_action=action
	if action in ["warning","put_away","move"]:record.warnings=mini(20,int(record.get("warnings",0))+1)
	if action=="put_away":record.phone_requests=mini(20,int(record.get("phone_requests",0))+1)
	return {"action":action,"reason":reason,"record":record,"kind":kind,"severity":severity,
		"safety":safety,"interrupt":action in ["warning","put_away","confiscate","move","remove","stop_activity"]}
