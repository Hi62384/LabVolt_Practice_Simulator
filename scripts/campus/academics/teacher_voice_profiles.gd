extends RefCounted
## Persistent OpenAI vocal identities. Legacy offline profiles below are only
## consumed when the host explicitly chooses the legacy offline provider.
const PATH := "res://assets/campus/faculty/voice_profiles.json"
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Design=preload("res://scripts/campus/academics/character_voice_design.gd")
const SCHEMA_VERSION := 1
const MAX_IDENTITIES := 8192
const PROMPT_VOICE_LIMIT := 100
const MAX_STORE_BYTES := 16777216
const AUDITION_MOODS := ["normal","sad","angry"]
const MAX_AUDITION_RUNS:=8
const AUDITION_ALLOWED:=["normal","happy","excited","amused","irritated","angry","extremely angry","sad","tired","disappointed","dismissive","embarrassed","bored","confused"]
const MAX_PROMPT_CHARS:=2000
static var store_path := "user://character_voices.json"
static var _loaded_path := ""
static var _state: Dictionary={}
static var _designs: Dictionary={}
static var _generation_claims: Dictionary={}
static var last_error: Error=OK

static func designs() -> Dictionary:
	if _designs.is_empty():
		var authored:=Design.authored()
		if authored.size()!=Roster.PEOPLE.size():return {}
		for id: String in Roster.PEOPLE:
			if not _valid_identity(authored.get(id,{}),id):return {}
		_designs=authored
	return _designs.duplicate(true)

static func scope_for(person: Dictionary) -> String:
	var scope:=str(person.get("voice_scope",""))
	return scope if not Roster.PEOPLE.has(str(person.get("id",""))) and scope.length()==64 and scope.is_valid_hex_number(false) else ""

static func _key(id: String,scope: String="") -> String:
	return id if scope.is_empty() or Roster.PEOPLE.has(id) else scope+":"+id

static func legacy_conflict(person: Dictionary) -> bool:
	if _load()!=OK:return false
	var id:=str(person.get("id",""))
	var key:=_key(id,scope_for(person))
	return key!=id and not _state.identities.has(key) and _state.identities.has(id)

static func identity(person: Dictionary) -> Dictionary:
	var id:=str(person.get("id",""))
	if id.is_empty() or id.length()>128 or person.get("identity_scope","")=="public" or _load()!=OK:return {}
	var key:=_key(id,scope_for(person))
	if _state.identities.has(key):return _state.identities[key].duplicate(true)
	# An old unscoped generated ID might belong to a different saved campus.
	# Do not silently adopt or replace it without an explicit host decision.
	if legacy_conflict(person):return {}
	return _initialize_identity(person)

static func _initialize_identity(person: Dictionary) -> Dictionary:
	var id:=str(person.get("id",""))
	var scope:=scope_for(person)
	var key:=_key(id,scope)
	if _state.identities.has(key):return _state.identities[key].duplicate(true)
	var designed:=designs()
	if Roster.PEOPLE.has(id) and not designed.has(id):last_error=ERR_INVALID_DATA;return {}
	var value: Dictionary=designed[id].duplicate(true) if designed.has(id) else Design.draft(person)
	if value.is_empty() or _state.identities.size()>=MAX_IDENTITIES:return {}
	if value.get("voice_type","")=="preset" and Models.voice_compatible("gpt-realtime-2.1-mini",str(value.get("permanent_voice_id","")),"preset"):
		# New profiles default to the efficient renderer. Existing saved identities,
		# including explicitly approved custom voices, are never migrated silently.
		value.preferred_model="gpt-realtime-2.1-mini"
	if not scope.is_empty():value.voice_scope=scope
	var prior:=_state.duplicate(true)
	_state.identities[key]=value
	if _commit(prior)!=OK:return {}
	return value.duplicate(true)

static func resolve_legacy(person: Dictionary,adopt: bool,confirmed: bool) -> Error:
	if not confirmed or not legacy_conflict(person):return ERR_UNAUTHORIZED
	var id:=str(person.id)
	var scope:=scope_for(person)
	var key:=_key(id,scope)
	if _generation_claims.has(id) or _generation_claims.has(key):return ERR_BUSY
	if not adopt:return OK if not _initialize_identity(person).is_empty() else ERR_CANT_CREATE
	var prior:=_state.duplicate(true)
	for section: String in ["identities","candidates","pending_creations"]:
		if _state[section].has(id):
			var item: Dictionary=_state[section][id]
			item.voice_scope=scope
			_state[section][key]=item
			_state[section].erase(id)
	for allocation: Dictionary in _state.allocations.values():
		if str(allocation.get("storage_key",allocation.get("character_id","")))==id:allocation.storage_key=key
	return _commit(prior)

