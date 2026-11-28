extends RefCounted
## The host owns the campus roster. Indices are migration IDs, not classroom
## slots: saved people keep their identity and can attend only one live class.
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Dossiers=preload("res://scripts/campus/academics/character_dossier_store.gd")
const VERSION:=2
const LEGACY_COUNT:=12
const INITIAL_COUNT:=12
const MAX_RESIDENTS:=4096
const MAX_BYTES:=134217728
const MAX_CACHED_PROFILES:=8
const MAX_CACHED_BYTES:=134217728
var path:="user://campus_student_population.json"
var people: Dictionary={}
var next_index:=0
var requested_size:=INITIAL_COUNT
var dirty:=false
var last_save_error:=OK
var last_load_error:=OK
var recovered_backup:=false
var profile_blocked:=false
var persistence_blocked:=false
var preserved_corrupt_paths: Array[String]=[]
var last_profile_cache_error:=OK
var _host_profile:=""
var _loaded_path:=""
var _unsaved_profiles: Dictionary={}

func set_host_profile(profile_id: String) -> Error:
	if profile_id.is_empty() or profile_id.length()>128:
		profile_blocked=true
		return ERR_INVALID_PARAMETER
	var selected:=Memory.profile_prefix(profile_id)+".population.json"
	if selected==path:
		profile_blocked=false
		return OK
	# A damaged save may have a useful session roster. Keep it under its owner
	# when changing hosts; never make a new host inherit the old host's people.
	var needs_cache:=false
	# Recheck a loaded roster even when clean: the files may have been damaged
	# since the last read, and its still-known identities must not be discarded.
	if dirty or (not _host_profile.is_empty() and _loaded_path==path and not people.is_empty()):
		profile_blocked=false
		var saved:=save_population()
		if saved!=OK:
			if saved==ERR_FILE_CORRUPT and not _host_profile.is_empty():needs_cache=true
			else:
				profile_blocked=true
				return saved
	profile_blocked=true
	var error:=DirAccess.make_dir_recursive_absolute("user://character_memory")
	if error!=OK:return error
	# A missing primary with an existing backup is an existing campus. Legacy
	# migration must not replace that host's saved identities.
	if not _exists(selected) and not _exists(selected+".bak"):
		error=_migrate_legacy(profile_id,selected)
		if error!=OK:return error
	if needs_cache:
		error=_cache_unsaved_profile(selected)
		if error!=OK:return error
	else:_unsaved_profiles.erase(path)
	path=selected
	_host_profile=profile_id
	_loaded_path=""
	people.clear()
	next_index=0
	dirty=false
	persistence_blocked=false
	last_save_error=OK
	last_load_error=OK
	recovered_backup=false
	preserved_corrupt_paths.clear()
	profile_blocked=false
	var dossier_error:=Dossiers.set_host_profile(profile_id)
	if dossier_error!=OK and dossier_error!=ERR_FILE_CORRUPT:
		profile_blocked=true
		return dossier_error
	if _unsaved_profiles.has(selected):
		var state: Dictionary=_unsaved_profiles[selected].state
		people=state.people;next_index=state.next_index;dirty=state.dirty
		persistence_blocked=state.persistence_blocked;last_save_error=state.last_save_error;last_load_error=state.last_load_error
		recovered_backup=state.recovered_backup;preserved_corrupt_paths.assign(state.preserved_corrupt_paths)
		_loaded_path=path
		_unsaved_profiles.erase(selected)
	return OK

func _migrate_legacy(profile_id: String,selected: String) -> Error:
	var legacy:="user://campus_student_population.json"
	if not _exists(legacy) and not _exists(legacy+".bak"):return OK
	if not claim_legacy(profile_id):return OK
	var source:=legacy if not _read(legacy).is_empty() else legacy+".bak"
	if not _read(source).is_empty():return DirAccess.copy_absolute(source,selected)
	# The first owner's damaged legacy data still exists. Copy its evidence into
	# the namespace so loading fails explicitly instead of saving replacements.
	for suffix in ["",".bak"]:
		if not _exists(legacy+suffix):continue
		var error:=DirAccess.copy_absolute(legacy+suffix,selected+suffix)
		if error!=OK:return error
	return OK

