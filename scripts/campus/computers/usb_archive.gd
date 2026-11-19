extends RefCounted
## Client-local contents of one uniquely identified USB drive. Ownership and
## insertion permissions must be checked by inventory authority before use.
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const CAPACITIES_MB:=[8,32,64,150]
const MAX_ENTRIES:=4096
const MAX_OVERHEAD:=8*1024*1024

static func path(owner: String,id: String) -> String:
	if owner.length()!=48 or not owner.is_valid_hex_number() or id.length()!=32 or not id.is_valid_hex_number():return ""
	return "user://usb_%s_%s.dat" % [owner.to_lower(),id.to_lower()]

static func valid_name(value: String) -> bool:
	if value.strip_edges().is_empty() or value.length()>40:return false
	for character in value:
		if character.unicode_at(0)<32 or character.unicode_at(0)==127:return false
	return true

static func _valid_entries(entries: Variant,capacity: int) -> bool:
	if not entries is Dictionary or entries.size()>MAX_ENTRIES:return false
	var used:=0
	for key in entries:
		if not key is String or not Drive.valid_path(key) or not entries[key] is Dictionary:return false
		var entry: Dictionary=entries[key]
		var has_timestamp:=int(entry.has("modified"))
		if has_timestamp and (not entry.modified is int or entry.modified<0 or entry.modified>253402300799):return false
		if entry.get("type","")=="folder":
			if entry.size()!=1+has_timestamp:return false
		elif entry.get("type","")=="file":
			if entry.size()!=2+has_timestamp or not entry.get("data") is PackedByteArray:return false
			used+=entry.data.size()
			if used>capacity:return false
		else:return false
		var parent_index: int=key.rfind("/")
		if parent_index>=0:
			var parent: String=key.left(parent_index)
			if not entries.get(parent,{}) is Dictionary or entries.get(parent,{}).get("type","")!="folder":return false
	return true

static func save(owner: String,id: String,name: String,capacity_mb: int,drive: RefCounted) -> Error:
	var target:=path(owner,id)
	if target.is_empty() or not valid_name(name) or capacity_mb not in CAPACITIES_MB or drive==null:return ERR_INVALID_PARAMETER
	var limit:=capacity_mb*1024*1024
	if not _valid_entries(drive.entries,limit):return ERR_INVALID_DATA
	var file:=FileAccess.open(target+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_var({"schema":1,"owner":owner.to_lower(),"id":id.to_lower(),"name":name,"capacity_mb":capacity_mb,"entries":drive.entries},false)
	file.flush();var error:=file.get_error();file.close()
	if error!=OK:return error
	if _load_file(target+".tmp",owner,id,capacity_mb).has("error"):return ERR_INVALID_DATA
	error=DirAccess.copy_absolute(target+".tmp",target+".bak.tmp")
	if error!=OK:return error
	error=DirAccess.rename_absolute(target+".bak.tmp",target+".bak")
	if error!=OK:return error
	return DirAccess.rename_absolute(target+".tmp",target)

static func load(owner: String,id: String,capacity_mb: int) -> Dictionary:
	var target:=path(owner,id)
	if target.is_empty() or capacity_mb not in CAPACITIES_MB:return {"error":"Invalid drive identity"}
	var primary:=_load_file(target,owner,id,capacity_mb)
	if not primary.has("error"):return primary
	var backup:=_load_file(target+".bak",owner,id,capacity_mb)
	if not backup.has("error"):
		backup.recovered=true
		return backup
	return primary

static func _load_file(target: String,owner: String,id: String,capacity_mb: int) -> Dictionary:
	if not FileAccess.file_exists(target):return {"error":"Drive data not found"}
	var file:=FileAccess.open(target,FileAccess.READ)
	if file==null:return {"error":"Unable to open drive"}
	if file.get_length()>capacity_mb*1024*1024+MAX_OVERHEAD:
		file.close()
		return {"error":"Drive data exceeds capacity"}
	var value: Variant=file.get_var(false)
	file.close()
	if not value is Dictionary or value.get("schema")!=1 or value.get("owner")!=owner.to_lower() or value.get("id")!=id.to_lower() or value.get("capacity_mb")!=capacity_mb or not value.get("name") is String or not valid_name(value.name) or not _valid_entries(value.get("entries"),capacity_mb*1024*1024):
		return {"error":"Drive data is invalid"}
	var drive=Drive.new(capacity_mb*1024*1024);drive.entries=value.entries.duplicate(true)
	return {"name":value.name,"drive":drive}
