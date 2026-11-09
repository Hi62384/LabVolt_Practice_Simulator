extends RefCounted
## Stores only explicitly ungraded practice, under the host's persistent profile identity.
const MAX_BYTES := 12 * 1024 * 1024

static func _path(identity: String) -> String:
	return "user://practice_sheets_" + identity.sha256_text().left(32) + ".bin"

static func read(identity: String) -> Array:
	if identity.length() != 48 or not identity.is_valid_hex_number():return []
	var file := FileAccess.open(_path(identity), FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:return []
	var value: Variant = file.get_var(false)
	if not value is Array or value.size() > 6:return []
	var sheets: Array = []
	for sheet in value:
		if not sheet is Dictionary or not sheet.get("project") is Dictionary:continue
		if sheet.project.get("practice_scope") != "ungraded" or not sheet.get("answers") is Dictionary or not sheet.get("strokes") is Dictionary:continue
		sheets.append(sheet)
	return sheets

static func write(identity: String, papers: Dictionary) -> Error:
	if identity.length() != 48 or not identity.is_valid_hex_number():return ERR_INVALID_PARAMETER
	var sheets: Array = []
	for sheet in papers.values():
		if sheet.get("identity") != identity or sheet.get("project", {}).get("practice_scope") != "ungraded":continue
		var draft: Dictionary = sheet.duplicate(true)
		draft.erase("edit_history")
		sheets.append(draft)
		if sheets.size() == 6:break
	if var_to_bytes(sheets).size() > MAX_BYTES:return ERR_OUT_OF_MEMORY
	var target := _path(identity)
	var file := FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if file == null:return FileAccess.get_open_error()
	file.store_var(sheets, false)
	var error := file.get_error()
	file.close()
	if error != OK:return error
	return DirAccess.rename_absolute(target + ".tmp", target)