func _cache_unsaved_profile(incoming_path: String) -> Error:
	var state:={"people":people,"next_index":next_index,"dirty":dirty,"persistence_blocked":persistence_blocked,
		"last_save_error":last_save_error,"last_load_error":last_load_error,"recovered_backup":recovered_backup,
		"preserved_corrupt_paths":preserved_corrupt_paths}
	var bytes:=JSON.stringify(state).to_utf8_buffer().size()
	var total:=bytes
	var count:=0
	for cached_path in _unsaved_profiles:
		# Returning consumes the incoming entry, even when the cache is full.
		if cached_path in [path,incoming_path]:continue
		count+=1;total+=int(_unsaved_profiles[cached_path].bytes)
	if count>=MAX_CACHED_PROFILES or total>MAX_CACHED_BYTES:
		last_profile_cache_error=ERR_OUT_OF_MEMORY
		return last_profile_cache_error
	_unsaved_profiles[path]={"state":state.duplicate(true),"bytes":bytes}
	last_profile_cache_error=OK
	return OK

static func claim_legacy(profile_id: String) -> bool:
	var marker:="user://character_memory/legacy_owner.txt"
	var owner:=FileAccess.get_file_as_string(marker).strip_edges() if FileAccess.file_exists(marker) else ""
	if not owner.is_empty():return owner==profile_id.sha256_text()
	if DirAccess.make_dir_recursive_absolute("user://character_memory")!=OK:return false
	var file:=FileAccess.open(marker+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(profile_id.sha256_text())
	file.flush()
	var error:=file.get_error()
	file.close()
	return error==OK and DirAccess.rename_absolute(marker+".tmp",marker)==OK

func load_population() -> bool:
	if profile_blocked:return false
	# Reconfiguration and host switching can call load again. Unsaved session
	# identities must survive, including a restored corruption fallback.
	if dirty and not _loaded_path.is_empty():
		if _loaded_path!=path:
			profile_blocked=true
			last_load_error=ERR_BUSY
		return false
	var same_path:=_loaded_path==path
	recovered_backup=false
	var loaded:=_read(path)
	if loaded.is_empty():
		loaded=_read(path+".bak")
		recovered_backup=not loaded.is_empty()
	persistence_blocked=loaded.is_empty() and (_exists(path) or _exists(path+".bak"))
	last_load_error=ERR_FILE_CORRUPT if persistence_blocked else OK
	last_save_error=last_load_error
	if not loaded.is_empty():
		people=loaded.people
		next_index=int(loaded.next_index)
		requested_size=clampi(int(loaded.get("requested_size",INITIAL_COUNT)),0,MAX_RESIDENTS)
		dirty=recovered_backup
	elif not same_path:
		people.clear()
		next_index=0
	_loaded_path=path
	if loaded.is_empty():dirty=true
	# Only reconstruct historical IDs that are evidenced by an older memory or
	# learning save. A fresh campus waits for AI-created students in the reserve;
	# it never silently creates generic replacements when the service is offline.
	if loaded.is_empty() and not persistence_blocked:
		for index in _legacy_indices():
			var id:="campus_student_%02d"%index
			if not people.has(id):
				people[id]=_create(index)
				dirty=true
			next_index=maxi(next_index,index+1)
	# A separately saved dossier is an existing identity, not a generic fallback.
	# Reuse it in a damaged population namespace without overwriting damaged bytes.
	if not _host_profile.is_empty() and Dossiers.host_identity==_host_profile:
		for id in Dossiers.dossiers:
			var d: Dictionary=Dossiers.dossiers[id]
			if d.get("identity",{}).get("role")=="student" and not people.has(id):
				people[id]=Dossiers.project({"id":id,"role":"student","subjects":[],"lines":{}})
				next_index=maxi(next_index,int(str(id).trim_prefix("campus_student_"))+1)
				dirty=true
	for id in people:
		people[id]=Dossiers.project(people[id])
	if not Dossiers.host_identity.is_empty() and Dossiers.dirty: Dossiers.save()
	ensure_size(maxi(INITIAL_COUNT,people.size()))
	if dirty and not persistence_blocked:save_population()
	return not loaded.is_empty()

func ensure_size(count: int) -> void:
	# Demand is satisfied by CharacterDossierGeneration in the background.
	requested_size=clampi(maxi(requested_size,count),0,MAX_RESIDENTS)

func reserve_identity() -> String:
	if profile_blocked or persistence_blocked or people.size()>=MAX_RESIDENTS:return ""
	while next_index<MAX_RESIDENTS*4:
		var id:="campus_student_%02d"%next_index
		next_index+=1
		if people.has(id) or Dossiers.dossiers.has(id) or Dossiers.jobs.has(id):continue
		dirty=true
		if save_population()!=OK:return ""
		return id
	return ""

func import_generated(person: Dictionary) -> bool:
	if profile_blocked or persistence_blocked:return false
	var id:=str(person.get("id",""))
	if not id.begins_with("campus_student_") or not id.trim_prefix("campus_student_").is_valid_int():return false
	var d:=Dossiers.get_dossier(id)
	if d.get("generation",{}).get("status")!="complete" or d.get("identity",{}).get("role")!="student":return false
	if not people.has(id) and people.size()>=MAX_RESIDENTS:return false
	var previous: Dictionary=people.get(id,{}).duplicate(true)
	people[id]=Dossiers.project(person)
	next_index=maxi(next_index,int(id.trim_prefix("campus_student_"))+1)
	dirty=true
	if save_population()!=OK:
		if previous.is_empty():people.erase(id)
		else:people[id]=previous
		return false
	return true

func _legacy_indices() -> Array:
	var indices: Array=[]
	var memory_path:=Memory.profile_prefix(_host_profile)+".json" if not _host_profile.is_empty() else Memory.MEMORY_PATH
	if FileAccess.file_exists(memory_path):
		var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(memory_path))
		if raw is Dictionary:
			var pattern:=RegEx.create_from_string("campus_student_([0-9]+)")
			for hit in pattern.search_all(JSON.stringify(raw)):
				var index:=int(hit.get_string(1))
				if index<LEGACY_COUNT and index not in indices:indices.append(index)
	var records:=ConfigFile.new()
	var learning_path:=Memory.profile_prefix(_host_profile)+".learning.cfg" if not _host_profile.is_empty() else "user://classmate_learning.cfg"
	if records.load(learning_path)==OK:
		for id in records.get_sections():
			if id.begins_with("campus_student_") and id.trim_prefix("campus_student_").is_valid_int():
				var index:=int(id.trim_prefix("campus_student_"))
				if index<LEGACY_COUNT and index not in indices:indices.append(index)
	return indices

