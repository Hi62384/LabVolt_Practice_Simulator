extends RefCounted
## Small authoritative metadata only. File bytes stay in the client's archive.
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Config=preload("res://scripts/campus/items/equipment_configuration.gd")
const PRICES:={8:20,32:40,64:65,150:120}
const MAX_DRIVES:=128
const LOCATIONS:=["hotbar","cabinet","connected","lost","handoff"]

static func valid(dorm: Dictionary) -> bool:
	var drives: Variant=dorm.get("usb_drives",{})
	if not drives is Dictionary or drives.size()>MAX_DRIVES:return false
	var carried: Variant=dorm.get("carry_items",[])
	if not carried is Array:return false
	for id in drives:
		if not id is String or id.length()!=32 or not id.is_valid_hex_number() or id!=id.to_lower():return false
		var item: Variant=drives[id]
		if not item is Dictionary or not item.get("name") is String or not Archive.valid_name(item.name):return false
		if item.size()!=3+int(item.has("configuration")):return false
		var capacity: Variant=item.get("capacity_mb")
		if not (capacity is int or capacity is float) or not is_finite(float(capacity)) or float(capacity)!=floor(float(capacity)) or not PRICES.has(int(capacity)) or item.get("location","") not in LOCATIONS:return false
		if item.has("configuration") and not Config.valid_usb_pending({"capacity_mb":capacity,"configuration":item.configuration}):return false
		if (item.location=="hotbar") != ("usb:"+id in carried):return false
	for key in carried:
		if key is String and key.begins_with("usb:") and not drives.has(key.trim_prefix("usb:")):return false
	return true

static func rename(dorm: Dictionary,id: String,value: String) -> bool:
	if not valid(dorm) or not dorm.get("usb_drives",{}).has(id) or not Archive.valid_name(value):return false
	dorm.usb_drives[id].name=value.strip_edges()
	return true
