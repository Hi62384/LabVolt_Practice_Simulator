extends RefCounted
## Separate authoritative attendance facts. Never creates marks, attempts or rewards.
const VERSION := 1
static func event_id(session_id: String, profile: String, course_id: String, kind: String, week: int) -> String:
	return "attendance:%s:%s:%s:%s:%d"%[session_id,profile,course_id,kind,week]
static func record_authoritative(events: Dictionary, is_authority: bool, session_id: String, profile: String, course_id: String, kind: String, week: int, timestamp: String, allowed_courses: Array) -> Dictionary:
	if not is_authority:return {"ok":false,"error":"Attendance is host-authoritative."}
	if session_id.is_empty() or profile.is_empty() or course_id not in allowed_courses:return {"ok":false,"error":"Invalid attendance identity or course."}
	if kind not in ["lecture","lab"] or week<1:return {"ok":false,"error":"Invalid attendance track or week."}
	if Time.get_unix_time_from_datetime_string(timestamp)<=0:return {"ok":false,"error":"Attendance requires a valid host timestamp."}
	var id := event_id(session_id,profile,course_id,kind,week)
	if events.has(id):return {"ok":true,"created":false,"id":id,"event":events[id].duplicate(true)}
	var event := {"version":VERSION,"id":id,"profile":profile,"course_id":course_id,"kind":kind,"week":week,"attended":true,"time":timestamp,"session_id":session_id}
	events[id]=event
	return {"ok":true,"created":true,"id":id,"event":event.duplicate(true)}
static func private_for_profile(events: Dictionary, profile: String) -> Dictionary:
	var result := {}
	for id in events:
		if events[id] is Dictionary and str(events[id].get("profile",""))==profile:result[id]=events[id].duplicate(true)
	return result