func available(excluded: Dictionary,count: int,seed_value: int) -> Array:
	if profile_blocked:return []
	count=clampi(count,0,6)
	var candidates:=people.keys().filter(func(id):return not excluded.has(id))
	if candidates.size()<count:
		ensure_size(people.size()+count-candidates.size())
		candidates=people.keys().filter(func(id):return not excluded.has(id))
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var result: Array=[]
	while not candidates.is_empty() and result.size()<count:
		var id: String=candidates.pop_at(rng.randi_range(0,candidates.size()-1))
		result.append(Dossiers.project(people[id]))
	if dirty:save_population()
	return result

func profile_for(id: String) -> Dictionary:
	return Dossiers.project(people[id]) if people.has(id) else {}

func save_population() -> Error:
	if profile_blocked:
		last_save_error=ERR_UNAUTHORIZED
		return last_save_error
	if persistence_blocked:
		last_save_error=ERR_FILE_CORRUPT
		return last_save_error
	if not _loaded_path.is_empty() and _loaded_path!=path:
		last_save_error=ERR_BUSY
		return last_save_error
	# Check again before writing: either file can become corrupt after loading.
	var primary:=_read(path)
	var backup:=_read(path+".bak")
	if primary.is_empty() and backup.is_empty() and (_exists(path) or _exists(path+".bak")):
		persistence_blocked=true
		dirty=true
		last_save_error=ERR_FILE_CORRUPT
		return last_save_error
	for source in [path,path+".bak"]:
		if _exists(source) and (primary.is_empty() if source==path else backup.is_empty()):
			last_save_error=_preserve_corrupt(source)
			if last_save_error!=OK:return last_save_error
	var serialized:=JSON.stringify({"version":VERSION,"next_index":next_index,"requested_size":requested_size,"people":people})
	if serialized.to_utf8_buffer().size()>MAX_BYTES:
		last_save_error=ERR_OUT_OF_MEMORY
		return last_save_error
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:
		last_save_error=FileAccess.get_open_error()
		return last_save_error
	file.store_string(serialized)
	file.flush()
	last_save_error=file.get_error()
	file.close()
	if last_save_error!=OK:return last_save_error
	if _read(path+".tmp").is_empty():
		last_save_error=ERR_INVALID_DATA
		return last_save_error
	if not primary.is_empty():
		last_save_error=DirAccess.copy_absolute(path,path+".bak")
		if last_save_error!=OK:return last_save_error
	last_save_error=DirAccess.rename_absolute(path+".tmp",path)
	if last_save_error==OK:dirty=false
	return last_save_error

