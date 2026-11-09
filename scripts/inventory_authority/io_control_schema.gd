extends RefCounted
# Persistence boundary for the IO worker v1 contract. This stores input settings,
# never client-published display/runtime state. The host reducer owns live edits.
const FIELDS := {
	"io_encoder":["revision","detent"],"io_keypad":["revision","keys"],
	"io_slider":["revision","x"],"io_joystick":["revision","x","y","pressed"],
	"io_selector":["revision","position"],"xpt2046":["revision","x","y","pressed"]}
static func kinds(parts: Array,definitions: Dictionary,prefix: String,depth: int=0) -> Dictionary:
	var result := {}
	if depth>=8:return result
	for part in parts:
		if not part is Dictionary:return result
		var id := prefix+str(part.get("id",""));var type := str(part.get("type",""))
		if FIELDS.has(type):result[id]=type
		elif type.begins_with("ic:") and definitions.get(type) is Dictionary and definitions[type].get("parts") is Array:
			result.merge(kinds(definitions[type].parts,definitions,id+"/",depth+1))
	return result
static func valid(saved: Variant,parts: Array,definitions: Dictionary,prefix: String="board/") -> bool:
	if not saved is Dictionary or saved.size()>64 or var_to_bytes(saved).size()>32768:return false
	var devices := kinds(parts,definitions,prefix)
	for id in saved:
		if not id is String or id.length()>256 or not devices.has(id) or not saved[id] is Dictionary:return false
		for key in saved[id]:
			if key not in FIELDS[devices[id]]:return false
			var value=saved[id][key]
			if key=="pressed":
				if not value is bool:return false
				continue
			if not (value is int or value is float) or not is_finite(float(value)):return false
			if key in ["x","y"]:
				if value<0 or value>1:return false
			else:
				if float(value)!=floor(float(value)):return false
				if key=="detent":
					if absf(float(value))>100000:return false
				elif value<0 or value>({"revision":2147483647,"keys":4095,"position":2}.get(key,0)):return false
	return true
