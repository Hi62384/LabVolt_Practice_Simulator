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

## Reconcile only the named session on orderly host exit. On process startup,
## every persisted class has ended because class sessions cannot resume.
static func end_host_session(archive: Dictionary, persist: Callable, session_id: String = "") -> Error:
	var next := archive.duplicate(true)
	var changed := false
	for token in next:
		var entries: Variant = next[token]
		if not entries is Dictionary:continue
		for id in entries.keys():
			var record: Variant = entries[id]
			if not record is Dictionary or record.get("pending_assessment_version") != VERSION or record.has("score"):continue
			if session_id != "" and str(record.get("assessment_id", "")) != session_id:continue
			changed = true
			if (record.get("class_authority_role") == "host" or record.get("room_class",false)) and str(record.get("profile", "")) == str(token) and str(record.get("id", "")) == str(id):
				record.erase("pending_assessment_version")
				record["score"] = 0.0
				record["reason"] = "Hosted class ended before the assignment was completed."
			else:
				# Guest work is interrupted. Legacy entries have no reliable role.
				entries.erase(id)
	if not changed:return OK
	var error: Error = persist.call(next)
	if error != OK:return error
	archive.clear()
	archive.merge(next, true)
	return OK