func _preserve_corrupt(source: String) -> Error:
	var digest:=FileAccess.get_sha256(source)
	if digest.is_empty():return ERR_FILE_CANT_READ
	var destination:=source+".corrupt-"+digest
	if _exists(destination):
		if FileAccess.get_sha256(destination)!=digest:return ERR_ALREADY_EXISTS
	else:
		var error:=DirAccess.copy_absolute(source,destination)
		if error!=OK:return error
		if FileAccess.get_sha256(destination)!=digest:return ERR_FILE_CORRUPT
	if destination not in preserved_corrupt_paths:preserved_corrupt_paths.append(destination)
	if preserved_corrupt_paths.size()>16:preserved_corrupt_paths.pop_front()
	return OK

static func _exists(source: String) -> bool:
	return FileAccess.file_exists(source) or DirAccess.dir_exists_absolute(source)

func diagnostics() -> Dictionary:
	return {"persistence_blocked":persistence_blocked,"profile_blocked":profile_blocked,
		"last_load_error":last_load_error,"last_save_error":last_save_error,"unsaved_data":dirty,
		"persistence_state":"blocked_unsaved" if persistence_blocked and dirty else ("blocked" if persistence_blocked or profile_blocked else ("unsaved" if dirty else "saved")),
		"recovered_backup":recovered_backup,"preserved_corrupt_paths":preserved_corrupt_paths.duplicate(),
		"cached_unsaved_profiles":_unsaved_profiles.size(),"profile_cache_error":last_profile_cache_error,
		"profile_cache_durable":false,"profile_scoped":not _host_profile.is_empty(),"ready_count":people.size(),"requested_size":requested_size,"generation_required":maxi(0,requested_size-people.size())}