static func resolve(person: Dictionary,model: String,override: Dictionary={}) -> Dictionary:
	var profile:=identity(person) if override.is_empty() else override.duplicate(true)
	if profile.is_empty():return {"ok":false,"error":"An older voice belongs to an unscoped character ID. Resolve it explicitly in Character Voices." if legacy_conflict(person) else "The saved character voice could not be loaded. It has not been replaced.","character_id":str(person.get("id",""))}
	var configured_model:=model
	if override.is_empty() and not str(profile.get("preferred_model","")).is_empty():model=str(profile.preferred_model)
	var voice: Variant=str(profile.permanent_voice_id) if profile.voice_type=="preset" else {"id":str(profile.permanent_voice_id)}
	var result:={"ok":true,"voice":voice,"voice_type":str(profile.voice_type),"provider":str(profile.provider),
		"character_id":str(profile.character_id),"profile_version":int(profile.profile_version),"identity":profile,
		"model":model,"configured_model":configured_model,"model_pinned":not str(profile.get("preferred_model","")).is_empty(),"approval_status":str(profile.approval_status),"audition_status":str(profile.audition_status)}
	if Models.lifecycle(model).get("status","")=="retired":
		result.ok=false;result.error="This voice model has retired. Choose a compatible model in Character Voices; the voice has not changed."
	elif not Models.voice_compatible(model,voice,str(profile.voice_type)):
		result.ok=false;result.error="%s does not support this character's %s voice. Select a compatible model or explicitly approve a new voice."%[model,str(profile.voice_type)]
	return result

static func candidate(character_id: String,scope: String="") -> Dictionary:
	if _load()!=OK:return {}
	return _state.candidates.get(_key(character_id,scope),{}).duplicate(true)

static func pending_creation(character_id: String,scope: String="") -> Dictionary:
	if _load()!=OK:return {}
	var key:=_key(character_id,scope)
	var result: Dictionary=_state.pending_creations.get(key,{}).duplicate(true)
	if not result.is_empty():result.in_flight=_generation_claims.has(key)
	return result

static func creation_design(person: Dictionary) -> Dictionary:
	var current:=peek(person)
	if current.is_empty():return {}
	# An upgraded dossier can design a new candidate without mutating the saved
	# provisional speaker. Existing approved voices always retain their design.
	if not Roster.PEOPLE.has(str(person.get("id",""))) and current.get("approval_status")=="provisional_preset" and person.get("dossier_status","")=="complete":
		var proposed:=Design.draft(person)
		if not proposed.is_empty():return proposed
	return current

# Personalized Realtime preset candidates allocate no custom provider voice.
# A candidate has its own version even when it shares the active base voice.
static func stage_preset(person: Dictionary,base_voice: String,description: String) -> Error:
	var current:=identity(person)
	if current.is_empty():return last_error if last_error!=OK else ERR_INVALID_DATA
	var key:=_key(str(person.id),scope_for(person))
	var prompt:=description.strip_edges()
	if prompt.length()<40 or prompt.length()>MAX_PROMPT_CHARS or not Models.voice_compatible("gpt-realtime-2.1-mini",base_voice,"preset"):return ERR_INVALID_PARAMETER
	if _state.candidates.has(key) or _state.pending_creations.has(key):return ERR_ALREADY_EXISTS
	var next:=Design.draft(person)
	if next.is_empty():next=current.duplicate(true)
	var scope:=scope_for(person)
	if not scope.is_empty():next.voice_scope=scope
	next.voice_type="preset";next.permanent_voice_id=base_voice;next.profile_version=int(current.profile_version)+1
	next.compatible_model_families=["gpt-realtime-2.1-mini","gpt-realtime-2.1","gpt-live-1.1","gpt-live-1","gpt-audio-1.5","gpt-4o-mini-tts"]
	next.design_description=prompt;next.approval_status="candidate";next.audition_status="not_auditioned"
	next.voice_design_status="personalized_preset_candidate";next.creation_source="personalized_preset"
	for field in ["preferred_model","auditions","audition_runs","approved_at","approved_script_hash","provisional_notice"]:next.erase(field)
	var prior:=_state.duplicate(true)
	_state.candidates[key]=next
	return _commit(prior)

