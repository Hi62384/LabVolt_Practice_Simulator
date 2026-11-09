extends RefCounted
static func station(require_integrated := false) -> RefCounted:
	var Original := load("res://scripts/dc_station.gd")
	var instance: RefCounted=Original.new()
	if int(instance.scope.get("schema",0))>=2:
		print("SCOPE_CORE_MODE integrated")
		return instance
	if require_integrated:
		push_error("Integrated DCStation scope v2 hooks are missing")
		return null
	var source := FileAccess.get_file_as_string("res://scripts/dc_station.gd").replace("\r\n","\n")
	var changes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/remaining/scope/fixtures/core_edits.json"))
	for edit in changes["scripts/dc_station.gd"]:
		if source.count(str(edit.old))!=1:
			push_error("Scope proposal does not match current DCStation source")
			return null
		source=source.replace(str(edit.old),str(edit.new))
	var script := GDScript.new(); script.source_code=source
	if script.reload()!=OK:
		push_error("Scope proposal failed to compile")
		return null
	print("SCOPE_CORE_MODE proposed hook applied in-memory only; production core unchanged")
	return script.new()

