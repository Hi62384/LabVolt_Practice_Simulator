extends RefCounted
const EXTENSIONS := ["ino","cpp","c","h","hpp"]
const RESERVED := ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"]
static func name_ok(name: String) -> bool:
	if name.is_empty() or name.length()>48 or name.begins_with(".") or ".." in name or name.ends_with("."):return false
	for character in name:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":return false
	return name.get_slice(".",0).to_upper() not in RESERVED

static func validate(request: Dictionary) -> Dictionary:
	for key in request:
		if key not in ["schema","board","language","entry","files"]:return failure("Unknown compile option: "+str(key))
	if request.get("schema",0)!=1:return failure("Unknown compile request schema")
	var board := str(request.get("board",""));var language := str(request.get("language",""))
	if board not in ["uno","nano","pico"]:return failure("Unsupported compiler target")
	if language=="micropython":return failure("MicroPython source can be edited/imported, but the current RP2040 machine does not provide a verified MicroPython firmware runtime.","runtime_unavailable")
	if language!=("arduino_cpp" if board in ["uno","nano"] else "pico_cpp"):return failure("Language and board do not match")
	var files: Variant=request.get("files",{})
	if not files is Dictionary or files.is_empty() or files.size()>16:return failure("Use 1–16 source files")
	var names: Array[String]=[];var total := 0
	for key in files:
		var name := str(key)
		if not key is String or not name_ok(name) or name.get_extension() not in EXTENSIONS:return failure("Use simple .ino, .cpp, .c, .h or .hpp filenames")
		if name.to_lower() in names:return failure("Filenames must be unique without regard to letter case")
		names.append(name.to_lower())
		if not files[key] is String:return failure("Source contents must be text")
		var bytes: int=files[key].to_utf8_buffer().size();total+=bytes
		if bytes>65536 or files[key].to_utf8_buffer().has(0):return failure("Each source file must be at most 64 KiB without NUL characters")
	if total>1048576:return failure("Project exceeds 1 MiB")
	var entry := str(request.get("entry",""))
	if not files.has(entry) or entry.get_extension() not in ["ino","cpp","c"]:return failure("Choose an existing source entry file")
	return {"ok":true,"status":"validated","bytes":total,"source_sha256":source_hash(files)}

static func source_hash(files: Dictionary) -> String:
	var names: Array=files.keys();names.sort()
	var canonical: Array=[]
	for name in names:canonical.append([name,files[name]])
	return JSON.stringify(canonical).sha256_text()

static func failure(message: String,status: String="invalid_request") -> Dictionary:
	return {"ok":false,"status":status,"error":message,"diagnostics":[]}
