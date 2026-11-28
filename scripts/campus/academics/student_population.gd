extends RefCounted
## The host owns the campus roster. Indices are migration IDs, not classroom
## slots: saved people keep their identity and can attend only one live class.
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const Dossiers=preload("res://scripts/campus/academics/character_dossier_store.gd")
const Programs=preload("res://scripts/campus/academics/academic_programs.gd")
const VERSION:=4
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
var requested_courses: Dictionary={}
var contribution_sources: Dictionary={}
var reconciliation_conflicts: Array=[]
var index: Dictionary={}
var _selection_serial:=0


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
	index.clear()
	requested_courses.clear()
	contribution_sources.clear()
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
			var d:=Dossiers.summary(str(id))
			if d.get("identity",{}).get("role")=="student" and not people.has(id):
				people[id]=_light_profile({"id":id,"role":"student"},d) if d.get("generation",{}).get("status")=="complete" else Dossiers.project({"id":id,"role":"student","subjects":[],"lines":{}})
				if people[id].is_empty():people.erase(id);continue
				if _legacy_identity(str(id)):next_index=maxi(next_index,int(str(id).trim_prefix("campus_student_"))+1)
				dirty=true
	for id in people:
		var entry:=Dossiers.summary(str(id))
		if entry.is_empty():
			Dossiers.ensure(people[id])
			entry=Dossiers.summary(str(id))
		if entry.get("generation",{}).get("status")=="complete":
			if not people[id].get("dossier_ref",false):dirty=true
			people[id]=_light_profile(people[id],entry)
		_stamp_identity(people[id])
		index[id]=_index_entry(people[id])
	if not Dossiers.host_identity.is_empty() and Dossiers.dirty: Dossiers.save()
	ensure_size(maxi(INITIAL_COUNT,people.size()))
	if dirty and not persistence_blocked:save_population()
	return not loaded.is_empty()

func ensure_size(count: int) -> void:
	# Demand is satisfied by CharacterDossierGeneration in the background.
	requested_size=clampi(maxi(requested_size,count),0,MAX_RESIDENTS)

func reserve_identity() -> String:
	if profile_blocked or persistence_blocked or people.size()>=MAX_RESIDENTS:return ""
	# 128 random bits are independent of names, device counters and host changes.
	for _attempt in 8:
		var id:="campus_student_"+Crypto.new().generate_random_bytes(16).hex_encode()
		if people.has(id) or Dossiers.dossiers.has(id) or Dossiers.jobs.has(id):continue
		next_index+=1
		dirty=true
		if save_population()!=OK:return ""
		return id
	return ""

func generation_seed(id: String) -> Dictionary:
	var course:=""
	for candidate in requested_courses:
		if int(requested_courses[candidate])>0:course=str(candidate);break
	var program:=Programs.for_course(course,id.hash())
	return {"identity":{"id":id,"role":"student","program":program,"origin_population":_host_profile.sha256_text()}, "subjects":Programs.courses_for(program),
		"design_specification":"Create a distinct adult campus student enrolled in %s. Their enrolled courses are %s. Keep this program and stable ID. Develop their complete coherent life, independent personality, speech, knowledge, appearance and permanent vocal characteristics. No official marks are generated."%[program,", ".join(Programs.courses_for(program))]}

func import_generated(person: Dictionary) -> bool:
	if profile_blocked or persistence_blocked:return false
	var id:=str(person.get("id",""))
	if not valid_identity(id):return false
	var d:=Dossiers.get_dossier(id)
	if d.get("generation",{}).get("status")!="complete" or d.get("identity",{}).get("role")!="student":return false
	if not people.has(id) and people.size()>=MAX_RESIDENTS:return false
	var previous: Dictionary=people.get(id,{}).duplicate(true)
	people[id]=Dossiers.project(person)
	# Refreshing a completed dossier must not discard attendance or ownership.
	for key in ["origin_population","persistent_id","attendance","profile_lineage","newly_generated","learning","learning_weeks"]:
		if previous.has(key):people[id][key]=previous[key].duplicate(true) if previous[key] is Dictionary or previous[key] is Array else previous[key]
	_stamp_identity(people[id])
	if people[id].get("dossier_status","")=="complete":people[id]=_light_profile(people[id],Dossiers.summary(id))
	index[id]=_index_entry(people[id])
	for course in Programs.courses_for(str(people[id].get("program",""))):
		if requested_courses.has(course):requested_courses[course]=maxi(0,int(requested_courses[course])-1)
	if _legacy_identity(id):next_index=maxi(next_index,int(id.trim_prefix("campus_student_"))+1)
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
			if id.begins_with("campus_student_") and _legacy_identity(id):
				var index:=int(id.trim_prefix("campus_student_"))
				if index<LEGACY_COUNT and index not in indices:indices.append(index)
	return indices

