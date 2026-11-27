extends RefCounted
## Versioned local checkpoints. The caller picks an identifier and controls sharing.
const Document=preload("res://scripts/procedural_animation/document.gd")
const Playback=preload("res://scripts/procedural_animation/playback.gd")
const ROOT:="user://procedural_visuals/"
const MAX_BYTES:=Document.MAX_BYTES+1400

static func save(id: String,player: RefCounted,replace := true) -> Error:
	if not Document._id(id) or player.scene.is_empty():return ERR_INVALID_PARAMETER
	if not replace and FileAccess.file_exists(ROOT+id+".json"):return ERR_ALREADY_EXISTS
	var data:=JSON.stringify({"version":1,"checkpoint":player.snapshot()})
	if data.to_utf8_buffer().size()>MAX_BYTES:return ERR_INVALID_DATA
	var error:=DirAccess.make_dir_recursive_absolute(ROOT)
	if error!=OK:return error
	var file:=FileAccess.open(ROOT+id+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(data)
	file.flush()
	error=file.get_error()
	file.close()
	return DirAccess.rename_absolute(ROOT+id+".tmp",ROOT+id+".json") if error==OK else error

static func load_playback(id: String) -> RefCounted:
	if not Document._id(id):return null
	var file:=FileAccess.open(ROOT+id+".json",FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES:return null
	var raw: Variant=JSON.parse_string(file.get_as_text())
	if not raw is Dictionary or raw.get("version")!=1 or not raw.get("checkpoint") is Dictionary:return null
	var player:=Playback.new()
	return player if player.restore_checkpoint(raw.checkpoint) else null