static func stage_candidate(person: Dictionary,created: Dictionary) -> Error:
	var current:=identity(person)
	if current.is_empty():return last_error if last_error!=OK else ERR_INVALID_DATA
	var key:=_key(str(person.id),scope_for(person))
	var id:=str(created.get("id",""))
	var voice_type:=str(created.get("type","prompt"))
	if not id.begins_with("voice_") or id.length()>128 or not Models.valid_id(id) or voice_type not in ["prompt","audio_sample"]:return ERR_INVALID_PARAMETER
	if _state.candidates.has(key) or id==str(current.permanent_voice_id):return ERR_ALREADY_EXISTS
	var allocation: Dictionary=_state.allocations.get(id,{})
	if not allocation.is_empty() and (str(allocation.get("storage_key",allocation.get("character_id","")))!=key or str(allocation.get("type",""))!=voice_type):return ERR_ALREADY_EXISTS
	if allocation.is_empty() and _state.allocations.size()>=MAX_IDENTITIES:return ERR_OUT_OF_MEMORY
	var next:=creation_design(person)
	if next.is_empty():next=current.duplicate(true)
	var scope:=scope_for(person)
	if not scope.is_empty():next.voice_scope=scope
	next.permanent_voice_id=id;next.voice_type=voice_type;next.profile_version=int(current.profile_version)+1
	next.compatible_model_families=["gpt-live-1.1","gpt-live-1"] if voice_type=="prompt" else ["gpt-live-1.1","gpt-live-1","gpt-realtime-2.1","gpt-realtime-2.1-mini","gpt-audio-1.5","gpt-4o-mini-tts"]
	next.approval_status="candidate";next.audition_status="not_auditioned";next.voice_design_status="generated_candidate" if not created.get("imported",false) else "imported_candidate"
	for field in ["preferred_model","auditions","audition_runs","approved_at","approved_script_hash","provisional_notice"]:
		next.erase(field)
	var described:=str(created.get("prompt",current.design_description)).strip_edges()
	if not described.is_empty():next.design_description=described.left(MAX_PROMPT_CHARS)
	# The acoustic prompt is the intended design; numeric/text fields are not
	# measurements of the created audio. Never claim that synthesis confirmed them.
	next.creation_source="existing_provider_resource" if created.get("imported",false) else "original_description"
	var prior:=_state.duplicate(true)
	_state.candidates[key]=next
	if allocation.is_empty():
		_state.allocations[id]={"character_id":str(person.id),"storage_key":key,"type":voice_type,"created_at":int(Time.get_unix_time_from_system())}
	_state.pending_creations.erase(key)
	return _commit(prior)

