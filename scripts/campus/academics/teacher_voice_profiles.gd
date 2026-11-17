extends RefCounted
## Verified speaker assignments for the bundled multi-speaker Piper model.
const PATH := "res://assets/campus/faculty/voice_profiles.json"
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")

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
