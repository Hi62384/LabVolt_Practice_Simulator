extends RefCounted
## One host-scoped authority. Getters return copies; inspector reads never create
## a relationship, generate a character, or count as a social event.
const Dossier = preload("res://scripts/campus/academics/character_dossier.gd")
const VERSION := 1
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
	return OK

static func ensure(profile: Dictionary) -> Dictionary:
	var id := str(profile.get("id", ""))
	if id.is_empty(): return {}
	if not dossiers.has(id):
		if dossiers.size() >= MAX_IDENTITIES: return Dossier.migrate(profile)
		dossiers[id] = Dossier.migrate(profile)
		dirty = true
	return dossiers[id].duplicate(true)

static func project(profile: Dictionary) -> Dictionary:
	var id := str(profile.get("id",""))
	if not dossiers.has(id): ensure(profile)
	if not dossiers.has(id): return profile.duplicate(true)
	var d: Dictionary = dossiers[id]
	var content_revision := int(d.get("revision",1))
	if not _projection_cache.has(id) or int(_projection_cache[id].revision)!=content_revision:
		_projection_cache[id]={"revision":content_revision,"profile":Dossier.project(profile,d)}
	return _projection_cache[id].profile.duplicate(true)

static func get_dossier(id: String) -> Dictionary:
	return dossiers.get(id, {}).duplicate(true)

static func preserve_biography(id: String, biography: Dictionary) -> void:
	# One-time migration only. Developing facts remain in CharacterLifeMemory.
	if not dossiers.has(id): return
	var d: Dictionary = dossiers[id]
	var established: Dictionary = d.get_or_add("established_biography", {})
	for key in biography:
		if not biography[key] is String or biography[key].strip_edges().is_empty() or established.has(key): continue
		established[key] = biography[key]
		d.life_history.append({"id": "preserved_" + str(key), "title": str(key).replace("_", " ").capitalize(), "text": biography[key], "topics": [str(key)], "entities": [], "chronology": "Established before dossier migration", "source": "migrated_fiction"})
		dirty = true
		d.revision = int(d.get("revision",1))+1

static func queue(profile: Dictionary, priority := 0) -> bool:
	if blocked: return false
	var d := ensure(profile)
	var id := str(profile.get("id", ""))
	if id.is_empty() or d.get("generation", {}).get("status") == "complete": return false
	if jobs.has(id):
		jobs[id].priority = maxi(int(jobs[id].get("priority", 0)), priority)
		return false
	jobs[id] = {"id": id, "kind": "expand", "status": "queued", "priority": priority, "attempts": 0, "stage": "full", "draft": {}, "issues": [], "invalid_sections": [], "created_at": int(Time.get_unix_time_from_system()), "retry_at": 0, "requests": 0, "measurement": {}, "last_error": ""}
	dirty = true
	return true

static func queue_student(id: String) -> bool:
	if blocked or jobs.has(id) or dossiers.has(id) or jobs.size() >= MAX_IDENTITIES: return false
	jobs[id] = {"id": id, "kind": "student", "status": "queued", "priority": 1, "attempts": 0, "stage": "full", "draft": {}, "issues": [], "invalid_sections": [], "created_at": int(Time.get_unix_time_from_system()), "retry_at": 0, "requests": 0, "measurement": {}, "last_error": ""}
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
	if dossiers.has(id): seed=dossiers[id].duplicate(true)
	var validation := Dossier.validate(candidate, seed)
	if not validation.ok: return validation
	var previous: Dictionary = dossiers.get(id, {}).duplicate(true)
	var d := {}
	for field in ["identity", "life_history", "personality", "communication", "traits", "knowledge", "voice", "compact_core", "trait_evidence"]:
		d[field] = candidate[field].duplicate(true) if candidate[field] is Dictionary or candidate[field] is Array else candidate[field]
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
	var serialized := JSON.stringify({"version": VERSION, "dossiers": dossiers, "jobs": jobs})
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
	if not parsed is Dictionary or parsed.get("version") != VERSION or not parsed.get("dossiers") is Dictionary or not parsed.get("jobs") is Dictionary: return {}
	if parsed.dossiers.size() > MAX_IDENTITIES or parsed.jobs.size() > MAX_IDENTITIES: return {}
	for id in parsed.dossiers:
		var d: Variant = parsed.dossiers[id]
		if not d is Dictionary or not d.get("identity") is Dictionary or d.identity.get("id") != id: return {}
		for field in ["personality", "communication", "traits", "knowledge", "voice", "generation"]:
			if not d.get(field) is Dictionary: return {}
		if not d.get("life_history") is Array or not d.communication.get("examples") is Array: return {}
		if not Dossier.validate(d,{},false).ok: return {}
		for value in d.traits.values():
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0. or float(value) > 1.: return {}
	for id in parsed.jobs:
		var job: Variant = parsed.jobs[id]
		if not job is Dictionary or job.get("id") != id or job.get("status") not in ["queued", "running", "retry", "failed", "complete"] or not job.get("draft", {}) is Dictionary: return {}
	return parsed

static func diagnostics(id := "") -> Dictionary:
	var pending := 0
	var complete := 0
	for d in dossiers.values():
		if d.get("generation", {}).get("status") == "complete": complete += 1
	for job in jobs.values():
		if job.get("status") in ["queued", "running", "retry"]: pending += 1
	var job: Dictionary = jobs.get(id, {})
	var state: Dictionary = dossiers.get(id, {}).get("generation", {})
	return {"host_scoped": not host_identity.is_empty(), "identity_count": dossiers.size(), "complete_count": complete, "pending_count": pending, "selected_status": str(job.get("status", state.get("status", "not_created"))), "last_error": str(job.get("last_error", "")), "attempts": int(job.get("attempts", 0)), "requests": int(job.get("requests", 0)), "measurement": job.get("measurement", state.get("measurement", {})).duplicate(true), "persistence_state": "blocked" if blocked else "unsaved" if dirty else "saved", "last_save_error": last_save_error, "last_load_error": last_load_error, "recovered_backup": recovered_backup, "storage_bytes": _storage_bytes()}

static func _storage_bytes() -> int:
	if path.is_empty(): return 0
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:return 0
	var bytes := file.get_length()
	file.close()
	return bytes
