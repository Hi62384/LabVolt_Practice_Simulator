extends RefCounted
const Progression=preload("res://scripts/campus/academics/course_progression.gd")
const Weights=preload("res://scripts/campus/academics/grade_weight_policy.gd")
static func summary(gradebook: Dictionary, profile: String, course_id: String, course_bridge: Object) -> Dictionary:
	var requirements := {"lecture":course_bridge.call("weeks",course_id,"lecture").size(),"lab":course_bridge.call("weeks",course_id,"lab").size()}
	return Progression.summarize(gradebook,profile,course_id,requirements,Progression.weights_from_tracks(Weights.final_weights(Weights.course(course_id))))
static func record_fields(project: Dictionary) -> Dictionary:
	return {"is_exam":bool(project.get("is_exam",false)),"assessment_type":str(project.get("assessment_type","assignment")),"grade_weight":project.get("grade_weight")}
static func menu_catalog(gradebook: Dictionary, profile: String, course_bridge: Object, attendance_events: Dictionary={}) -> Dictionary:
	var courses: Array=[];var groups := {};var recent_rows: Array=[];var activity_rows: Array=[];var attendance_available := not attendance_events.is_empty()
	for catalog_entry in course_bridge.call("catalog"):
		var id := str(catalog_entry.get("id",catalog_entry.get("course_id","")))
		if id.is_empty():continue
		var subject := str(catalog_entry.get("subject",_subject(id)))
		var projection := summary(gradebook,profile,id,course_bridge)
		var tracks := {};var latest_attendance := "";var latest_activity := ""
		for kind in ["lecture","lab"]:
			var weeks: Array=[]
			for row in course_bridge.call("weeks",id,kind):
				var week := int(row.get("week",weeks.size()+1));var completion := _completion(projection,kind,week)
				var attendance := _attendance(attendance_events,profile,id,kind,week)
				if str(attendance.get("latest_time",""))>latest_attendance:latest_attendance=str(attendance.latest_time)
				weeks.append({"week":week,"title":str(row.get("title","")),"kind":kind,"is_exam":bool(row.get("is_exam",false)),"assessment_type":str(row.get("assessment_type","exam" if bool(row.get("is_exam",false)) else "assignment")),"grade_weight":row.get("grade_weight"),"completed":completion.completed,"attempts":completion.attempts,"best_score":completion.best_score,"marks":completion.marks,"attendance":attendance.status,"attendance_time":attendance.latest_time})
			tracks[kind]=weeks
		for record in gradebook.values():
			if record is Dictionary and str(record.get("profile",""))==profile and str(record.get("course_id",""))==id and not bool(record.get("lesson",false)) and not bool(record.get("practice",false)) and not bool(record.get("linked_practice",false)):
				var stamp := _valid_time(str(record.get("time","")));if stamp>latest_activity:latest_activity=stamp
		var course := {"course_id":id,"display_name":str(catalog_entry.get("title",catalog_entry.get("name",id))),"subject":subject,"subject_group":subject,"mark":{"status":projection.status,"running":projection.current_attempt.get("running_mark"),"earned_to_date":projection.current_attempt.get("earned_to_date",0.0),"final":projection.final_mark,"passed":projection.passed,"pass_mark":projection.pass_mark},"tracks":tracks,"latest_attendance_time":latest_attendance,"latest_activity_time":latest_activity,"recently_attended":not latest_attendance.is_empty(),"attendance_history_available":attendance_available}
		courses.append(course)
		if not groups.has(subject):
			groups[subject] = []
		groups[subject].append(id)
		if not latest_attendance.is_empty():recent_rows.append({"course_id":id,"time":latest_attendance})
		if not latest_activity.is_empty():activity_rows.append({"course_id":id,"time":latest_activity})
	recent_rows.sort_custom(func(a,b):return str(a.time)>str(b.time))
	activity_rows.sort_custom(func(a,b):return str(a.time)>str(b.time))
	return {"schema":"academic-menu.v1","courses":courses,"groups":groups,"recent_attendance":recent_rows,"recent_activity":activity_rows,"attendance_history_available":attendance_available,"attendance_fallback":"Completion is shown from official marked work. Attendance remains unavailable unless authoritative attendance events are supplied; no absence is inferred."}
static func _subject(course_id: String) -> String:
	return "Mathematics" if course_id.begins_with("MTH") else "Electrical" if course_id.begins_with("ELM") or course_id.begins_with("ETY") else "Other"
static func _completion(projection: Dictionary, kind: String, week: int) -> Dictionary:
	var count := 0;var best: Variant=null;var marks: Array=[];var slot := "%s:%d"%[kind,week]
	var attempts: Array=projection.get("completed_attempts",[])+projection.get("open_attempts",[])
	for attempt in attempts:
		if not attempt.records.has(slot):continue
		count+=1;var record: Dictionary=attempt.records[slot];var score := float(record.score);best=score if best==null else maxf(float(best),score)
		marks.append({"attempt":int(attempt.number),"attempt_complete":bool(attempt.complete),"score":score,"time":str(record.get("time","")),"assessment_id":str(record.get("assessment_id",record.get("id",""))),"reason":str(record.get("reason",""))})
	return {"completed":count>0,"attempts":count,"best_score":best,"marks":marks}
static func _attendance(events: Dictionary, profile: String, course: String, kind: String, week: int) -> Dictionary:
	var matched := false;var found := false;var latest := ""
	for event in events.values():
		if not event is Dictionary or str(event.get("profile",""))!=profile or str(event.get("course_id",""))!=course or str(event.get("kind",""))!=kind or int(event.get("week",0))!=week:continue
		matched=true;found=found or bool(event.get("attended",false));var stamp := _valid_time(str(event.get("time","")));if stamp>latest:latest=stamp
	return {"status":"attended" if found else ("not_attended" if matched else "unavailable"),"latest_time":latest}
static func _valid_time(stamp: String) -> String:
	if stamp.is_empty():return ""
	return stamp if Time.get_unix_time_from_datetime_string(stamp)>0 else ""
