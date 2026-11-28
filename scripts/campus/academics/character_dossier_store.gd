extends RefCounted
## One host-scoped authority. Getters return copies; inspector reads never create
## a relationship, generate a character, or count as a social event.
const Dossier = preload("res://scripts/campus/academics/character_dossier.gd")
const VERSION := 1
const STORAGE_VERSION := 2
const MAX_BYTES := 134217728
const MAX_IDENTITIES := 4128
static var dossiers: Dictionary = {}
static var jobs: Dictionary = {}
static var host_identity := ""
static var path := ""
static var revision := 0
static var dirty := false
static var blocked := false
static var last_save_error := OK
static var last_load_error := OK
static var recovered_backup := false
static var _session_cache: Dictionary = {}
static var _projection_cache: Dictionary = {}
static var hydrated_count := 0
static var unavailable: Dictionary = {}

static func set_host_profile(identity: String) -> Error:
	if identity.is_empty() or identity.length() > 128: return ERR_INVALID_PARAMETER
	if identity == host_identity and not path.is_empty(): return OK
	if dirty and not path.is_empty():
		var error := save()
		if error != OK:
			# Preserve an unsaved owner namespace rather than leak it to another host.
			if _session_cache.size() >= 8 and not _session_cache.has(host_identity): return error
			var total_bytes:=JSON.stringify({"dossiers":dossiers,"jobs":jobs}).to_utf8_buffer().size()
			for cached_id in _session_cache:
				if cached_id not in [host_identity,identity]: total_bytes+=JSON.stringify(_session_cache[cached_id]).to_utf8_buffer().size()
			if total_bytes>MAX_BYTES:return ERR_OUT_OF_MEMORY
			_session_cache[host_identity] = {"dossiers": dossiers.duplicate(true), "jobs": jobs.duplicate(true), "blocked": blocked, "error": error}
	var next_path := "user://character_memory/" + identity.sha256_text() + ".dossiers.json"
	var folder_error := DirAccess.make_dir_recursive_absolute("user://character_memory")
	if folder_error != OK: return folder_error
	host_identity = identity
	path = next_path
	revision += 1
	_projection_cache.clear()
	unavailable.clear()
	hydrated_count=0
	dossiers = {}
	jobs = {}
	dirty = false
	blocked = false
	last_save_error = OK
	last_load_error = OK
	recovered_backup = false
	if _session_cache.has(identity):
		var cached: Dictionary = _session_cache[identity]
		dossiers = cached.dossiers
		jobs = cached.jobs
		blocked = bool(cached.blocked)
		last_save_error = int(cached.error)
		dirty = true
		_session_cache.erase(identity)
		return OK
	var loaded := _read(next_path)
	if loaded.is_empty():
		loaded = _read(next_path + ".bak")
		recovered_backup = not loaded.is_empty()
	if loaded.is_empty():
		blocked = FileAccess.file_exists(next_path) or FileAccess.file_exists(next_path + ".bak")
		last_load_error = ERR_FILE_CORRUPT if blocked else OK
		return last_load_error
	dossiers = loaded.dossiers
	jobs = loaded.jobs
	for job in jobs.values():
		if job.get("status") == "running":
			job.status = "queued"
			job.attempts = maxi(0,int(job.get("attempts",0))-1)
			job.interrupted_requests = int(job.get("interrupted_requests",0))+1
			job.last_error = "Previous session ended before this generation completed."
			dirty = true
	dirty = dirty or recovered_backup
	if int(loaded.version)==VERSION:
		# Commit immutable blobs first, then replace the legacy collection with a
		# lightweight manifest. A process interruption leaves the old file valid.
		dirty=true
		var migration_error:=save()
		if migration_error!=OK:return migration_error
		var migrated:=_read(path)
		if not migrated.is_empty():dossiers=migrated.dossiers
	return OK

static func ensure(profile: Dictionary) -> Dictionary:
	if profile.get("identity_scope", "") == "public": return {}
	var id := str(profile.get("id", ""))
	if id.is_empty(): return {}
	if not dossiers.has(id):
		if profile.get("dossier_ref",false):
			unavailable[id]="Saved dossier reference is unavailable; identity was retained."
			return {}
		if dossiers.size() >= MAX_IDENTITIES: return Dossier.migrate(profile)
		dossiers[id] = Dossier.migrate(profile)
		dirty = true
	return get_dossier(id)

