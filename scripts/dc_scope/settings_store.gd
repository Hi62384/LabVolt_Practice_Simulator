extends RefCounted
const Settings = preload("res://scripts/dc_scope/settings.gd")
const PATH := "user://dc_scope_settings.cfg"
static func restore(station: int, path := PATH) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path)!=OK: return Settings.defaults()
	var raw: Variant=config.get_value("station_%d"%station,"scope",{})
	var result := Settings.normalize(raw if raw is Dictionary else {})
	result.single=false; result.armed=false
	return result
static func persist(station: int, scope: Dictionary, path := PATH) -> Error:
	if station<0 or station>63: return ERR_INVALID_PARAMETER
	var config := ConfigFile.new(); var loaded := config.load(path)
	if loaded not in [OK,ERR_FILE_NOT_FOUND]: return loaded
	var safe := Settings.normalize(scope); safe.single=false; safe.armed=false
	config.set_value("station_%d"%station,"scope",safe)
	var temporary := path+".pending"
	var error := config.save(temporary)
	if error!=OK: return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))