func available(excluded: Dictionary,count: int,seed_value: int,course: String="",participants: Array=[]) -> Array:
	if profile_blocked:return []
	count=clampi(count,0,6)
	# Filtering and weighting read index fields only; complete dossier projection
	# is reserved for the selected identities below.
	for id in people:index[id]=_index_entry(people[id])
	var candidates:=index.keys().filter(func(id):return people.has(id) and not excluded.has(id) and Programs.eligible(index[id],course))
	if candidates.size()<count:
		ensure_size(people.size()+count-candidates.size())
		if not course.is_empty():requested_courses[course]=maxi(int(requested_courses.get(course,0)),count-candidates.size())
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var result: Array=[]
	_selection_serial+=1
	while not candidates.is_empty() and result.size()<count:
		var weights:=[]
		var total:=0.
		for id in candidates:
			var entry: Dictionary=index[id]
			# Familiar faces recur without monopolising every class. No remote
			# AI call, clock comparison or full biography is needed for selection.
			var weight:=1.+minf(2.,float(entry.appearances)*.15)
			weight*=.65+float(entry.academic_motivation)*.7
			if str(entry.last_course)==course:weight*=.85
			for identity in participants:
				if str(identity).sha256_text() in entry.familiar_players:weight+=.35
			total+=weight;weights.append(total)
		var pick:=rng.randf()*total
		var selected:=0
		while selected<weights.size()-1 and pick>float(weights[selected]):selected+=1
		var id: String=candidates.pop_at(selected)
		var selected_profile:=profile_for(id)
		if not selected_profile.is_empty():result.append(selected_profile)
	# A slowly growing reserve introduces occasional new eligible students;
	# existing biographies are never regenerated to satisfy this demand.
	if not course.is_empty() and count>0 and people.size()<MAX_RESIDENTS and rng.randf()<.18:
		requested_courses[course]=maxi(1,int(requested_courses.get(course,0)))
		ensure_size(people.size()+1)
	if dirty:save_population()
	return result

func record_attendance(id: String,course: String,activity_id: String,participants: Array=[]) -> void:
	if not people.has(id) or course not in Programs.COURSES or activity_id.is_empty():return
	var person: Dictionary=people[id]
	var attendance: Dictionary=person.get_or_add("attendance",{"count":0,"events":[],"courses":{},"familiar_players":[]})
	var event:=activity_id.sha256_text().left(32)
	if event in attendance.get("events",[]):return
	attendance.events=attendance.get("events",[])
	attendance.events.append(event)
	if attendance.events.size()>128:attendance.events.pop_front()
	attendance.count=mini(1000000,int(attendance.get("count",0))+1)
	attendance.last_course=course
	attendance.courses=attendance.get("courses",{})
	attendance.courses[course]=mini(1000000,int(attendance.courses.get(course,0))+1)
	attendance.familiar_players=attendance.get("familiar_players",[])
	for player in participants:
		var token:=str(player).sha256_text()
		if token not in attendance.familiar_players and attendance.familiar_players.size()<32:attendance.familiar_players.append(token)
	person.newly_generated=false
	index[id]=_index_entry(person)
	dirty=true
	save_population()