static func project(profile: Dictionary) -> Dictionary:
	if profile.get("identity_scope", "") == "public": return profile.duplicate(true)
	var id := str(profile.get("id",""))
	if not dossiers.has(id): ensure(profile)
	if not dossiers.has(id): return {} if profile.get("dossier_ref",false) else _voice_scoped(profile.duplicate(true))
	var d:=get_dossier(id)
	if d.is_empty():return {}
	var content_revision := int(d.get("revision",1))
	if not _projection_cache.has(id) or int(_projection_cache[id].revision)!=content_revision:
		_projection_cache[id]={"revision":content_revision,"profile":Dossier.project(profile,d)}
	var result: Dictionary=_projection_cache[id].profile.duplicate(true)
	# Attendance and origin are runtime index metadata, not biography revisions.
	for field in ["origin_population","persistent_id","attendance","newly_generated","enrollment","learning","learning_weeks"]:
		if profile.has(field):result[field]=profile[field].duplicate(true) if profile[field] is Dictionary or profile[field] is Array else profile[field]
	if not result.has("origin_population") and d.get("identity",{}).has("origin_population"):result.origin_population=d.identity.origin_population
	return _voice_scoped(result)

static func _voice_scoped(profile: Dictionary) -> Dictionary:
	# Generated IDs may recur in different host saves. Established faculty stay
	# globally authored; the voice store scopes other identities to this owner.
	profile.erase("voice_scope")
	if profile.get("role")=="student" and not str(profile.get("origin_population","")).is_empty():profile.voice_scope=str(profile.origin_population)
	elif not host_identity.is_empty():profile.voice_scope=host_identity.sha256_text()
	return profile

static func get_dossier(id: String) -> Dictionary:
	var entry: Dictionary=dossiers.get(id,{})
	if not entry.has("_blob"):return entry.duplicate(true)
	var data:=_load_blob(id,entry)
	if data.is_empty():
		unavailable[id]="Saved dossier is missing or corrupt; its identity is retained."
		last_load_error=ERR_FILE_CORRUPT
		return {}
	dossiers[id]=data
	unavailable.erase(id)
	hydrated_count+=1
	return data.duplicate(true)

static func summary(id: String) -> Dictionary:
	var entry: Dictionary=dossiers.get(id,{})
	if entry.is_empty():return {}
	return entry.duplicate(true) if entry.has("_blob") else _entry(entry,str(entry.get("_blob","")),0)

static func preserve_biography(id: String, biography: Dictionary) -> void:
	# One-time migration only. Developing facts remain in CharacterLifeMemory.
	if not dossiers.has(id): return
	if get_dossier(id).is_empty():return
	var d: Dictionary = dossiers[id]
	var established: Dictionary = d.get_or_add("established_biography", {})
	for key in biography:
		if not biography[key] is String or biography[key].strip_edges().is_empty() or established.has(key): continue
		established[key] = biography[key]
		d.life_history.append({"id": "preserved_" + str(key), "title": str(key).replace("_", " ").capitalize(), "text": biography[key], "topics": [str(key)], "entities": [], "chronology": "Established before dossier migration", "source": "migrated_fiction"})
		dirty = true
		d.revision = int(d.get("revision",1))+1

static func queue(profile: Dictionary, priority := 0) -> bool:
	if blocked or profile.get("identity_scope", "") == "public": return false
	var known: Dictionary=dossiers.get(str(profile.get("id","")),{})
	if known.get("generation",{}).get("status")=="complete" or unavailable.has(str(profile.get("id",""))):return false
	var d := ensure(profile)
	var id := str(profile.get("id", ""))
	if id.is_empty() or d.is_empty() or d.get("generation", {}).get("status") == "complete": return false
	if jobs.has(id):
		jobs[id].priority = maxi(int(jobs[id].get("priority", 0)), priority)
		return false
	jobs[id] = {"id": id, "kind": "expand", "status": "queued", "priority": priority, "attempts": 0, "stage": "full", "draft": {}, "issues": [], "invalid_sections": [], "created_at": int(Time.get_unix_time_from_system()), "retry_at": 0, "requests": 0, "measurement": {}, "last_error": ""}
	dirty = true
	return true

