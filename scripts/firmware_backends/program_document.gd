extends RefCounted
## Data-only per-instance firmware document; never resolves host executables.
const Schema=preload("res://scripts/inventory_authority/firmware_schema.gd")
const LIVE_LIMIT=786432
static func validate(board: String,firmware: Dictionary,sources: Dictionary,live := false) -> Dictionary:
	if board not in ["uno","nano","pico"] or firmware.get("board","")!=board:return {"ok":false,"error":"Image target does not match selected board"}
	if not Schema.record(firmware):return {"ok":false,"error":"Invalid compiled image: check format, checksum, flash bounds and vector table"}
	if not Schema.files(sources,false):return {"ok":false,"error":"Source project exceeds filename, file count or size limits"}
	var bytes := JSON.stringify({"native_firmware":firmware,"native_sources":sources}).to_utf8_buffer().size()
	if live and bytes>LIVE_LIMIT:return {"ok":false,"error":"Program exceeds the 768 KiB live upload limit; save locally or use a smaller compiled image"}
	return {"ok":true,"bytes":bytes}
static func merged(part: Dictionary,override: Dictionary) -> Dictionary:
	var result := part.duplicate(true)
	for key in ["native_firmware","native_sources","run"]:
		if override.has(key):result[key]=override[key].duplicate(true) if override[key] is Dictionary else override[key]
	return result
static func store(design: Dictionary,id: String,firmware: Dictionary,sources: Dictionary) -> void:
	if not design.get("programs") is Dictionary:design.programs={}
	var record: Dictionary=design.programs.get(id,{}).duplicate(true)
	record.native_firmware=firmware.duplicate(true);record.native_sources=sources.duplicate(true)
	if not record.has("run"):record.run=true
	design.programs[id]=record

static func compiler_map_key(board: String,firmware: Dictionary,sources: Dictionary) -> String:
	var canonical := [board,str(firmware.get("format","")),str(firmware.get("image","")),int(firmware.get("vector_offset",0)),preload("res://scripts/firmware_toolchain/source_request.gd").source_hash(sources)]
	return JSON.stringify(canonical).sha256_text()

static func save_compiler_map(board: String,firmware: Dictionary,sources: Dictionary,source_map: Array) -> void:
	if not validate(board,firmware,sources).ok or source_map.size()>16384:return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://firmware_compiler_maps"))
	var file := FileAccess.open("user://firmware_compiler_maps/"+compiler_map_key(board,firmware,sources)+".json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(source_map));file.close()

static func load_compiler_map(board: String,firmware: Dictionary,sources: Dictionary) -> Array:
	var path := "user://firmware_compiler_maps/"+compiler_map_key(board,firmware,sources)+".json"
	if not FileAccess.file_exists(path):return []
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:return []
	if file.get_length()>2097152:file.close();return []
	var value: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not value is Array or value.size()>16384:return []
	var verified := preload("res://scripts/firmware_toolchain/artifact.gd").validate({"ok":true,"firmware":firmware,"source_map":value,"artifact":{"source_sha256":preload("res://scripts/firmware_toolchain/source_request.gd").source_hash(sources)}},board,sources)
	if not verified.get("ok",false):return []
	var result: Array=[]
	for entry in value:
		if not entry is Dictionary or not sources.has(str(entry.get("file",""))) or int(entry.get("line",0))<1 or int(entry.get("pc",-1))<0 or int(entry.get("pc",0))>0xffffffff:return []
		result.append({"file":str(entry.file),"line":int(entry.line),"pc":int(entry.pc)})
	return result