func profile_for(id: String) -> Dictionary:
	if not people.has(id):return {}
	_stamp_identity(people[id])
	index[id]=_index_entry(people[id])
	var person:=Dossiers.project(people[id])
	if person.is_empty():return {}
	_stamp_identity(person)
	person.eligible_courses=Programs.eligible_courses(person)
	person.appearances=int(person.get("attendance",{}).get("count",0))
	person.persistence_status="blocked" if persistence_blocked else "saved"
	return person

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
	if not (version is float or version is int) or not is_finite(float(version)) or float(version) not in [1.,2.,3.,float(VERSION)]:return {}
	var roster: Variant=parsed.get("people")
	if not roster is Dictionary or roster.size()>MAX_RESIDENTS:return {}
	var last_index:=-1
	for id in roster:
		var suffix:=str(id).trim_prefix("campus_student_")
		if not valid_identity(str(id)):return {}
		var index:=int(suffix) if _legacy_identity(str(id)) else posmod(str(id).hash(),MAX_RESIDENTS)
		if _legacy_identity(str(id)) and (index<0 or index>MAX_RESIDENTS*4):return {}
		var person: Variant=roster[id]
		if person is Dictionary and not _valid_metadata(person):return {}
		if not person is Dictionary or str(person.get("id",""))!=id or person.get("role","")!="student":return {}
		if not person.get("traits") is Dictionary or not person.get("name") is String:return {}
		if str(person.name).is_empty() or str(person.name).length()>80:return {}
		for value in person.traits.values():
			if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0. or float(value)>1.:return {}
		if person.get("dossier_ref",false):
			if float(version)<4. or person.get("dossier_ref")!=true or not person.get("program") is String or person.program.is_empty() or person.program.length()>160:return {}
			if person.get("dossier_status")!="complete" or not person.get("dossier_revision") is float and not person.get("dossier_revision") is int:return {}
			if not is_finite(float(person.dossier_revision)) or float(person.dossier_revision)<1. or float(person.dossier_revision)>1000000000.:return {}
			if _legacy_identity(str(id)):last_index=maxi(last_index,index)
			continue
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
		if _legacy_identity(str(id)):last_index=maxi(last_index,index)
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

static func valid_identity(id: String) -> bool:
	if not id.begins_with("campus_student_") or id.length()>64:return false
	var suffix:=id.trim_prefix("campus_student_")
	if _legacy_identity(id):return int(suffix)>=0 and int(suffix)<=MAX_RESIDENTS*4
	if suffix.length()!=32:return false
	for character in suffix:
		if character not in "0123456789abcdef":return false
	return true

func _stamp_identity(person: Dictionary) -> void:
	var id:=str(person.get("id",""))
	if not person.has("origin_population"):person.origin_population=_host_profile.sha256_text()
	if not person.has("persistent_id"):
		person.persistent_id="campus_student_"+(str(person.origin_population)+":"+id).sha256_text().left(32) if _legacy_identity(id) else id
	if not person.has("attendance"):person.attendance={"count":0,"events":[],"courses":{},"familiar_players":[]}
	if not person.has("enrollment"):
		person.enrollment={}
		for course in Programs.courses_for(str(person.get("program",""))):person.enrollment[course]="enrolled"
	if not person.has("newly_generated"):person.newly_generated=int(person.attendance.get("count",0))==0

static func _light_profile(profile: Dictionary,entry: Dictionary) -> Dictionary:
	# Full generated biographies/personality/examples have one saved authority.
	# Population rows retain only index data and evolving attendance/skills.
	var result:={"dossier_ref":true,"dossier_revision":int(entry.get("revision",1)),"dossier_status":str(entry.get("generation",{}).get("status","complete")),"subjects":entry.get("subjects",[]).duplicate(),"traits":entry.get("traits",{}).duplicate(true)}
	for key in ["id","name","age","role","program"]:result[key]=entry.get("identity",{}).get(key,profile.get(key,""))
	for key in ["origin_population","persistent_id","attendance","profile_lineage","newly_generated","enrollment","learning","learning_weeks","created_at"]:
		if profile.has(key):result[key]=profile[key].duplicate(true) if profile[key] is Dictionary or profile[key] is Array else profile[key]
	if not result.has("origin_population") and entry.get("identity",{}).has("origin_population"):result.origin_population=entry.identity.origin_population
	return result