static func queue_student(id: String,seed: Dictionary={}) -> bool:
	if blocked or jobs.has(id) or dossiers.has(id) or jobs.size() >= MAX_IDENTITIES: return false
	jobs[id] = {"id": id, "kind": "student", "status": "queued", "priority": 1, "attempts": 0, "stage": "full", "draft": {}, "issues": [], "invalid_sections": [], "created_at": int(Time.get_unix_time_from_system()), "retry_at": 0, "requests": 0, "measurement": {}, "last_error": ""}
	if not seed.is_empty():jobs[id].seed=seed.duplicate(true)
	dirty = true
	return true

static func queue_custom_teacher(id: String, course: String, design: String) -> bool:
	if blocked or jobs.has(id) or dossiers.has(id) or not id.begins_with("generated_"): return false
	if course not in ["MTH147","MTH255","ETY155","ELM253","DGS266"] or design.strip_edges().length()<3 or design.length()>2000: return false
	jobs[id] = {"id":id,"kind":"teacher","status":"queued","priority":8,"attempts":0,"stage":"full","draft":{},"issues":[],"invalid_sections":[],"created_at":int(Time.get_unix_time_from_system()),"retry_at":0,"requests":0,"measurement":{},"last_error":"",
		"seed":{"identity":{"id":id,"role":"teacher"},"subjects":[course],"design_specification":design}}
	dirty=true
	return true

static func update_job(id: String, job: Dictionary) -> void:
	if not jobs.has(id): return
	jobs[id] = job.duplicate(true)
	dirty = true

static func publish(candidate: Dictionary, seed: Dictionary = {}, telemetry: Dictionary = {}) -> Dictionary:
	if blocked: return {"ok": false, "error": "Dossier persistence is blocked."}
	var id := str(candidate.get("identity",{}).get("id",""))
	if dossiers.has(id):
		seed=get_dossier(id)
		if seed.is_empty():return {"ok":false,"error":"Established dossier is unavailable; identity was retained."}
	var validation := Dossier.validate(candidate, seed)
	if not validation.ok: return validation
	var previous:=get_dossier(id)
	var d := {}
	for field in ["identity", "life_history", "personality", "communication", "traits", "knowledge", "voice", "compact_core", "trait_evidence"]:
		d[field] = candidate[field].duplicate(true) if candidate[field] is Dictionary or candidate[field] is Array else candidate[field]
	if not seed.get("identity",{}).get("appearance",{}).is_empty(): d.identity.appearance=seed.identity.appearance.duplicate(true)
	if _digest(seed.get("identity",{}).get("origin_population")):d.identity.origin_population=seed.identity.origin_population
	d.version = VERSION
	d.revision = int(previous.get("revision",0))+1
	d.subjects = seed.get("subjects",[]).duplicate()
	d.design_specification = str(seed.get("design_specification", ""))
	d.trait_constraints = seed.get("trait_constraints", {}).duplicate(true)
	d.established_biography = seed.get("established_biography", {}).duplicate(true)
	# Preserve complete established sections verbatim as anchors, even if the
	# generator elaborated them elsewhere. Never replace a known life with a rewrite.
	var existing_ids := {}
	for section in d.life_history:
		existing_ids[str(section.id)] = true
		section.source = "preexisting_fiction"
	for section in seed.get("life_history", []):
		if section.get("source", "") != "migrated_fiction": continue
		var preserved: Dictionary = section.duplicate(true)
		preserved.id = "established_" + str(preserved.id)
		if not existing_ids.has(preserved.id): d.life_history.append(preserved)
	d.provenance = {"source": "ai_generated", "history_kind": "fictional", "created_at": int(seed.get("provenance", {}).get("created_at", Time.get_unix_time_from_system()))}
	d.generation = {"status": "complete", "source": "ai_generated", "completed_at": int(Time.get_unix_time_from_system()), "measurement": telemetry.duplicate(true)}
	dossiers[id] = d
	dirty = true
	var saved := save()
	if saved != OK:
		if previous.is_empty(): dossiers.erase(id)
		else: dossiers[id] = previous
		dirty = true
		return {"ok": false, "error": "Validated identity could not be saved.", "save_error": saved}
	return {"ok": true, "id": id, "dossier": d.duplicate(true)}

