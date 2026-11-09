extends RefCounted
## LabVoltScript projects only. Includes resolve against an in-memory file map;
## never host paths. Each file's numeric jumps remain local after flattening.
const Runtime=preload("res://scripts/firmware_runtime.gd")
static func native_request(board: String,files: Dictionary,entry: String,language: String="") -> Dictionary:
	var request := {"schema":1,"board":board,"files":files,"entry":entry,"language":language if language!="" else "arduino_cpp" if board in ["uno","nano"] else "pico_cpp"}
	return preload("res://scripts/firmware_toolchain/source_request.gd").validate(request)
static func filename_ok(name: String) -> bool:
	if name.length()>48 or not name.ends_with(".lvs"):return false
	for c in name:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-." :return false
	return not name.begins_with(".") and not ".." in name

static func build(files: Dictionary,entry := "main.lvs") -> Dictionary:
	if files.is_empty() or files.size()>16:return failure(entry,1,"Project requires 1–16 files")
	for name in files:
		if not filename_ok(str(name)) or not files[name] is String:return failure(str(name),1,"Use simple .lvs filenames and text contents")
	var context := {"rows":[],"stack":[],"seen":[],"error":{},"bytes":0}
	visit(files,entry,context)
	if not context.error.is_empty():return context.error
	var rows: Array=context.rows
	var map := {}
	for i in rows.size():map[str(rows[i].file)+":"+str(rows[i].line)]=i+1
	var source: Array=[]
	for row in rows:
		var t: PackedStringArray=str(row.text).split("#")[0].strip_edges().replace("\t"," ").split(" ",false)
		var jump := 1 if t.size()==2 and t[0]=="goto" else (5 if t.size()==6 and t[0]=="if" and t[4]=="goto" else -1)
		if jump>=0 and t[jump].is_valid_int():
			var key := str(row.file)+":"+t[jump]
			if not map.has(key):return failure(row.file,row.line,"Jump target must be an instruction in the same file")
			t[jump]=str(map[key]);source.append(" ".join(t))
		else:source.append(row.text)
	var flattened := "\n".join(source)
	var result := Runtime.compile(flattened)
	if not result.ok:
		var row: Dictionary=rows[clampi(int(result.line)-1,0,rows.size()-1)] if not rows.is_empty() else {"file":entry,"line":1}
		return failure(row.file,row.line,result.error)
	return {"ok":true,"source":flattened,"locations":rows,"program":result.program}

static func failure(file: String,line: int,message: String) -> Dictionary:
	return {"ok":false,"file":file,"line":line,"error":message}

static func visit(files: Dictionary,name: String,context: Dictionary) -> void:
	if not files.has(name):context.error=failure(name,1,"Included file not found");return
	if name in context.stack:context.error=failure(name,1,"Circular include");return
	if name in context.seen:context.error=failure(name,1,"Include each file once");return
	context.stack.append(name);context.seen.append(name)
	var source: String=files[name]
	context.bytes+=source.length()
	if context.bytes>8192:context.error=failure(name,1,"Project exceeds 8192 characters");return
	var lines := source.split("\n")
	for i in lines.size():
		var clean := lines[i].strip_edges()
		if clean.begins_with("#include"):
			var requested := clean.trim_prefix("#include").strip_edges()
			if requested.length()<3 or not requested.begins_with('"') or not requested.ends_with('"'):
				context.error=failure(name,i+1,'Use #include "filename.lvs"');return
			visit(files,requested.substr(1,requested.length()-2),context)
			if not context.error.is_empty():return
		else:context.rows.append({"file":name,"line":i+1,"text":lines[i]})
		if context.rows.size()>256:context.error=failure(name,i+1,"Project exceeds 256 expanded lines");return
	context.stack.pop_back()
