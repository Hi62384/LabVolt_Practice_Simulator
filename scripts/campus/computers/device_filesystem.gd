extends RefCounted
## An isolated virtual drive. Paths never refer to the host operating system.
const MAX_CAPACITY := 150 * 1024 * 1024
const MAX_ENTRIES := 4096
const ExecutableIcons = preload("res://scripts/campus/computers/ExecutableIcon.cs")
var capacity: int
var _executable_icons: Dictionary = {}
var _icon_reader: RefCounted
var entries: Dictionary = {}:
	set(value):
		entries=value
		_executable_icons.clear()

func _init(bytes: int = MAX_CAPACITY) -> void:
	capacity = clampi(bytes, 0, MAX_CAPACITY)

static func valid_path(path: String) -> bool:
	if path.is_empty() or path.length() > 240 or path.begins_with("/") or path.ends_with("/") or path.contains("\\") or path.contains(":"):
		return false
	for part in path.split("/"):
		if part.is_empty() or part in [".", ".."] or part.length() > 80:
			return false
		for ch in part:
			if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127:
				return false
	return true

func _parent(path: String) -> String:
	var index := path.rfind("/")
	return "" if index < 0 else path.left(index)

func _parent_exists(path: String) -> bool:
	var parent := _parent(path)
	return parent.is_empty() or entries.get(parent, {}).get("type", "") == "folder"

func used_bytes() -> int:
	var used := 0
	for entry in entries.values():
		if entry.type == "file": used += entry.data.size()
	return used

func executable_icon(path: String) -> PackedByteArray:
	var file: Dictionary=entries.get(path,{})
	if file.get("type","")!="file":return PackedByteArray()
	if _executable_icons.has(path):return _executable_icons[path]
	if _icon_reader==null:_icon_reader=ExecutableIcons.new()
	var icon: PackedByteArray=_icon_reader.ReadIcon(file.data)
	if _executable_icons.size()>=128:_executable_icons.erase(_executable_icons.keys()[0])
	_executable_icons[path]=icon
	return icon

func make_folder(path: String) -> bool:
	if not valid_path(path) or not _parent_exists(path) or entries.has(path) or entries.size() >= MAX_ENTRIES:
		return false
	entries[path] = {"type": "folder", "modified": int(Time.get_unix_time_from_system())}
	return true

func write_file(path: String, data: PackedByteArray) -> bool:
	if not valid_path(path) or not _parent_exists(path): return false
	var previous: Dictionary = entries.get(path, {})
	if not previous.is_empty() and previous.type != "file": return false
	if previous.is_empty() and entries.size() >= MAX_ENTRIES: return false
	var old_size: int = previous.get("data", PackedByteArray()).size()
	if used_bytes() - old_size + data.size() > capacity: return false
	entries[path] = {"type": "file", "data": data.duplicate(), "modified": int(Time.get_unix_time_from_system())}
	_executable_icons.erase(path)
	return true

func remove(path: String) -> bool:
	if not entries.has(path): return false
	for name in entries.keys():
		if name == path or str(name).begins_with(path + "/"):
			entries.erase(name)
			_executable_icons.erase(name)
	return true

func move(source: String, target: String) -> bool:
	if not entries.has(source) or not valid_path(target) or entries.has(target) or not _parent_exists(target) or target.begins_with(source + "/"):
		return false
	var renamed := {}
	for name in entries.keys():
		if name == source or str(name).begins_with(source + "/"):
			var replacement: String = target + str(name).substr(source.length())
			if not valid_path(replacement) or (entries.has(replacement) and not (replacement == source or replacement.begins_with(source + "/"))): return false
			renamed[replacement] = entries[name]
	for name in entries.keys():
		if name == source or str(name).begins_with(source + "/"): entries.erase(name)
	entries.merge(renamed)
	return true

func clear() -> void:
	entries.clear()