static func save() -> Error:
	if blocked:
		last_save_error = ERR_FILE_CORRUPT
		return last_save_error
	if path.is_empty():
		last_save_error = ERR_UNCONFIGURED
		return last_save_error
	var old := _read(path)
	var backup := _read(path + ".bak")
	if old.is_empty() and backup.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")):
		blocked = true
		last_save_error = ERR_FILE_CORRUPT
		return last_save_error
	for source in [path, path + ".bak"]:
		if FileAccess.file_exists(source) and (old.is_empty() if source == path else backup.is_empty()):
			var destination: String = source + ".corrupt-" + FileAccess.get_sha256(source)
			if not FileAccess.file_exists(destination):
				last_save_error = DirAccess.copy_absolute(source, destination)
				if last_save_error != OK: return last_save_error
	var entries:={}
	var total_bytes:=0
	for id in dossiers:
		var d: Dictionary=dossiers[id]
		if d.has("_blob"):
			if not _valid_entry(str(id),d):last_save_error=ERR_INVALID_DATA;return last_save_error
			entries[id]=d.duplicate(true)
		else:
			var stored:=_store_blob(str(id),d)
			if stored.is_empty():return last_save_error
			entries[id]=stored
		total_bytes+=int(entries[id].get("_bytes",0))
	if total_bytes>MAX_BYTES:last_save_error=ERR_OUT_OF_MEMORY;return last_save_error
	var serialized := JSON.stringify({"version": STORAGE_VERSION, "dossiers": entries, "jobs": jobs})
	if serialized.to_utf8_buffer().size() > MAX_BYTES:
		last_save_error = ERR_OUT_OF_MEMORY
		return last_save_error
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_save_error = FileAccess.get_open_error()
		return last_save_error
	file.store_string(serialized)
	file.flush()
	last_save_error = file.get_error()
	file.close()
	if last_save_error != OK: return last_save_error
	if _read(path + ".tmp").is_empty():
		last_save_error = ERR_INVALID_DATA
		return last_save_error
	if not old.is_empty():
		if int(old.get("version",0))==VERSION and not FileAccess.file_exists(path+".legacy-v1.json"):
			last_save_error=DirAccess.copy_absolute(path,path+".legacy-v1.json")
			if last_save_error!=OK:return last_save_error
		last_save_error = DirAccess.copy_absolute(path, path + ".bak")
		if last_save_error != OK: return last_save_error
	last_save_error = DirAccess.rename_absolute(path + ".tmp", path)
	if last_save_error == OK: dirty = false
	return last_save_error