func _index_entry(person: Dictionary) -> Dictionary:
	var attendance: Dictionary=person.get("attendance",{})
	return {"id":str(person.get("persistent_id",person.id)),"local_id":str(person.id),"name":str(person.name),"program":str(person.get("program","")),"courses":Programs.eligible_courses(person),"origin_population":str(person.get("origin_population","")),"revision":int(person.get("dossier_revision",1)),"progress_digest":_digest({"learning":person.get("learning",{}),"weeks":person.get("learning_weeks",{})}),"appearances":int(attendance.get("count",0)),"academic_motivation":float(person.get("traits",{}).get("academic_motivation",.5)),"enrollment":person.get("enrollment",{}).duplicate(true),"last_course":str(attendance.get("last_course","")),"familiar_players":attendance.get("familiar_players",[]).duplicate()}

func local_id(persistent_id: String) -> String:
	if people.has(persistent_id):return persistent_id
	for id in index:
		if str(index[id].id)==persistent_id:return str(id)
	return ""

func manifest(offset:=0,limit:=32) -> Array:
	var result:=[]
	var ids:=people.keys()
	ids.sort()
	for id in ids.slice(maxi(0,offset),maxi(0,offset)+clampi(limit,1,32)):
		_stamp_identity(people[id])
		index[id]=_index_entry(people[id])
		var entry: Dictionary=index[id].duplicate(true)
		for field in ["local_id","academic_motivation","enrollment","last_course","familiar_players"]:entry.erase(field)
		result.append(entry)
	return result

func export_person(persistent_id: String) -> Dictionary:
	var id:=local_id(persistent_id)
	if id.is_empty():return {}
	var person:=profile_for(id)
	var dossier:=Dossiers.get_dossier(id)
	if dossier.is_empty():return {}
	# The identity dossier contains the person's fictional canon only. Host
	# conversations, player grades and API account data are never population data.
	dossier.identity.id=persistent_id
	for field in ["generation","provenance"]:
		dossier[field]={"status":"complete" if person.get("dossier_status")=="complete" else "needs_expansion","source":"contributed_identity"} if field=="generation" else {"source":"contributed_identity","history_kind":"fictional"}
	return {"version":1,"id":persistent_id,"origin_population":str(person.origin_population),"revision":int(dossier.get("revision",1)),"dossier":dossier,"enrollment":person.get("enrollment",{}).duplicate(true),"learning":person.get("learning",{}).duplicate(true),"learning_weeks":person.get("learning_weeks",{}).duplicate(true),"attendance":{"count":int(person.attendance.get("count",0)),"events":person.attendance.get("events",[]).duplicate(),"courses":person.attendance.get("courses",{}).duplicate(true)},"digest":_digest(dossier)}

