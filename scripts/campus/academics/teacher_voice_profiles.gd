extends RefCounted
## Persistent OpenAI vocal identities. Legacy offline profiles below are only
## consumed when the host explicitly chooses the legacy offline provider.
const PATH := "res://assets/campus/faculty/voice_profiles.json"
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const DESIGNS_PATH := "res://assets/campus/faculty/character_voice_designs.json"
const SCHEMA_VERSION := 1
const MAX_IDENTITIES := 8192
const PROMPT_VOICE_LIMIT := 100
const MAX_STORE_BYTES := 16777216
const AUDITION_MOODS := ["normal","sad","angry"]
static var store_path := "user://character_voices.json"
static var _loaded_path := ""
static var _state: Dictionary={}
static var _designs: Dictionary={}
static var _generation_claims: Dictionary={}
static var last_error: Error=OK

static func designs() -> Dictionary:
	if _designs.is_empty():
		var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(DESIGNS_PATH))
		if parsed is Dictionary and parsed.get("version")==1 and parsed.get("voices") is Dictionary:
			for id: String in Roster.PEOPLE:
				if not _valid_identity(parsed.voices.get(id,{}),id):return {}
			_designs=parsed.voices.duplicate(true)
	return _designs.duplicate(true)

static func identity(person: Dictionary) -> Dictionary:
	var id:=str(person.get("id",""))
	if id.is_empty() or id.length()>128 or _load()!=OK:return {}
	if _state.identities.has(id):return _state.identities[id].duplicate(true)
	var designed:=designs()
	var value: Dictionary=designed[id].duplicate(true) if designed.has(id) else _student_identity(person)
	if value.is_empty():return {}
	if _state.identities.size()>=MAX_IDENTITIES:last_error=ERR_OUT_OF_MEMORY;return {}
	_state.identities[id]=value
	if _save()!=OK:
		_state.identities.erase(id)
		return {}
	return value.duplicate(true)

static func resolve(person: Dictionary,model: String,override: Dictionary={}) -> Dictionary:
	var profile:=identity(person) if override.is_empty() else override.duplicate(true)
	if profile.is_empty():return {"ok":false,"error":"The saved character voice could not be loaded. It has not been replaced.","character_id":str(person.get("id",""))}
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

static func candidate(character_id: String) -> Dictionary:
	if _load()!=OK:return {}
	return _state.candidates.get(character_id,{}).duplicate(true)

static func stage_candidate(person: Dictionary,created: Dictionary) -> Error:
	var current:=identity(person)
	if current.is_empty():return last_error if last_error!=OK else ERR_INVALID_DATA
	var id:=str(created.get("id",""))
	var voice_type:=str(created.get("type","prompt"))
	if not id.begins_with("voice_") or id.length()>200 or voice_type not in ["prompt","audio_sample"]:return ERR_INVALID_PARAMETER
	if not candidate(str(person.id)).is_empty():return ERR_ALREADY_EXISTS
	if _state.allocations.has(id) and str(_state.allocations[id].get("character_id",""))!=str(person.id):return ERR_ALREADY_EXISTS
	var next:=current.duplicate(true)
	next.permanent_voice_id=id;next.voice_type=voice_type;next.profile_version=int(current.profile_version)+1
	next.compatible_model_families=["gpt-live-1.1"] if voice_type=="prompt" else ["gpt-realtime-2.1","gpt-realtime-2.1-mini","gpt-4o-mini-tts"]
	next.approval_status="candidate";next.audition_status="not_auditioned";next.voice_design_status="generated_candidate"
	next.erase("preferred_model");next.erase("auditions");next.erase("approved_at")
	next.erase("provisional_notice")
	var described:=str(created.get("prompt",current.design_description)).strip_edges()
	if not described.is_empty():next.design_description=described.left(4000)
	_state.candidates[str(person.id)]=next
	_state.allocations[id]={"character_id":str(person.id),"type":voice_type,"created_at":int(Time.get_unix_time_from_system())}
	return _save()