static func _read(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null: return {}
	if file.get_length() > MAX_BYTES: return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK: return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or not _whole(parsed.get("version"),VERSION,STORAGE_VERSION) or not parsed.get("dossiers") is Dictionary or not parsed.get("jobs") is Dictionary: return {}
	if parsed.dossiers.size() > MAX_IDENTITIES or parsed.jobs.size() > MAX_IDENTITIES: return {}
	for id in parsed.dossiers:
		var d: Variant = parsed.dossiers[id]
		if int(parsed.version)==STORAGE_VERSION:
			if not d is Dictionary or not _valid_entry(str(id),d):return {}
			continue
		if not d is Dictionary or not d.get("identity") is Dictionary or d.identity.get("id") != id: return {}
		for field in ["personality", "communication", "traits", "knowledge", "voice", "generation"]:
			if not d.get(field) is Dictionary: return {}
		if not d.get("life_history") is Array or not d.communication.get("examples") is Array: return {}
		if not Dossier.validate(d,{},false).ok: return {}
		for value in d.traits.values():
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0. or float(value) > 1.: return {}
	for id in parsed.jobs:
		var job: Variant = parsed.jobs[id]
		if not id is String or id.is_empty() or id.length()>64: return {}
		if not job is Dictionary or job.get("id") != id or job.get("status") not in ["queued", "running", "retry", "failed", "complete"] or not job.get("draft", {}) is Dictionary: return {}
		if job.get("kind") not in ["expand","student","teacher"] or job.get("stage") not in ["full","repair","publish"]: return {}
		for key in ["attempts","requests","request_attempts","cancelled_requests","interrupted_requests","canon_repairs"]:
			if not _whole(job.get(key,0),0,1000000): return {}
		if not _whole(job.get("priority",0),0,100): return {}
		for key in ["created_at","started_at","retry_at","completed_at","elapsed_ms"]:
			if not _whole(job.get(key,0),0,9000000000000): return {}
		for key in ["issues","invalid_sections"]:
			if not job.get(key,[]) is Array: return {}
			for entry in job.get(key,[]):
				if not entry is String or entry.length()>2500: return {}
		if not job.get("measurement",{}) is Dictionary or not job.get("last_error","") is String: return {}
		if job.has("canon_fingerprint") and not _digest(job.canon_fingerprint): return {}
		if not job.get("canon_hashes",{}) is Dictionary or job.get("canon_hashes",{}).size()>2048: return {}
		for topic in job.get("canon_hashes",{}):
			if not topic is String or topic.length()>96 or not _digest(job.canon_hashes[topic]): return {}
		if job.has("canon_fingerprint") and job.canon_fingerprint != JSON.stringify(job.get("canon_hashes",{}),"",true).sha256_text(): return {}
		if job.has("canon_example_ids"):
			if not job.canon_example_ids is Array or job.canon_example_ids.size()>120: return {}
			for example in job.canon_example_ids:
				if not example is String or example.length()>1800: return {}
		if job.has("canon_communication_description") and not job.canon_communication_description is bool: return {}
		if JSON.stringify(job.get("draft",{})).to_utf8_buffer().size()>Dossier.MAX_BYTES: return {}
		if job.has("seed") and (not job.seed is Dictionary or not job.seed.get("identity") is Dictionary or job.seed.identity.get("id")!=id): return {}
	return parsed

static func _digest(value: Variant) -> bool:
	if not value is String or value.length()!=64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum and floorf(float(value))==float(value)

static func diagnostics(id := "") -> Dictionary:
	var pending := 0
	var complete := 0
	for d in dossiers.values():
		if d.get("generation", {}).get("status") == "complete": complete += 1
	for job in jobs.values():
		if job.get("status") in ["queued", "running", "retry"]: pending += 1
	var job: Dictionary = jobs.get(id, {})
	var state: Dictionary = dossiers.get(id, {}).get("generation", {})
	return {"host_scoped": not host_identity.is_empty(), "identity_count": dossiers.size(), "complete_count": complete, "pending_count": pending, "selected_status": "unavailable" if unavailable.has(id) else str(job.get("status", state.get("status", "not_created"))), "last_error": str(unavailable.get(id,job.get("last_error", ""))), "attempts": int(job.get("attempts", 0)), "requests": int(job.get("requests", 0)), "measurement": job.get("measurement", state.get("measurement", {})).duplicate(true), "persistence_state": "blocked" if blocked else "unsaved" if dirty else "saved", "last_save_error": last_save_error, "last_load_error": last_load_error, "recovered_backup": recovered_backup, "storage_bytes": _storage_bytes(),"hydrated_count":hydrated_count,"unavailable_identities":unavailable.size()}

static func _storage_bytes() -> int:
	if path.is_empty(): return 0
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:return 0
	var bytes := file.get_length()
	file.close()
	for entry in dossiers.values():bytes+=int(entry.get("_bytes",0)) if entry.has("_blob") else JSON.stringify(entry).to_utf8_buffer().size()
	return bytes

static func _entry(dossier: Dictionary,blob: String,bytes: int) -> Dictionary:
	var identity: Dictionary=dossier.get("identity",{})
	var compact_identity:={}
	for field in ["id","name","age","role","program"]:compact_identity[field]=identity.get(field,"" if field!="age" else 18)
	if identity.has("origin_population"):compact_identity.origin_population=identity.origin_population
	var result:={"identity":compact_identity,"revision":int(dossier.get("revision",1)),"generation":{"status":str(dossier.get("generation",{}).get("status","needs_expansion"))},"subjects":dossier.get("subjects",[]).duplicate(),"traits":{"academic_motivation":float(dossier.get("traits",{}).get("academic_motivation",.5))}}
	if not blob.is_empty():result._blob=blob;result._bytes=bytes
	return result

static func _valid_entry(id: String,entry: Dictionary) -> bool:
	if id.is_empty() or id.length()>64 or not id.is_valid_identifier() or not _digest(entry.get("_blob")):return false
	if not _whole(entry.get("_bytes"),1,Dossier.MAX_BYTES) or not _whole(entry.get("revision"),1,1000000000):return false
	if not entry.get("identity") is Dictionary or not entry.get("generation") is Dictionary or not entry.get("traits") is Dictionary:return false
	if entry.identity.get("id")!=id or entry.identity.get("role") not in ["student","teacher","staff"] or not _whole(entry.identity.get("age"),18,110):return false
	if entry.identity.has("origin_population") and not _digest(entry.identity.origin_population):return false
	for field in ["name","program"]:
		if not entry.identity.get(field) is String or (entry.identity[field].is_empty() and field=="name") or entry.identity[field].length()>(80 if field=="name" else 160):return false
		for character in entry.identity[field]:
			if character.unicode_at(0)<32:return false
	if entry.generation.get("status") not in ["complete","needs_expansion"]:return false
	var motivation: Variant=entry.traits.get("academic_motivation")
	if not (motivation is int or motivation is float) or not is_finite(float(motivation)) or float(motivation)<0. or float(motivation)>1.:return false
	if not entry.get("subjects") is Array or entry.subjects.size()>128:return false
	for subject in entry.subjects:
		if not subject is String or subject.length()>256:return false
	return JSON.stringify(entry).to_utf8_buffer().size()<=4096

static func _read_blob(source: String,id: String,digest: String) -> Dictionary:
	var file:=FileAccess.open(source,FileAccess.READ)
	if file==null:return {}
	if file.get_length()>Dossier.MAX_BYTES:file.close();return {}
	var serialized:=file.get_as_text();file.close()
	if serialized.sha256_text()!=digest:return {}
	var raw: Variant=JSON.parse_string(serialized)
	if not raw is Dictionary or not raw.get("identity") is Dictionary or raw.identity.get("id")!=id:return {}
	return raw if Dossier.validate(raw,{},false).get("ok",false) else {}

static func _blob_path(digest: String) -> String:
	return path+".records/"+digest+".json"

static func _preserve_blob(source: String) -> Error:
	if not FileAccess.file_exists(source):return OK
	var copy:=source+".corrupt-"+FileAccess.get_sha256(source)
	return OK if FileAccess.file_exists(copy) else DirAccess.copy_absolute(source,copy)

static func _load_blob(id: String,entry: Dictionary) -> Dictionary:
	if not _valid_entry(id,entry):return {}
	var source:=_blob_path(str(entry._blob))
	var loaded:=_read_blob(source,id,str(entry._blob))
	if not loaded.is_empty():return loaded
	loaded=_read_blob(source+".bak",id,str(entry._blob))
	if loaded.is_empty():return {}
	# A backup is validated before repairing a corrupt primary. Its damaged
	# bytes remain available for recovery/debugging and are never silently lost.
	var error:=_preserve_blob(source)
	if error==OK:error=DirAccess.copy_absolute(source+".bak",source+".tmp")
	if error==OK:error=DirAccess.rename_absolute(source+".tmp",source)
	if error!=OK:last_save_error=error
	recovered_backup=true
	return loaded

static func _store_blob(id: String,dossier: Dictionary) -> Dictionary:
	if not dossier.get("identity") is Dictionary or dossier.identity.get("id")!=id or not Dossier.validate(dossier,{},false).get("ok",false):last_save_error=ERR_INVALID_DATA;return {}
	var serialized:=JSON.stringify(dossier,"",true)
	var digest:=serialized.sha256_text()
	var source:=_blob_path(digest)
	var entry:=_entry(dossier,digest,serialized.to_utf8_buffer().size())
	if not _valid_entry(id,entry):last_save_error=ERR_INVALID_DATA;return {}
	if not _read_blob(source,id,digest).is_empty() and not _read_blob(source+".bak",id,digest).is_empty():return entry
	last_save_error=DirAccess.make_dir_recursive_absolute(source.get_base_dir())
	if last_save_error!=OK:return {}
	for existing in [source,source+".bak"]:
		if FileAccess.file_exists(existing) and _read_blob(existing,id,digest).is_empty():
			last_save_error=_preserve_blob(existing)
			if last_save_error!=OK:return {}
	var file:=FileAccess.open(source+".tmp",FileAccess.WRITE)
	if file==null:last_save_error=FileAccess.get_open_error();return {}
	file.store_string(serialized);file.flush();last_save_error=file.get_error();file.close()
	if last_save_error!=OK:return {}
	if _read_blob(source+".tmp",id,digest).is_empty():last_save_error=ERR_INVALID_DATA;return {}
	last_save_error=DirAccess.rename_absolute(source+".tmp",source)
	if last_save_error!=OK:return {}
	last_save_error=DirAccess.copy_absolute(source,source+".bak")
	return entry if last_save_error==OK else {}

static func import_identity(incoming: Dictionary) -> Dictionary:
	if blocked or path.is_empty():return {"ok":false,"error":"Character storage is unavailable."}
	var validation:=Dossier.validate(incoming,{},false)
	if not validation.get("ok",false):return {"ok":false,"error":"Contributed dossier failed schema validation."}
	var id:=str(incoming.identity.id)
	if incoming.identity.get("role")!="student" or not id.begins_with("campus_student_"):return {"ok":false,"error":"Only student identities can be contributed."}
	var previous:=get_dossier(id)
	if dossiers.has(id) and previous.is_empty():return {"ok":false,"error":"Established dossier is unavailable; identity was retained."}
	var merged:=incoming.duplicate(true)
	# A revision number from a second device is not an authority claim. Preserve
	# established facts and merge only identical or new nonconflicting sections.
	if not previous.is_empty():
		for key in ["id","name","role","age","program","appearance"]:
			if JSON.stringify(JSON.parse_string(JSON.stringify(previous.identity.get(key))),"",true)!=JSON.stringify(JSON.parse_string(JSON.stringify(incoming.identity.get(key))),"",true):
				return {"ok":false,"conflict":true,"error":"Conflicting %s; established identity retained."%key}
		merged=previous.duplicate(true)
		var sections:={}
		for section in merged.life_history:sections[str(section.id)]=section
		for section in incoming.life_history:
			if sections.has(str(section.id)):
				if str(sections[str(section.id)].get("text",""))!=str(section.get("text","")):
					return {"ok":false,"conflict":true,"error":"Contradictory biography section retained for review."}
			else:merged.life_history.append(section.duplicate(true))
		merged.revision=int(previous.get("revision",1))+(1 if merged.life_history.size()!=previous.life_history.size() else 0)
	# Strip noncanonical extensions from remote data, including telemetry.
	var safe:={}
	for key in ["version","revision","identity","life_history","personality","communication","traits","knowledge","voice","compact_core","trait_evidence","subjects","design_specification","trait_constraints","established_biography","generation","provenance"]:
		if merged.has(key):safe[key]=merged[key]
	safe.version=VERSION
	if not safe.identity.has("origin_population") and _digest(incoming.identity.get("origin_population")):safe.identity.origin_population=incoming.identity.origin_population
	dossiers[id]=safe
	_projection_cache.erase(id)
	dirty=true
	var saved:=save()
	if saved!=OK:
		if previous.is_empty():dossiers.erase(id)
		else:dossiers[id]=previous
		return {"ok":false,"error":"Contributed dossier could not be saved."}
	return {"ok":true,"id":id}