func import_person(payload: Dictionary,source_peer:=0) -> Dictionary:
	if profile_blocked or persistence_blocked:return {"ok":false,"error":"Local population storage is unavailable."}
	if JSON.stringify(payload).to_utf8_buffer().size()>300000:return {"ok":false,"error":"Profile exceeds size limit."}
	var id:=str(payload.get("id",""))
	var origin:=str(payload.get("origin_population",""))
	if payload.get("version")!=1 or not valid_identity(id) or origin.length()!=64 or not payload.get("dossier") is Dictionary:return {"ok":false,"error":"Invalid population record."}
	for character in origin:
		if character not in "0123456789abcdef":return {"ok":false,"error":"Invalid origin."}
	if not _valid_learning(payload.get("learning",{}),.35,false) or not _valid_learning(payload.get("learning_weeks",{}),.25,true):return {"ok":false,"error":"Invalid NPC learning record."}
	if payload.has("attendance") and not _valid_metadata({"attendance":payload.attendance}):return {"ok":false,"error":"Invalid NPC attendance record."}
	if payload.has("enrollment") and not _valid_metadata({"enrollment":payload.enrollment}):return {"ok":false,"error":"Invalid NPC enrollment record."}
	var incoming: Dictionary=payload.dossier.duplicate(true)
	if not incoming.get("identity") is Dictionary:return {"ok":false,"error":"Invalid dossier identity."}
	if incoming.identity.get("id")!=id or incoming.identity.get("role")!="student":return {"ok":false,"error":"Identity mismatch."}
	if _digest(incoming)!=str(payload.get("digest","")):return {"ok":false,"error":"Profile digest mismatch."}
	var existing:=local_id(id)
	if existing.is_empty():existing=id
	if not people.has(existing) and people.size()>=MAX_RESIDENTS:return {"ok":false,"error":"Local population is full."}
	if people.has(existing) and str(people[existing].get("origin_population",""))!=origin:return {"ok":false,"error":"Conflicting origin; preserved established identity."}
	incoming.identity.id=existing
	incoming.identity.origin_population=origin
	var merged:=Dossiers.import_identity(incoming)
	if not merged.get("ok",false):
		if merged.get("conflict",false):
			reconciliation_conflicts.append({"id":id,"error":str(merged.error)})
			if reconciliation_conflicts.size()>64:reconciliation_conflicts.pop_front()
		return merged
	var seed: Dictionary=people.get(existing,{"id":existing,"role":"student","subjects":[],"lines":{}})
	var person:=Dossiers.project(seed)
	person.origin_population=origin;person.persistent_id=id;person.newly_generated=false
	if not person.has("enrollment") and payload.has("enrollment"):person.enrollment=payload.enrollment.duplicate(true)
	for field in ["learning","learning_weeks"]:
		var progress: Dictionary=person.get_or_add(field,{})
		for course in payload.get(field,{}):progress[course]=maxf(float(progress.get(course,0.)),float(payload[field][course]))
	_stamp_identity(person)
	var attendance: Variant=payload.get("attendance",{})
	if attendance is Dictionary:
		var events: Array=person.attendance.get("events",[])
		var incoming_events: Variant=attendance.get("events",[])
		if incoming_events is Array and incoming_events.size()<=128:
			for event in incoming_events:
				if event is String and event.length()==32 and event not in events:events.append(event)
			while events.size()>128:events.pop_front()
		person.attendance.events=events
		person.attendance.count=maxi(int(person.attendance.get("count",0)),maxi(events.size(),int(attendance.get("count",0))))
		var courses: Dictionary=person.attendance.get_or_add("courses",{})
		for course in attendance.get("courses",{}):courses[course]=maxi(int(courses.get(course,0)),int(attendance.courses[course]))
	people[existing]=person
	if person.get("dossier_status","")=="complete":people[existing]=_light_profile(person,Dossiers.summary(existing))
	index[existing]=_index_entry(person)
	if source_peer>0:contribution_sources[id]=source_peer
	dirty=true
	var saved:=save_population()
	return {"ok":saved==OK,"id":existing,"persistent_id":id,"error":"Could not save contributed identity." if saved!=OK else ""}

static func _digest(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)),"",true).sha256_text()

static func _legacy_identity(id: String) -> bool:
	var suffix:=id.trim_prefix("campus_student_")
	return id.begins_with("campus_student_") and suffix.length()<32 and suffix.is_valid_int()