static func generate_candidate(service: Node,person: Dictionary,prompt: String,script_hint: String="",draft: Dictionary={}) -> Dictionary:
	var id:=str(person.get("id",""))
	if not is_instance_valid(service) or not service.has_method("create_prompt_voice") or not service.host_allowed():return {"ok":false,"error":"Only the configured host can create a voice."}
	if identity(person).is_empty():return {"ok":false,"error":"The character voice could not be saved."}
	if _generation_claims.has(id) or not candidate(id).is_empty():return {"ok":false,"error":"This character already has a pending voice candidate."}
	if not bool(capacity(person).available):return {"ok":false,"error":"No known prompt-voice capacity remains after faculty reservations."}
	var text:=prompt.strip_edges()
	if text.length()<40 or text.length()>4000:return {"ok":false,"error":"Use a voice design between 40 and 4,000 characters."}
	_generation_claims[id]=true
	# Persist the successful result here, outside the UI object's lifetime.
	var result: Dictionary=await service.create_prompt_voice(str(person.get("name",id)),text,script_hint.left(2000),draft)
	_generation_claims.erase(id)
	if not bool(result.get("ok",false)):return result
	result.prompt=text
	var error:=stage_candidate(person,result)
	if error!=OK:return {"ok":false,"error":"The provider created voice %s, but saving the candidate failed (%s). Keep this ID; do not generate a duplicate."%[str(result.get("id","")),error_string(error)],"created_voice_id":str(result.get("id",""))}
	return {"ok":true,"id":str(result.id),"candidate":candidate(id)}

static func record_audition(character_id: String,voice_id: String,mood: String) -> Error:
	if _load()!=OK:return last_error
	var target: Dictionary=_state.candidates.get(character_id,_state.identities.get(character_id,{}))
	if target.is_empty() or str(target.permanent_voice_id)!=voice_id:return ERR_DOES_NOT_EXIST
	# This is called only after a user-started preview actually finishes playback.
	var heard: Dictionary=target.get("auditions",{})
	heard[mood.left(32)]=int(Time.get_unix_time_from_system())
	target.auditions=heard;target.audition_status="preview_played"
	return _save()

static func approve(character_id: String,voice_id: String,fit_confirmed: bool,model: String="") -> Error:
	if _load()!=OK:return last_error
	var next: Dictionary=_state.candidates.get(character_id,_state.identities.get(character_id,{})).duplicate(true)
	if next.is_empty() or str(next.permanent_voice_id)!=voice_id:return ERR_DOES_NOT_EXIST
	if not fit_confirmed or not AUDITION_MOODS.all(func(mood: String):return next.get("auditions",{}).has(mood)):return ERR_UNAUTHORIZED
	if not model.is_empty():
		var voice: Variant=str(next.permanent_voice_id) if next.voice_type=="preset" else {"id":str(next.permanent_voice_id)}
		if not Models.voice_compatible(model,voice,str(next.voice_type)) or Models.lifecycle(model).get("status","")=="retired":return ERR_INVALID_PARAMETER
		next.preferred_model=model
	next.approval_status="approved";next.audition_status="host_approved_after_listening"
	next.approved_at=int(Time.get_unix_time_from_system())
	_state.identities[character_id]=next
	_state.candidates.erase(character_id)
	return _save()

static func discard_candidate(character_id: String) -> Error:
	if _load()!=OK:return last_error
	# The remote voice is never deleted automatically, and still counts toward
	# known organization usage. An abandoned audition cannot free provider quota.
	_state.candidates.erase(character_id)
	return _save()

static func set_external_voice_count(count: int) -> Error:
	if _load()!=OK:return last_error
	_state.external_prompt_voices=clampi(count,0,PROMPT_VOICE_LIMIT)
	return _save()

static func capacity(person: Dictionary={}) -> Dictionary:
	if _load()!=OK:return {"available":false,"remaining":0,"error":"Voice storage is unavailable."}
	var known:=0
	var faculty_assigned: Dictionary={}
	for id: String in _state.allocations:
		var item: Dictionary=_state.allocations[id]
		if item.get("type")=="prompt":known+=1
		if Roster.PEOPLE.has(str(item.get("character_id",""))):faculty_assigned[str(item.character_id)]=true
	var reserved:=maxi(0,Roster.PEOPLE.size()-faculty_assigned.size())
	var external:=int(_state.get("external_prompt_voices",0))
	var remaining:=maxi(0,PROMPT_VOICE_LIMIT-known-external-_generation_claims.size())
	var faculty:=Roster.PEOPLE.has(str(person.get("id","")))
	return {"available":remaining>0 and (faculty or remaining>reserved),"remaining":remaining,"known":known,
		"external":external,"in_flight":_generation_claims.size(),"faculty_reserved":reserved,"limit":PROMPT_VOICE_LIMIT,
		"verified_organization_count":false,"note":"Known local allocations plus the external count you enter. The provider enforces the actual organization limit."}

static func reset_cache() -> void:
	_loaded_path="";_state.clear();last_error=OK

static func _load() -> Error:
	if _loaded_path==store_path:return last_error
	_loaded_path=store_path
	_state={"version":SCHEMA_VERSION,"identities":{},"candidates":{},"allocations":{},"external_prompt_voices":0}
	last_error=OK
	if not FileAccess.file_exists(store_path) and not FileAccess.file_exists(store_path+".bak"):return OK
	for path: String in [store_path,store_path+".bak"]:
		if not FileAccess.file_exists(path):continue
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null or file.get_length()>MAX_STORE_BYTES:continue
		var data: Variant=_parse(file.get_as_text());file.close()
		if not _valid_store(data):continue
		_state=data;return OK
	last_error=ERR_FILE_CORRUPT
	return last_error

