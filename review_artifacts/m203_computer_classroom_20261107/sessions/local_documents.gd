extends RefCounted
const Files = preload("res://scripts/campus/computers/virtual_files.gd")
## Only this local client accesses its own profile. Never accept a remote profile key.
static func location(identity: String) -> String:
	if identity.length()!=48 or not identity.is_valid_hex_number():return ""
	return "user://computer_documents_"+identity.sha256_text()+".json"
static func load_documents(identity: String) -> Dictionary:
	var target := location(identity)
	if target.is_empty() or not FileAccess.file_exists(target):return {}
	var file := FileAccess.open(target,FileAccess.READ)
	if file==null or file.get_length()>2000000:return {}
	var envelope = JSON.parse_string(file.get_as_text())
	if not envelope is Dictionary:return {}
	var data = envelope.get("files",{})
	if not data is Dictionary:return {}
	# JSON numbers are floats; convert only verified integral bounded versions.
	for item in data.values():
		if not item is Dictionary:return {}
		var version = item.get("version",0)
		if not (version is float or version is int) or not is_finite(float(version)) or float(version)!=floor(float(version)):return {}
		item.version=int(version)
	return data if Files.validate(data) else {}
static func save_documents(identity: String, documents: Dictionary, editor: Dictionary = {}) -> Error:
	var target := location(identity)
	if target.is_empty() or not Files.validate(documents):return ERR_INVALID_DATA
	var file := FileAccess.open(target+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"files":documents,"editor":editor}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK:return error
	return DirAccess.rename_absolute(target+".tmp",target)
static func load_editor(identity: String) -> Dictionary:
	var target := location(identity)
	if target.is_empty() or not FileAccess.file_exists(target):return {}
	var file := FileAccess.open(target,FileAccess.READ)
	if file==null or file.get_length()>2000000:return {}
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("editor",{}) is Dictionary:return {}
	return data.get("editor",{}).duplicate(true)
