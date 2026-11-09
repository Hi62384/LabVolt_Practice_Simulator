extends RefCounted
const Schema=preload("res://scripts/inventory_authority/firmware_schema.gd")
const Request=preload("res://scripts/firmware_toolchain/source_request.gd")
static func validate(result: Dictionary,board: String,files: Dictionary) -> Dictionary:
	if not result.get("ok",false):return result
	var firmware: Variant=result.get("firmware",{})
	if not firmware is Dictionary or firmware.get("board","")!=board or not Schema.record(firmware):return Request.failure("Compiler output failed existing board image validation","invalid_artifact")
	if str(result.get("artifact",{}).get("source_sha256",""))!=Request.source_hash(files):return Request.failure("Compiled output belongs to a different source revision","stale_artifact")
	var source_map: Variant=result.get("source_map",[])
	if not source_map is Array or source_map.size()>16384:return Request.failure("Compiler source map exceeds bounds","invalid_artifact")
	for entry in source_map:
		if not entry is Dictionary or not files.has(str(entry.get("file",""))):return Request.failure("Invalid source map","invalid_artifact")
		if not (entry.get("pc") is int or entry.get("pc") is float) or not (entry.get("line") is int or entry.get("line") is float):return Request.failure("Non-numeric source map location","invalid_artifact")
		var pc_value := float(entry.get("pc",-1));var line_value := float(entry.get("line",0))
		if not is_finite(pc_value) or pc_value!=floor(pc_value) or not is_finite(line_value) or line_value!=floor(line_value):return Request.failure("Non-integral source map location","invalid_artifact")
		if pc_value<0 or pc_value>0xffffffff or line_value<1:return Request.failure("Source location is outside bounds","invalid_artifact")
		if int(entry.line)>str(files[str(entry.file)]).split("\n").size():return Request.failure("Source map line is outside the supplied source","invalid_artifact")
		if board in ["uno","nano"] and (int(entry.pc)>=32768 or int(entry.pc)%2!=0):return Request.failure("Source address exceeds AVR flash or instruction alignment","invalid_artifact")
		if board=="pico" and (int(entry.pc)<0x10000000 or int(entry.pc)>=0x10000000+Marshalls.base64_to_raw(str(firmware.image)).size() or int(entry.pc)%2!=0):return Request.failure("Source address exceeds compiled Pico flash","invalid_artifact")
	return result