static func generate_candidate(service: Node,person: Dictionary,prompt: String,script_hint: String="",draft: Dictionary={}) -> Dictionary:
	var id:=str(person.get("id",""))
	var key:=_key(id,scope_for(person))
	if not is_instance_valid(service) or not service.has_method("create_prompt_voice") or not service.host_allowed():return {"ok":false,"error":"Only the configured host can create a voice."}
	if identity(person).is_empty():return {"ok":false,"error":"The character voice could not be saved. Resolve any legacy or storage issue first."}
	if _generation_claims.has(key) or _state.candidates.has(key):return {"ok":false,"error":"This character already has a pending voice candidate."}
	if _state.pending_creations.has(key):return {"ok":false,"error":"A previous creation is unresolved. Check the provider dashboard and recover its ID before trying again."}
	if not bool(capacity(person).available):return {"ok":false,"error":"No known prompt-voice capacity remains after faculty reservations."}
	var text:=prompt.strip_edges()
	var hint:=script_hint.strip_edges()
	if text.length()<40 or text.length()>MAX_PROMPT_CHARS:return {"ok":false,"error":"Use a voice design between 40 and 2,000 characters."}
	if not hint.is_empty() and (hint.length()<20 or hint.length()>2000):return {"ok":false,"error":"Use a representative script of 20–2,000 characters or leave it blank."}
	# Journal the operation BEFORE the POST. Even a process crash or lost reply
	# cannot cause a second allocation on the next launch.
	var ticket:=Crypto.new().generate_random_bytes(8).hex_encode()
	var name:="LabVolt original "+id.left(128)+" "+ticket
	var prior:=_state.duplicate(true)
	_state.pending_creations[key]={"character_id":id,"voice_scope":scope_for(person),"name":name,"prompt":text,"created_at":int(Time.get_unix_time_from_system())}
	if _commit(prior)!=OK:return {"ok":false,"error":"Could not save the creation journal. No provider request was made."}
	_generation_claims[key]=ticket
	var result: Dictionary=await service.create_prompt_voice(name,text,hint,draft)
	_generation_claims.erase(key)
	if not bool(result.get("ok",false)):
		# A definite rejection may be retried explicitly. An ambiguous provider
		# outcome stays journaled until the host reconciles it.
		if not bool(result.get("creation_uncertain",false)):
			var before:=_state.duplicate(true)
			_state.pending_creations.erase(key)
			if _commit(before)!=OK:result.error="Creation failed and its journal could not be cleared. Reconcile it before retrying."
		else:result.error=str(result.get("error","Creation could not be confirmed."))+" Check the voice dashboard for "+name+"."
		return result
	result.prompt=text
	var error:=stage_candidate(person,result)
	if error!=OK:return {"ok":false,"creation_uncertain":true,"error":"The provider created voice %s, but saving the candidate failed (%s). Keep this ID; do not generate a duplicate."%[str(result.get("id","")),error_string(error)],"created_voice_id":str(result.get("id",""))}
	return {"ok":true,"id":str(result.id),"candidate":candidate(id,scope_for(person))}

static func recover_candidate(person: Dictionary,voice_id: String,voice_type: String,prompt: String,confirmed: bool) -> Error:
	if not confirmed:return ERR_UNAUTHORIZED
	if _load()!=OK:return last_error
	var key:=_key(str(person.get("id","")),scope_for(person))
	if _generation_claims.has(key):return ERR_BUSY
	var journal: Dictionary=_state.pending_creations.get(key,{})
	var description:=str(journal.get("prompt",prompt)).strip_edges()
	if description.length()<40 or description.length()>MAX_PROMPT_CHARS:return ERR_INVALID_PARAMETER
	return stage_candidate(person,{"id":voice_id.strip_edges(),"type":voice_type,"prompt":description,"imported":true})

static func clear_unconfirmed_creation(character_id: String,scope: String,confirmed_no_voice: bool) -> Error:
	if not confirmed_no_voice:return ERR_UNAUTHORIZED
	if _load()!=OK:return last_error
	var key:=_key(character_id,scope)
	if _generation_claims.has(key):return ERR_BUSY
	if not _state.pending_creations.has(key):return ERR_DOES_NOT_EXIST
	var prior:=_state.duplicate(true)
	_state.pending_creations.erase(key)
	return _commit(prior)

static func _audition_key(model: String,script: String) -> String:
	return model+":"+script.strip_edges().sha256_text()

static func auditions_for(profile: Dictionary,model: String,script: String) -> Dictionary:
	var runs: Dictionary=profile.get("audition_runs",{})
	var record: Dictionary=runs.get(_audition_key(model,script),{})
	return record.get("moods",{}).duplicate(true)

static func record_audition(character_id: String,voice_id: String,mood: String,model: String="",script: String="",scope: String="",expected_version: int=0) -> Error:
	if _load()!=OK:return last_error
	var key:=_key(character_id,scope)
	var target: Dictionary=_state.candidates.get(key,{})
	if str(target.get("permanent_voice_id",""))!=voice_id or (expected_version>0 and int(target.get("profile_version",0))!=expected_version):target=_state.identities.get(key,{})
	if target.is_empty() or str(target.permanent_voice_id)!=voice_id or (expected_version>0 and int(target.profile_version)!=expected_version):return ERR_DOES_NOT_EXIST
	var voice: Variant=voice_id if target.voice_type=="preset" else {"id":voice_id}
	if not Models.voice_compatible(model,voice,str(target.voice_type)) or script.strip_edges().is_empty() or script.length()>1200 or mood not in AUDITION_ALLOWED:return ERR_INVALID_PARAMETER
	var prior:=_state.duplicate(true)
	var runs: Dictionary=target.get("audition_runs",{})
	var run_key:=_audition_key(model,script)
	if not runs.has(run_key) and runs.size()>=MAX_AUDITION_RUNS:runs.erase(runs.keys()[0])
	var run: Dictionary=runs.get_or_add(run_key,{"model":model,"script_hash":script.strip_edges().sha256_text(),"moods":{}})
	run.moods[mood]=int(Time.get_unix_time_from_system())
	target.audition_runs=runs
	var heard: Dictionary=target.get("auditions",{})
	heard[mood]=int(Time.get_unix_time_from_system())
	target.auditions=heard
	if target.approval_status!="approved":target.audition_status="preview_played"
	return _commit(prior)

