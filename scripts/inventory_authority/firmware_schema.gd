extends RefCounted
# Storage validation only. No guest execution, file includes, executable paths,
# runtime objects or process handles are accepted by this optional record schema.
static func name_ok(name: Variant,lv: bool) -> bool:
	if not name is String or name.is_empty() or name.length()>48 or name.begins_with(".") or ".." in name:return false
	for c in name:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":return false
	return not lv or name.ends_with(".lvs")
static func files(value: Variant,lv: bool) -> bool:
	if not value is Dictionary or value.size()>16:return false
	var total := 0
	for name in value:
		if not name_ok(name,lv) or not value[name] is String or value[name].length()>(8192 if lv else 65536):return false
		total+=value[name].length()
	return total<=(8192 if lv else 1048576)
static func record(value: Variant) -> bool:
	if not value is Dictionary:return false
	for key in value:
		if key not in ["schema","board","format","image","vector_offset"]:return false
	if value.get("schema")!=1 or not value.get("image") is String:return false
	if value.get("board") in ["uno","nano"]:
		if value.get("format")!="intel_hex" or value.has("vector_offset") or value.image.length()>131072:return false
		var regex := RegEx.new();regex.compile("^:([0-9a-fA-F]{2})+$")
		var ended := false;var base := 0
		for raw in value.image.strip_edges().split("\n"):
			var line := str(raw).trim_suffix("\r")
			if ended or regex.search(line)==null:return false
			var bytes := line.substr(1).hex_decode()
			if bytes.size()<5 or bytes.size()!=int(bytes[0])+5:return false
			var sum := 0
			for byte in bytes:sum+=int(byte)
			if sum%256!=0:return false
			var address := int(bytes[1])*256+int(bytes[2]);var kind := int(bytes[3])
			if kind==0:
				if base+address+int(bytes[0])>32768:return false
			elif kind==1 and bytes[0]==0:ended=true
			elif kind==4 and bytes[0]==2:base=(int(bytes[4])*256+int(bytes[5]))*65536
			else:return false
		return ended
	if value.get("board")=="pico":
		if value.get("format")!="bin_base64" or value.image.length()>2796204:return false
		var regex := RegEx.new();regex.compile("^[A-Za-z0-9+/]*={0,2}$")
		if regex.search(value.image)==null:return false
		if value.image.length()%4==1:return false
		var encoded: String=value.image
		while encoded.length()%4!=0:encoded+="="
		var bytes := Marshalls.base64_to_raw(encoded)
		if bytes.size()<8 or bytes.size()>2097152:return false
		var offset=value.get("vector_offset",256)
		if not (offset is int or offset is float) or not is_finite(float(offset)) or float(offset)!=floor(float(offset)) or offset<0 or offset>bytes.size()-8:return false
		var sp := bytes.decode_u32(int(offset));var pc := bytes.decode_u32(int(offset)+4)
		return sp>=0x20000000 and sp<=0x20042000 and (pc&1)==1 and pc>=0x10000000 and pc<0x10000000+bytes.size()
	return false
static func part(value: Dictionary) -> bool:
	for key in ["node_executable","backend_directory","process_handle","pid","native_runtime","bridge","executable","node_path"]:
		if value.has(key):return false
	if value.has("native_firmware") and not record(value.native_firmware):return false
	if value.has("native_sources") and not files(value.native_sources,false):return false
	if value.has("code_files") and not files(value.code_files,true):return false
	return true
