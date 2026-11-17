extends RefCounted
const Files = preload("res://scripts/campus/computers/virtual_files.gd")
const MAX_SAVE_BYTES := 2000000
## Only this local client accesses its own profile. Never accept a remote profile key.
static func location(identity: String) -> String:
	if identity.length()!=48 or not identity.is_valid_hex_number():return ""
	return "user://computer_documents_"+identity.sha256_text()+".json"

## Missing is a clean first use; every other read failure must block restore.
static func load_state(identity: String) -> Dictionary:
	var target := location(identity)
	if target.is_empty():return {"status":"error","message":"Invalid student profile for local documents."}
	if not FileAccess.file_exists(target):return {"status":"missing","files":{},"editor":{}}
	var file := FileAccess.open(target,FileAccess.READ)
	if file==null:return {"status":"error","message":"Local documents could not be opened."}
	if file.get_length()>MAX_SAVE_BYTES:return {"status":"error","message":"Local documents exceed the save limit."}
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK:
		return {"status":"error","message":"Local documents are damaged or use an unsupported format."}
	var envelope: Variant=parser.data
	if not envelope is Dictionary or not envelope.has("files") or not envelope.files is Dictionary:
		return {"status":"error","message":"Local documents are damaged or use an unsupported format."}
	var data: Dictionary=envelope.files
	# JSON numbers are floats; convert only verified integral bounded versions.
	for item in data.values():
		if not item is Dictionary:return {"status":"error","message":"Local document entries are damaged."}
		var version: Variant=item.get("version",0)
		if not (version is float or version is int) or not is_finite(float(version)) or float(version)!=floor(float(version)):
			return {"status":"error","message":"Local document versions are invalid."}
		item.version=int(version)
	if not Files.validate(data):return {"status":"error","message":"Local documents contain invalid files."}
	return {"status":"ok","files":data,"editor":_validated_editor(envelope.get("editor",{}),data)}

static func _validated_editor(value: Variant,files: Dictionary) -> Dictionary:
	if not value is Dictionary or value.is_empty():return {}
	if value.size()!=2 or not value.get("path") is String or not files.has(value.path):return {}
	var path: String=value.path
	if Files.path(path)!=path:return {}
	var cursor: Variant=value.get("cursor")
	if not (cursor is int or cursor is float) or not is_finite(float(cursor)) or float(cursor)!=floor(float(cursor)):return {}
	if cursor<0 or cursor>str(files[path].text).length():return {}
	return {"path":path,"cursor":int(cursor)}

static func save_documents(identity: String,documents: Dictionary,editor: Dictionary={}) -> Error:
	var target := location(identity)
	if target.is_empty() or not Files.validate(documents) or (not editor.is_empty() and _validated_editor(editor,documents).is_empty()):return ERR_INVALID_DATA
	# A damaged primary is never replaced by an automatic snapshot save.
	if FileAccess.file_exists(target) and load_state(identity).status!="ok":return ERR_FILE_CORRUPT
	var serialized:=JSON.stringify({"files":documents,"editor":editor})
	if serialized.to_utf8_buffer().size()>MAX_SAVE_BYTES:return ERR_INVALID_DATA
	var file := FileAccess.open(target+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(serialized)
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK:return error
	if FileAccess.file_exists(target):
		error=DirAccess.copy_absolute(target,target+".bak")
		if error!=OK:return error
	return DirAccess.rename_absolute(target+".tmp",target)