static func _valid_store(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=SCHEMA_VERSION:return false
	for section: String in ["identities","candidates","allocations"]:
		if not value.get(section) is Dictionary or value[section].size()>MAX_IDENTITIES:return false
	for section: String in ["identities","candidates"]:
		for id: String in value[section]:
			if not _valid_identity(value[section][id],id):return false
	for id: String in value.allocations:
		if not value.allocations[id] is Dictionary or not id.begins_with("voice_"):return false
	var external: Variant=value.get("external_prompt_voices",0)
	return (external is float or external is int) and is_finite(float(external)) and float(external)>=0 and float(external)<=PROMPT_VOICE_LIMIT

static func _valid_identity(value: Variant,id: String) -> bool:
	if not value is Dictionary or str(value.get("character_id",""))!=id:return false
	for key: String in ["provider","voice_type","permanent_voice_id","design_description","vocal_presentation","pitch_range","resonance","timbre","texture","accent","articulation","mannerisms","emotional_tendencies","approval_status","audition_status"]:
		if not value.get(key) is String or str(value[key]).is_empty() or str(value[key]).length()>4000:return false
	if value.provider!="openai" or value.voice_type not in ["preset","prompt","audio_sample"]:return false
	if value.voice_type!="preset" and not str(value.permanent_voice_id).begins_with("voice_"):return false
	for key: String in ["profile_version","perceived_age","normal_pace"]:
		if not (value.get(key) is float or value.get(key) is int) or not is_finite(float(value[key])):return false
	return int(value.profile_version)>0 and float(value.perceived_age)>=18. and float(value.normal_pace)>=.5 and float(value.normal_pace)<=1.5

static func _save() -> Error:
	if last_error!=OK:return last_error
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

static func _student_identity(person: Dictionary) -> Dictionary:
	var id:=str(person.get("id",""))
	if id.is_empty():return {}
	var traits: Dictionary=person.get("traits",{})
	var intended: Dictionary=person.get("vocal_identity",{})
	var presentation:=str(intended.get("presentation",person.get("vocal_presentation","androgynous")))
	if presentation not in ["masculine","feminine","androgynous"]:presentation="androgynous"
	var age:=maxi(18,int(person.get("age",22)))
	var warm:=_number(traits,"warmth",.5)
	var pace:=clampf(.85+_number(traits,"speaking_pace",.5)*.28,.8,1.18)
	var voice: String="sage" if presentation=="feminine" and warm>.6 else "coral" if presentation=="feminine" else "cedar" if presentation=="masculine" and pace<1. else "ash" if presentation=="masculine" else "alloy" if pace<.98 else "verse"
	var pitch:=str(intended.get("pitch_range","middle register with a natural conversational range"))
	var accent:=str(intended.get("accent",person.get("accent","plain North American English")))
	var timber:="rounded and warm" if warm>.6 else "clear and dry"
	var profile:={"character_id":id,"provider":"openai","voice_type":"preset","permanent_voice_id":voice,
		"compatible_model_families":["gpt-live-1.1","gpt-realtime-2.1","gpt-realtime-2.1-mini","gpt-4o-mini-tts"],
		"perceived_age":age,"vocal_presentation":presentation,"pitch_range":pitch,"resonance":"balanced and unforced",
		"timbre":timber,"texture":"light natural breath and grain","accent":accent,"normal_pace":pace,
		"normal_projection":"normal","articulation":"clear conversational diction","mannerisms":str(person.get("style","plain-spoken")),
		"emotional_tendencies":"Use this person's expressiveness and restraint; shyness changes hesitation, not basic audibility.",
		"profile_version":1,"audition_status":"not_auditioned","approval_status":"provisional_preset","voice_design_status":"matched_persistent_pool","allocation":"student"}
	profile.design_description="An original fictional adult voice, age about %d, %s vocal presentation. %s, %s timbre, balanced resonance, %s. The same speaker must remain recognizable through every mood. Do not imitate anyone. No permanent emotional state is part of this identity."%[age,presentation,pitch,timber,accent]
	profile.provisional_notice="Persistently matched shared preset. Dedicated faculty voices are allocated before additional student voices."
	return profile

static func _number(source: Dictionary,key: String,fallback: float) -> float:
	var value: Variant=source.get(key,fallback)
	return clampf(float(value),0.,1.) if (value is float or value is int) and is_finite(float(value)) else fallback

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