func _read(source: String) -> Dictionary:
	var file:=FileAccess.open(source,FileAccess.READ)
	if file==null:return {}
	if file.get_length()>MAX_BYTES:
		file.close()
		return {}
	var json:=JSON.new()
	var decoded:=json.parse(file.get_as_text())
	file.close()
	if decoded!=OK:return {}
	var parsed: Variant=json.data
	if not parsed is Dictionary:return {}
	var version: Variant=parsed.get("version",0)
	if not (version is float or version is int) or not is_finite(float(version)) or float(version) not in [1.,float(VERSION)]:return {}
	var roster: Variant=parsed.get("people")
	if not roster is Dictionary or roster.size()>MAX_RESIDENTS:return {}
	var last_index:=-1
	for id in roster:
		var suffix:=str(id).trim_prefix("campus_student_")
		if not str(id).begins_with("campus_student_") or not suffix.is_valid_int():return {}
		var index:=int(suffix)
		if index<0 or index>MAX_RESIDENTS*4:return {}
		var person: Variant=roster[id]
		if not person is Dictionary or str(person.get("id",""))!=id or person.get("role","")!="student":return {}
		if not person.get("traits") is Dictionary or not person.get("name") is String:return {}
		if str(person.name).is_empty() or str(person.name).length()>80:return {}
		for value in person.traits.values():
			if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0. or float(value)>1.:return {}
		# Add new schema defaults without changing any saved identity or trait.
		var defaults:=Profiles.legacy_student(index)
		for key in defaults:
			if not person.has(key):person[key]=defaults[key]
			elif defaults[key] is Dictionary and not person[key] is Dictionary:return {}
			elif defaults[key] is Array and not person[key] is Array:return {}
			elif defaults[key] is String and not person[key] is String:return {}
			elif defaults[key] is float or defaults[key] is int:
				if not (person[key] is float or person[key] is int) or not is_finite(float(person[key])):return {}
		for key in defaults.traits:
			if not person.traits.has(key):person.traits[key]=defaults.traits[key]
		if not person.get("appearance") is Dictionary:person.appearance=_appearance(index)
		person.appearance=Toon.sanitize(person.appearance)
		last_index=maxi(last_index,index)
	var following_value: Variant=parsed.get("next_index",0)
	if not (following_value is float or following_value is int) or not is_finite(float(following_value)) or floorf(float(following_value))!=float(following_value):return {}
	var following:=int(following_value)
	if following<0 or following>MAX_RESIDENTS*4:return {}
	return {"people":roster,"next_index":maxi(following,last_index+1),"requested_size":clampi(int(parsed.get("requested_size",INITIAL_COUNT)),0,MAX_RESIDENTS)}

static func _create(index: int) -> Dictionary:
	var person:=Profiles.legacy_student(index)
	person.appearance=_appearance(index)
	person.created_at=int(Time.get_unix_time_from_system())
	return person

static func _appearance(index: int) -> Dictionary:
	var config:=Toon.defaults()
	config.name=Profiles.legacy_student(index).name
	if index<LEGACY_COUNT:
		config.hair=["Sweep","Curls","Crop","Bun"][index%4]
		config.skin=["c78e64","54382e","f3cbb1","a86c49"][index/3%4]
		config.top=["405f64","597d7a","675b77","754d41","789129","385c84"][index%6]
		return config
	var rng:=RandomNumberGenerator.new()
	rng.seed=("campus-appearance-%d"%index).hash()
	config.hair=Toon.HAIR[rng.randi_range(0,Toon.HAIR.size()-1)]
	config.outfit=Toon.OUTFITS[rng.randi_range(0,Toon.OUTFITS.size()-1)]
	config.skin=["c78e64","54382e","f3cbb1","a86c49","805037","deb08c"][rng.randi_range(0,5)]
	config.top=Color.from_hsv(rng.randf(),rng.randf_range(.2,.5),rng.randf_range(.3,.65)).to_html(false)
	config.accent=Color.from_hsv(rng.randf(),.3,.75).to_html(false)
	config.hair_color=["211f24","5a3f31","987550","4d3434","68747a"][rng.randi_range(0,4)]
	config.height=rng.randf_range(.92,1.1)
	config.build=rng.randf_range(.85,1.18)
	config.shoulders=rng.randf_range(.88,1.13)
	config.glasses=Toon.GLASSES[rng.randi_range(0,Toon.GLASSES.size()-1)] if rng.randf()<.3 else "None"
	config.freckles=rng.randf()<.25
	return Toon.sanitize(config)
