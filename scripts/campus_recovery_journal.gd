extends RefCounted
const PATH := "user://campus_academic_recovery.dat"
static func read(identity: String) -> Dictionary:
	if not FileAccess.file_exists(PATH):return {"ok":false,"error":"No saved class for this character."}
	var file := FileAccess.open(PATH,FileAccess.READ)
	if file==null:return {"ok":false,"error":"The saved class could not be opened."}
	if file.get_length()<8 or file.get_length()>16777216:file.close();return {"ok":false,"error":"The saved class is incomplete or exceeds its size limit."}
	var data: Variant=file.get_var(false);file.close()
	if not data is Dictionary or data.get("schema")!=1:return {"ok":false,"error":"Invalid saved class."}
	for key in ["activity","project","presentation","papers","students","identities","allocation"]:
		if not data.get(key) is Dictionary:return {"ok":false,"error":"Incomplete saved class: "+key}
	for key in ["remaining","deadline","saved_at","round_id","next_id"]:
		if not data.get(key) is float and not data.get(key) is int:return {"ok":false,"error":"Invalid saved class timing."}
		if not is_finite(float(data[key])) or float(data[key])<0:return {"ok":false,"error":"Invalid saved class timing."}
	if data.get("phase","") not in ["travel","lesson","assignment","complete"] or not data.get("assessment_id") is String:return {"ok":false,"error":"Invalid saved class state."}
	var owner := str(data.get("host_identity",data.identities.get(1,"")))
	if owner=="" or identity!=owner:return {"ok":false,"error":"Select the character that hosted this saved class."}
	for key in ["teaching_seconds","assessment_seconds"]:
		var value: Variant=data.activity.get(key)
		if not value is float and not value is int:return {"ok":false,"error":"Incomplete saved class duration."}
		if not is_finite(float(value)) or float(value)<=0:return {"ok":false,"error":"Invalid saved class duration."}
	if data.papers.size()>512 or data.students.size()>64:return {"ok":false,"error":"Saved class capacity exceeded."}
	for paper in data.papers.values():
		if not paper is Dictionary or not paper.get("project") is Dictionary or not paper.get("identity") is String:return {"ok":false,"error":"Invalid saved worksheet."}
	for student in data.students.values():
		if not student is Dictionary:return {"ok":false,"error":"Invalid saved student record."}
	return {"ok":true,"data":data}
static func summary(identity: String) -> Dictionary:
	var result := read(identity)
	if not result.ok:return result
	var data: Dictionary=result.data
	if data.phase=="complete":return {"ok":false,"error":"The saved class is complete."}
	return {"ok":true,"course_id":str(data.activity.get("course_id","")),"kind":str(data.activity.get("kind","")),"week":int(data.activity.get("week",1)),"phase":str(data.phase)}
