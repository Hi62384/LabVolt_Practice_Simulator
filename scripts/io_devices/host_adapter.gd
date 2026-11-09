extends RefCounted
## Optional helpers for the shared dispatch owner. No scene, save, or RPC ownership.
const Catalog=preload("res://scripts/io_devices/catalog.gd")
const Devices=preload("res://scripts/io_devices/devices.gd")
const Controls=preload("res://scripts/io_devices/controls.gd")
const Replication=preload("res://scripts/io_devices/replication.gd")

static func electrical(parts: Array) -> Array:
	return parts.filter(func(part):return part.get("kind","")!="io_device")

static func tick(parts: Array,result: Dictionary,states: Dictionary,dt: float) -> Dictionary:
	var out := {}
	for part in parts:
		if part.get("kind","")=="io_device":out[part.id]=Devices.tick(part,result,states.get(part.id,{}),dt)
	return out

static func publication(parts: Array,states: Dictionary) -> Dictionary:
	var out := {}
	for part in parts:
		if part.get("kind","")=="io_device":out[part.id]=Replication.public_state(part.model,states.get(part.id,{}))
	return out

## Restrict saved controls to known defaults and finite bounded scalar values.
## device_kinds uses fully qualified instance IDs after hierarchical expansion.
static func validate_controls(saved: Variant,device_kinds: Dictionary) -> String:
	if not saved is Dictionary or saved.size()>64:return "Invalid I/O controls"
	for id in saved:
		if not device_kinds.has(id) or not saved[id] is Dictionary:return "Unknown I/O input instance"
		var defaults := Controls.defaults(str(device_kinds[id]))
		if defaults.is_empty():return "I/O output cannot have input controls"
		for key in saved[id]:
			if not defaults.has(key):return "Unknown I/O input field"
			var value: Variant=saved[id][key]
			if key=="pressed":
				if not value is bool:return "Invalid I/O switch"
			elif not Controls.number(value):return "Invalid I/O number"
			elif key in ["x","y"]:
				if float(value)<0 or float(value)>1:return "Invalid I/O axis"
			elif float(value)!=floor(float(value)):return "Invalid integer I/O field"
			elif key=="revision" and (float(value)<0 or float(value)>2147483647):return "Invalid I/O revision"
			elif key=="detent" and absf(float(value))>100000:return "Invalid I/O detent"
			elif key=="keys" and (float(value)<0 or float(value)>4095):return "Invalid keypad mask"
			elif key=="position" and (float(value)<0 or float(value)>2):return "Invalid selector position"
	return ""

static func kinds(parts: Array,definitions: Dictionary,prefix: String="board/",depth: int=0) -> Dictionary:
	var out := {}
	if depth>=8:return out
	for part in parts:
		var id := prefix+str(part.id);var type := str(part.type)
		if type.begins_with("ic:") and definitions.has(type):out.merge(kinds(definitions[type].parts,definitions,id+"/",depth+1))
		elif Catalog.supports(type):out[id]=type
	return out