static func approve(character_id: String,voice_id: String,fit_confirmed: bool,model: String="",script: String="",scope: String="",expected_version: int=0) -> Error:
	if _load()!=OK:return last_error
	var key:=_key(character_id,scope)
	var next: Dictionary=_state.candidates.get(key,{})
	var pending:=str(next.get("permanent_voice_id",""))==voice_id and (expected_version<=0 or int(next.get("profile_version",0))==expected_version)
	if not pending:next=_state.identities.get(key,{})
	next=next.duplicate(true)
	if next.is_empty() or str(next.permanent_voice_id)!=voice_id or (expected_version>0 and int(next.profile_version)!=expected_version):return ERR_DOES_NOT_EXIST
	var heard:=auditions_for(next,model,script)
	if not fit_confirmed or script.strip_edges().is_empty() or not AUDITION_MOODS.all(func(mood: String):return heard.has(mood)):return ERR_UNAUTHORIZED
	var voice: Variant=voice_id if next.voice_type=="preset" else {"id":voice_id}
	if not Models.voice_compatible(model,voice,str(next.voice_type)):return ERR_INVALID_PARAMETER
	var prior:=_state.duplicate(true)
	next.preferred_model=model
	next.approval_status="approved";next.audition_status="host_approved_after_listening"
	next.approved_script_hash=script.strip_edges().sha256_text()
	next.approved_at=int(Time.get_unix_time_from_system())
	_state.identities[key]=next
	if pending:_state.candidates.erase(key)
	return _commit(prior)

static func discard_candidate(character_id: String,scope: String="") -> Error:
	if _load()!=OK:return last_error
	var prior:=_state.duplicate(true)
	# Discarding an audition never deletes a remote voice or frees quota.
	_state.candidates.erase(_key(character_id,scope))
	return _commit(prior)

static func set_external_voice_count(count: int) -> Error:
	if _load()!=OK:return last_error
	var prior:=_state.duplicate(true)
	_state.external_prompt_voices=clampi(count,0,PROMPT_VOICE_LIMIT)
	return _commit(prior)

static func custom_status(person: Dictionary) -> String:
	if _load()!=OK:return "storage_error"
	if legacy_conflict(person):return "legacy"
	var key:=_key(str(person.get("id","")),scope_for(person))
	if _state.pending_creations.has(key):return "creating" if _generation_claims.has(key) else "reconcile"
	if _state.candidates.has(key):return "candidate"
	var active: Dictionary=_state.identities.get(key,{})
	if active.get("voice_type","preset")!="preset" and active.get("approval_status","")=="approved":return "approved"
	return "missing"

static func missing_faculty(people: Dictionary) -> Array[String]:
	var missing: Array[String]=[]
	for id: String in Roster.PEOPLE:
		if people.has(id) and custom_status(people[id])=="missing":missing.append(id)
	for id: String in Roster.GENERATED:
		if people.has(id) and custom_status(people[id])=="missing":missing.append(id)
	return missing

static func capacity(person: Dictionary={}) -> Dictionary:
	if _load()!=OK:return {"available":false,"remaining":0,"error":"Voice storage is unavailable."}
	var known:=0
	for item: Dictionary in _state.allocations.values():
		if item.get("type")=="prompt" and not item.get("foreign_account",false):known+=1
	var reserved:=0
	for id: String in Roster.PEOPLE:
		# An abandoned allocation still consumes quota, but doesn't satisfy a
		# faculty reservation. A pending or approved candidate does.
		if custom_status({"id":id})=="missing":reserved+=1
	var external:=int(_state.get("external_prompt_voices",0))
	var unresolved: int=_state.pending_creations.size()
	var remaining:=maxi(0,PROMPT_VOICE_LIMIT-known-external-unresolved)
	var faculty:=Roster.PEOPLE.has(str(person.get("id","")))
	return {"available":remaining>0 and (faculty or remaining>reserved),"remaining":remaining,"known":known,
		"external":external,"in_flight":_generation_claims.size(),"unresolved":unresolved,"faculty_reserved":reserved,"limit":PROMPT_VOICE_LIMIT,
		"verified_organization_count":false,"note":"Known allocations, unresolved requests and your external count. Actual organization quota is enforced by OpenAI; do not double-count recovered IDs."}

