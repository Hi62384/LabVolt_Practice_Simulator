extends RefCounted
## Logical files only: no OS paths, commands, URLs or executable handles.
const MAX_FILES := 32
const MAX_FILE_BYTES := 32768
const MAX_TOTAL_BYTES := 262144
static func path(raw: String) -> String:
	if raw.length()<1 or raw.length()>96 or raw.begins_with("/") or raw.contains("\\") or raw.contains(":"):return ""
	var parts := raw.split("/",true)
	if parts.size()>4:return ""
	for part in parts:
		if part.is_empty() or part in [".",".."] or part.length()>32:return ""
		for c in part:
			if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":return ""
	return "/".join(parts)
static func validate(data: Dictionary) -> bool:
	if data.size()>MAX_FILES:return false
	var total := 0
	for key in data:
		if not key is String or path(key)!=key:return false
		var item = data[key]
		if not item is Dictionary or item.size()!=2 or not item.get("text") is String or not item.get("version") is int:return false
		if item.version<1 or item.version>2147483646:return false
		var size: int=item.text.to_utf8_buffer().size()
		if size>MAX_FILE_BYTES:return false
		total+=size
	return total<=MAX_TOTAL_BYTES
static func save(files: Dictionary, raw: String, text: String, expected: int) -> Dictionary:
	var key := path(raw)
	if key.is_empty():return {"error":"Invalid virtual path"}
	var current: int=files.get(key,{}).get("version",0)
	if current!=expected:return {"error":"File version conflict"}
	var next := files.duplicate(true)
	next[key]={"text":text,"version":current+1}
	if not validate(next):return {"error":"File quota exceeded"}
	return {"files":next}
