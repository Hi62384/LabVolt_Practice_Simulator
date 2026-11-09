extends RefCounted
## Uses the existing teacher_records archive and its atomic writer.
## No session, answer, inventory or profile snapshots are retained.
const VERSION := 1

static func enroll(archive: Dictionary, records: Array[Dictionary], persist: Callable) -> Error:
	var next := archive.duplicate(true)
	for record in records:
		var token := str(record.get("profile",""))
		var id := str(record.get("id",""))
		if token.is_empty() or id.is_empty():return ERR_INVALID_DATA
		if next.get(token,{}).has(id):continue
		if not next.has(token):next[token]={}
		var pending := record.duplicate(true)
		pending.erase("score")
		pending["pending_assessment_version"]=VERSION
		next[token][id]=pending
	var error: Error=persist.call(next)
	if error!=OK:return error
	archive.clear();archive.merge(next,true)
	return OK

static func prepare(archive: Dictionary, record: Dictionary, persist: Callable) -> Error:
	var token := str(record.get("profile",""))
	var id := str(record.get("id",""))
	if token.is_empty() or id.is_empty():return ERR_INVALID_DATA
	if archive.get(token,{}).has(id):return OK
	var next := archive.duplicate(true)
	if not next.has(token):next[token]={}
	var pending := record.duplicate(true)
	pending.erase("score")
	pending["pending_assessment_version"]=VERSION
	next[token][id]=pending
	var error: Error=persist.call(next)
	if error!=OK:return error
	archive.clear();archive.merge(next,true)
	return OK

static func settle(archive: Dictionary, result: Dictionary, persist: Callable) -> Error:
	var token := str(result.get("profile",""))
	var id := str(result.get("id",""))
	var old: Dictionary=archive.get(token,{}).get(id,{})
	if not old.is_empty() and not old.has("pending_assessment_version"):return OK
	if token.is_empty() or id.is_empty() or not result.has("score"):return ERR_INVALID_DATA
	var next := archive.duplicate(true)
	if not next.has(token):next[token]={}
	var final := result.duplicate(true)
	final.erase("pending_assessment_version")
	next[token][id]=final
	var error: Error=persist.call(next)
	if error!=OK:return error
	archive.clear();archive.merge(next,true)
	return OK

static func abandoned(archive: Dictionary, token: String) -> Array[Dictionary]:
	var results: Array[Dictionary]=[]
	for stored in archive.get(token,{}).values():
		if not stored is Dictionary or int(stored.get("pending_assessment_version",0))!=VERSION:continue
		var result: Dictionary=stored.duplicate(true)
		result.erase("pending_assessment_version")
		result["score"]=0.0
		result["reason"]="Left class before completing the assigned assessment."
		results.append(result)
	return results