static func reset_cache() -> void:
	_loaded_path="";_state.clear();last_error=OK

static func _load() -> Error:
	if _loaded_path==store_path:return last_error
	_loaded_path=store_path
	_state={"version":SCHEMA_VERSION,"identities":{},"candidates":{},"allocations":{},"pending_creations":{},"external_prompt_voices":0}
	last_error=OK
	if not FileAccess.file_exists(store_path) and not FileAccess.file_exists(store_path+".bak") and not FileAccess.file_exists(store_path+".tmp"):return OK
	# A backup may precede a successful remote allocation or approval. Never
	# silently revert to it: doing so could allocate again or change a speaker.
	if FileAccess.file_exists(store_path):
		var file:=FileAccess.open(store_path,FileAccess.READ)
		if file!=null and file.get_length()<=MAX_STORE_BYTES:
			var data: Variant=_parse(file.get_as_text());file.close()
			if _valid_store(data):
				_state=data
				_state.get_or_add("pending_creations",{})
				return OK
	last_error=ERR_FILE_CORRUPT
	return last_error

static func _valid_store(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=SCHEMA_VERSION:return false
	for section: String in ["identities","candidates","allocations"]:
		if not value.get(section) is Dictionary or value[section].size()>MAX_IDENTITIES:return false
	var allocated: Dictionary={}
	var pending: Variant=value.get("pending_creations",{})
	if not pending is Dictionary or pending.size()>PROMPT_VOICE_LIMIT:return false
	for key: String in pending:
		var item: Variant=pending[key]
		if not item is Dictionary or not item.get("character_id") is String or not item.get("name") is String or not item.get("prompt") is String:return false
		if key!=_key(str(item.character_id),str(item.get("voice_scope",""))) or not value.identities.has(key) or value.candidates.has(key) or item.name.length()>256 or item.prompt.length()>MAX_PROMPT_CHARS:return false
	for section: String in ["identities","candidates"]:
		for key: String in value[section]:
			var profile: Variant=value[section][key]
			if not profile is Dictionary:return false
			var id:=str(profile.get("character_id",""))
			if key!=_key(id,str(profile.get("voice_scope",""))) or not _valid_identity(profile,id):return false
			if profile.voice_type!="preset":
				var voice_id:=str(profile.permanent_voice_id)
				if allocated.has(voice_id):return false
				var allocation: Variant=value.allocations.get(voice_id)
				if not allocation is Dictionary or str(allocation.get("storage_key",allocation.get("character_id","")))!=key or allocation.get("type")!=profile.voice_type:return false
				allocated[voice_id]=true
	for id: String in value.allocations:
		if not value.allocations[id] is Dictionary or not id.begins_with("voice_") or not Models.valid_id(id):return false
		if value.allocations[id].get("type") not in ["prompt","audio_sample"]:return false
	var external: Variant=value.get("external_prompt_voices",0)
	return (external is float or external is int) and is_finite(float(external)) and float(external)>=0 and float(external)<=PROMPT_VOICE_LIMIT

static func _valid_identity(value: Variant,id: String) -> bool:
	if not value is Dictionary or str(value.get("character_id",""))!=id:return false
	for key: String in ["provider","voice_type","permanent_voice_id","design_description","vocal_presentation","pitch_range","resonance","timbre","texture","accent","articulation","mannerisms","emotional_tendencies","approval_status","audition_status"]:
		if not value.get(key) is String or str(value[key]).is_empty() or str(value[key]).length()>4000:return false
	if value.provider!="openai" or value.voice_type not in ["preset","prompt","audio_sample"]:return false
	if value.voice_type!="preset" and (not str(value.permanent_voice_id).begins_with("voice_") or not Models.valid_id(str(value.permanent_voice_id)) or str(value.permanent_voice_id).length()>128):return false
	var heard: Variant=value.get("auditions",{})
	if not heard is Dictionary or heard.size()>32:return false
	var scope:=str(value.get("voice_scope",""))
	if not scope.is_empty() and (scope.length()!=64 or not scope.is_valid_hex_number(false)):return false
	var runs: Variant=value.get("audition_runs",{})
	if not runs is Dictionary or runs.size()>MAX_AUDITION_RUNS:return false
	for run in runs.values():
		if not run is Dictionary or not run.get("moods") is Dictionary or run.moods.size()>32:return false
	for key: String in ["profile_version","perceived_age","normal_pace"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(float(value[key])):return false
	return int(value.profile_version)>0 and float(value.perceived_age)>=18. and float(value.normal_pace)>=.5 and float(value.normal_pace)<=1.5

static func _commit(prior: Dictionary) -> Error:
	var error:=_save()
	if error!=OK:_state=prior
	return error

static func _save() -> Error:
	if last_error!=OK:return last_error
	if not _valid_store(_state):last_error=ERR_INVALID_DATA;return last_error
	var text:=JSON.stringify(_state,"\t")
	if text.to_utf8_buffer().size()>MAX_STORE_BYTES:last_error=ERR_OUT_OF_MEMORY;return last_error
	var parent:=ProjectSettings.globalize_path(store_path).get_base_dir()
	var error:=DirAccess.make_dir_recursive_absolute(parent)
	if error!=OK:last_error=error;return error
	var file:=FileAccess.open(store_path+".tmp",FileAccess.WRITE)
	if file==null:last_error=FileAccess.get_open_error();return last_error
	file.store_string(text);file.flush();error=file.get_error();file.close()
	if error!=OK:last_error=error;return error
	if FileAccess.file_exists(store_path):
		# Preserve a known-good backup; corrupt primaries never replace it.
		var prior: Variant=_parse(FileAccess.get_file_as_string(store_path))
		if _valid_store(prior):
			error=DirAccess.copy_absolute(store_path,store_path+".bak")
			if error!=OK:last_error=error;return error
	error=DirAccess.rename_absolute(store_path+".tmp",store_path)
	last_error=error
	return error

# Read-only display; inspection never allocates a voice.
static func peek(person: Dictionary) -> Dictionary:
	var id:=str(person.get("id",""))
	if id.is_empty() or _load()!=OK:return {}
	if person.get("identity_scope","")=="public" or legacy_conflict(person):return {}
	var key:=_key(id,scope_for(person))
	return _state.identities[key].duplicate(true) if _state.identities.has(key) else Design.draft(person)

static func portable_profile(person: Dictionary) -> Dictionary:
	# Only the permanent fictional voice travels. Auditions, quotas, request
	# journals and account availability remain on the device that owns them.
	var profile:=peek(person)
	if profile.is_empty():return {}
	var result: Dictionary={}
	for key: String in ["character_id","provider","voice_type","permanent_voice_id","compatible_model_families","perceived_age","vocal_presentation","pitch_range","resonance","timbre","texture","accent","normal_pace","normal_projection","articulation","mannerisms","emotional_tendencies","profile_version","approval_status","voice_design_status","allocation","design_description","preferred_model","voice_scope"]:
		if profile.has(key):result[key]=profile[key]
	result.audition_status="not_auditioned_on_this_device"
	return result.duplicate(true)

static func accept_portable_profile(person: Dictionary,record: Dictionary) -> Error:
	var id:=str(person.get("id",""))
	if id.is_empty() or id.length()>128 or Roster.has(id) or record.size()>32 or JSON.stringify(record).to_utf8_buffer().size()>16000:return ERR_INVALID_DATA
	if _load()!=OK:return last_error
	# Apply a field allowlist, even to a host-validated public character record.
	var incoming: Dictionary={}
	for field: String in ["character_id","provider","voice_type","permanent_voice_id","compatible_model_families","perceived_age","vocal_presentation","pitch_range","resonance","timbre","texture","accent","normal_pace","normal_projection","articulation","mannerisms","emotional_tendencies","profile_version","approval_status","voice_design_status","allocation","design_description","preferred_model"]:
		if record.has(field):incoming[field]=record[field]
	incoming.voice_scope=scope_for(person)
	incoming.audition_status="not_auditioned_on_this_device"
	if not _valid_identity(incoming,id) or incoming.get("approval_status") not in ["provisional_preset","approved"]:return ERR_INVALID_DATA
	if incoming.voice_type!="preset" and incoming.approval_status!="approved":return ERR_INVALID_DATA
	var preferred:=str(incoming.get("preferred_model",""))
	var voice: Variant=str(incoming.permanent_voice_id) if incoming.voice_type=="preset" else {"id":str(incoming.permanent_voice_id)}
	if incoming.voice_type=="preset" and voice not in Models.LIVE_VOICES+Models.speech_voices("gpt-4o-mini-tts"):return ERR_INVALID_DATA
	if not preferred.is_empty():
		# A retired model is still historical identity data. Preserve that pin;
		# resolve() reports its lifecycle without silently changing the speaker.
		if not Models.supports(preferred,"tts"):return ERR_INVALID_DATA
		var capabilities:=Models.voice_capabilities(preferred)
		if incoming.voice_type=="preset" and voice not in capabilities.presets:return ERR_INVALID_DATA
		if incoming.voice_type=="prompt" and not capabilities.prompt_voices:return ERR_INVALID_DATA
		if incoming.voice_type=="audio_sample" and not capabilities.recording_voices:return ERR_INVALID_DATA
	var key:=_key(id,scope_for(person))
	if _state.identities.has(key):
		var current: Dictionary=_state.identities[key]
		return OK if current.get("permanent_voice_id")==incoming.permanent_voice_id and current.get("voice_type")==incoming.voice_type else ERR_ALREADY_EXISTS
	if _state.identities.size()>=MAX_IDENTITIES:return ERR_OUT_OF_MEMORY
	var previous:=_state.duplicate(true)
	if incoming.voice_type!="preset":
		var allocation: Dictionary=_state.allocations.get(incoming.permanent_voice_id,{})
		if not allocation.is_empty() and str(allocation.get("storage_key",allocation.get("character_id","")))!=key:return ERR_ALREADY_EXISTS
		if allocation.is_empty():
			_state.allocations[incoming.permanent_voice_id]={"character_id":id,"storage_key":key,"type":incoming.voice_type,"foreign_account":true}
		incoming.account_availability="unverified_portable_voice"
	_state.identities[key]=incoming
	return _commit(previous)

static func _parse(text: String) -> Variant:
	var parser:=JSON.new()
	return parser.data if parser.parse(text)==OK else null

static func profiles() -> Dictionary:
	var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not source is Dictionary or source.get("version")!=1 or not source.get("voices") is Dictionary:return {}
	var voices: Dictionary=source.voices
	if voices.size()!=Roster.PEOPLE.size():return {}
	for id in Roster.PEOPLE:
		if not voices.get(id) is Dictionary:return {}
		var profile: Dictionary=voices[id]
		if str(profile.get("target","")).is_empty():return {}
		if not profile.get("model","") is String or not (profile.get("speaker",0) is int or profile.get("speaker",0) is float) or int(profile.speaker)<0:return {}
		if not profile.get("rate",0.0) is float or float(profile.rate)<0.5 or float(profile.rate)>1.5:return {}
		if not profile.get("gain",0.0) is float or float(profile.gain)<0.0 or float(profile.gain)>2.0:return {}
		if not (profile.get("pause_ms",0) is int or profile.get("pause_ms",0) is float) or int(profile.pause_ms)<0 or int(profile.pause_ms)>1000:return {}
	return voices

static func available_voice_ids() -> Dictionary:
	var found: Dictionary={}
	var entries:=profiles()
	for id in entries:
		var model: String=str(entries[id].model)
		if model.begins_with("res://assets/campus/faculty/voices/") and model.ends_with(".onnx") and not resolve_model(model).is_empty():
			found[id]=model+":"+str(entries[id].speaker)
	return found

static func resolve_model(model: String) -> String:
	if not model.begins_with("res://assets/campus/faculty/voices/") or not model.ends_with(".onnx"):return ""
	var local:=ProjectSettings.globalize_path(model)
	if FileAccess.file_exists(local) and FileAccess.file_exists(local+".json"):return local
	var sidecar:=OS.get_executable_path().get_base_dir().path_join("teacher_voices").path_join(model.get_file())
	return sidecar if FileAccess.file_exists(sidecar) and FileAccess.file_exists(sidecar+".json") else ""