static func _valid_metadata(person: Dictionary) -> bool:
	if person.has("origin_population"):
		if not person.origin_population is String or person.origin_population.length()!=64:return false
		for character in person.origin_population:
			if character not in "0123456789abcdef":return false
	if person.has("persistent_id") and (not person.persistent_id is String or not valid_identity(person.persistent_id)):return false
	if person.has("enrollment"):
		if not person.enrollment is Dictionary or person.enrollment.size()>Programs.COURSES.size():return false
		for course in person.enrollment:
			if course not in Programs.COURSES or person.enrollment[course] not in ["enrolled","eligible","withdrawn","suspended","completed_only"]:return false
	if not _valid_learning(person.get("learning",{}),.35,false) or not _valid_learning(person.get("learning_weeks",{}),.25,true):return false
	if not person.has("attendance"):return true
	if not person.attendance is Dictionary:return false
	var attendance: Dictionary=person.attendance
	for field in ["count"]:
		var value: Variant=attendance.get(field,0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0. or float(value)>1000000.:return false
	if not attendance.get("events",[]) is Array or attendance.get("events",[]).size()>128:return false
	for event in attendance.get("events",[]):
		if not event is String or event.length()!=32:return false
	if not attendance.get("familiar_players",[]) is Array or attendance.get("familiar_players",[]).size()>32:return false
	for player in attendance.get("familiar_players",[]):
		if not player is String or player.length()!=64:return false
	if not attendance.get("courses",{}) is Dictionary or attendance.get("courses",{}).size()>Programs.COURSES.size():return false
	for course in attendance.get("courses",{}):
		var value: Variant=attendance.courses[course]
		if course not in Programs.COURSES or not (value is int or value is float) or not is_finite(float(value)) or float(value)<0. or float(value)>1000000.:return false
	return true

func record_learning(id: String,course: String,value: float,week:=0,concept_gain:=0.,persist:=true) -> Error:
	if profile_blocked or persistence_blocked:return ERR_FILE_CORRUPT
	if not people.has(id) or course not in Programs.COURSES or not is_finite(value) or not is_finite(concept_gain) or week<0 or week>52:return ERR_INVALID_PARAMETER
	var learned_courses: Dictionary=people[id].get_or_add("learning",{})
	learned_courses[course]=maxf(float(learned_courses.get(course,0.)),clampf(value,0.,.35))
	if week>0:
		var key:=course+":"+str(week)
		var learned_weeks: Dictionary=people[id].get_or_add("learning_weeks",{})
		learned_weeks[key]=maxf(float(learned_weeks.get(key,0.)),clampf(concept_gain,0.,.25))
	dirty=true
	index[id]=_index_entry(people[id])
	return save_population() if persist else OK

func learned(id: String,course: String,week:=0) -> float:
	if not people.has(id) or course not in Programs.COURSES:return 0.
	if week>0:return clampf(float(people[id].get("learning_weeks",{}).get(course+":"+str(week),0.)),0.,.25)
	return clampf(float(people[id].get("learning",{}).get(course,0.)),0.,.35)

static func _valid_learning(progress: Variant,maximum: float,weekly: bool) -> bool:
	if not progress is Dictionary or progress.size()>(260 if weekly else Programs.COURSES.size()):return false
	for key in progress:
		if not key is String:return false
		var course:=str(key).get_slice(":",0) if weekly else str(key)
		if course not in Programs.COURSES:return false
		if weekly:
			var week:=str(key).get_slice(":",1)
			if str(key).count(":")!=1 or not week.is_valid_int() or int(week)<1 or int(week)>52:return false
		var value: Variant=progress[key]
		if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0 or float(value)>maximum:return false
	return true

func import_progress(payload: Dictionary) -> Dictionary:
	var id:=local_id(str(payload.get("id","")))
	if id.is_empty() or profile_blocked or persistence_blocked:return {"ok":false,"error":"A complete local identity is required before an update."}
	var person: Dictionary=people[id]
	if str(payload.get("origin_population",""))!=str(person.get("origin_population","")):return {"ok":false,"error":"Progress origin does not match the saved identity."}
	if not _valid_learning(payload.get("learning",{}),.35,false) or not _valid_learning(payload.get("learning_weeks",{}),.25,true):return {"ok":false,"error":"Invalid NPC learning update."}
	if payload.has("attendance") and not _valid_metadata({"attendance":payload.attendance}):return {"ok":false,"error":"Invalid attendance update."}
	for field in ["learning","learning_weeks"]:
		var progress: Dictionary=person.get_or_add(field,{})
		for course in payload.get(field,{}):progress[course]=maxf(float(progress.get(course,0.)),float(payload[field][course]))
	var attendance: Dictionary=person.get_or_add("attendance",{"count":0,"events":[],"courses":{},"familiar_players":[]})
	var events: Array=attendance.get_or_add("events",[])
	for event in payload.get("attendance",{}).get("events",[]):
		if event not in events:events.append(event)
	while events.size()>128:events.pop_front()
	attendance.count=maxi(int(attendance.get("count",0)),int(payload.get("attendance",{}).get("count",0)))
	for course in payload.get("attendance",{}).get("courses",{}):
		var courses: Dictionary=attendance.get_or_add("courses",{})
		courses[course]=maxi(int(courses.get(course,0)),int(payload.attendance.courses[course]))
	index[id]=_index_entry(person);dirty=true
	return {"ok":save_population()==OK,"id":id,"persistent_id":str(person.persistent_id)}
