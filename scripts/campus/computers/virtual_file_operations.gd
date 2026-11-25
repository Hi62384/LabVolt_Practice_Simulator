extends RefCounted

const Files = preload("res://scripts/campus/computers/virtual_files.gd")
const Zip = preload("res://scripts/campus/computers/VirtualZip.cs")
const ArchiveLimit := 8 * 1024 * 1024

static func valid(path: String) -> bool:
	return not path.is_empty() and Files.path(path)==path and not path.to_lower().begins_with(".recycle")

static func apply(drive: RefCounted, operation: String, source: String, target: String) -> String:
	if not valid(source) or not valid(target) or not drive.entries.has(source):
		return "Choose an existing source and a valid destination."
	if drive.entries.has(target) or target.begins_with(source+"/"):
		return "Choose an unused destination outside the source folder."
	var parent:=target.get_base_dir()
	if not parent.is_empty() and drive.entries.get(parent,{}).get("type","")!="folder":
		return "The destination folder does not exist."
	var staged := {}
	var added_bytes := 0
	var now := int(Time.get_unix_time_from_system())
	match operation:
		"copy":
			for path: String in drive.entries:
				if path!=source and not path.begins_with(source+"/"):continue
				var destination:=target+path.substr(source.length())
				if not valid(destination) or drive.entries.has(destination):return "A copied path is too long or already exists."
				var entry: Dictionary=drive.entries[path].duplicate()
				entry.modified=now
				staged[destination]=entry
				if entry.type=="file":added_bytes+=entry.data.size()
		"zip":
			if target.get_extension().to_lower()!="zip":return "Give the archive a .zip extension."
			var archive := {}
			var base:=source.get_base_dir()
			for path: String in drive.entries:
				if path!=source and not path.begins_with(source+"/"):continue
				var name:=path if base.is_empty() else path.substr(base.length()+1)
				var entry: Dictionary=drive.entries[path]
				if entry.type=="folder":archive[name+"/"]=PackedByteArray()
				else:archive[name]=entry.data
			var packed: PackedByteArray=Zip.new().Pack(archive)
			if packed.is_empty():return "The folder exceeds this computer’s ZIP limits."
			staged[target]={"type":"file","data":packed,"modified":now}
			added_bytes=packed.size()
		"extract":
			var entry: Dictionary=drive.entries[source]
			if source.get_extension().to_lower()!="zip" or entry.type!="file" or entry.data.size()>ArchiveLimit:
				return "Choose a ZIP file within the 8 MiB archive limit."
			var result: Dictionary=Zip.new().Unpack(entry.data,drive.capacity-drive.used_bytes())
			if result.has("error"):return result.error
			staged[target]={"type":"folder","modified":now}
			for name: String in result.files:
				var path:=target+"/"+name.trim_suffix("/")
				if not valid(path):return "The ZIP contains a path this workspace cannot store."
				var folder:=name.ends_with("/")
				if staged.get(path,{}).get("type","")=="file" or (staged.has(path) and not folder):
					return "The ZIP contains conflicting paths."
				staged[path]={"type":"folder","modified":now} if folder else {"type":"file","data":result.files[name],"modified":now}
				added_bytes+=result.files[name].size()
				var ancestor:=path.get_base_dir()
				while ancestor!=target:
					if staged.get(ancestor,{}).get("type","")=="file":return "The ZIP contains conflicting paths."
					if not staged.has(ancestor):staged[ancestor]={"type":"folder","modified":now}
					ancestor=ancestor.get_base_dir()
		_:return "Unsupported file operation."
	if drive.entries.size()+staged.size()>drive.MAX_ENTRIES or drive.used_bytes()+added_bytes>drive.capacity:
		return "This drive does not have enough space for the operation."
	drive.entries.merge(staged)
	return ""
