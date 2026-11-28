extends RefCounted
## Per-device causal social receipts. Host scalar state wins divergent branches;
## callers merge unique memories separately, then record the reconciled result.
const MAX_BYTES:=16*1024*1024
const MAX_RECORDS:=2048
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
static var _validator:=Memory.new()
var path:=""
var owner:=""
var records: Dictionary={}
var conflicts: Array=[]
var blocked:=false
var last_error:=OK
var dirty:=false

func configure(identity: String) -> Error:
	if identity.is_empty() or identity.length()>128:return ERR_INVALID_PARAMETER
	if owner==identity and not path.is_empty():return save() if dirty else last_error
	# A receipt that could not reach disk still belongs to its original device
	# profile. Do not silently discard it when another profile is selected.
	if dirty:
		var pending_error:=save()
		if pending_error!=OK:return pending_error
	owner=identity
	path="user://character_memory/"+identity.sha256_text()+".student-social.json"
	records.clear();conflicts.clear();blocked=false;last_error=OK;dirty=false
	var raw:=_read(path)
	if raw.is_empty():
		raw=_read(path+".bak")
		dirty=not raw.is_empty()
	if raw.is_empty():
		blocked=FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak")
		last_error=ERR_FILE_CORRUPT if blocked else OK
	else:
		records=raw.records;conflicts=raw.get("conflicts",[])
	return last_error

func observe(character: String,player: String,snapshot: Dictionary) -> Dictionary:
	if snapshot.is_empty() or blocked:return {}
	var key:=character+":"+player
	if not records.has(key) and records.size()>=MAX_RECORDS:return {}
	var previous: Dictionary=records.get(key,{})
	var fingerprint:=digest(snapshot)
	if str(previous.get("digest",""))==fingerprint:
		return previous.duplicate(true) if not dirty or save()==OK else {}
	var parents: Array=previous.get("parents",[]).duplicate()
	if not previous.is_empty():parents.append(str(previous.digest))
	while parents.size()>64:parents.pop_front()
	var entry:={"version":1,"character":character,"player":player,"revision":int(previous.get("revision",0))+1,"digest":fingerprint,"parents":parents,"snapshot":snapshot.duplicate(true)}
	if not valid(entry):last_error=ERR_INVALID_DATA;return {}
	records[key]=entry
	dirty=true
	return entry.duplicate(true) if save()==OK else {}

func classify(entry: Dictionary) -> String:
	if not valid(entry):return "invalid"
	var key:=str(entry.character)+":"+str(entry.player)
	var current: Dictionary=records.get(key,{})
	if current.is_empty():return "new"
	if current.digest==entry.digest:return "same"
	if entry.digest in current.parents:return "older"
	if current.digest in entry.parents:return "descendant"
	return "conflict"

func receive(entry: Dictionary,merged_snapshot: Dictionary) -> bool:
	if blocked or not valid(entry) or merged_snapshot.is_empty():return false
	var key:=str(entry.character)+":"+str(entry.player)
	var kind:=classify(entry)
	if kind in ["same","older"]:return not dirty or save()==OK
	if not records.has(key) and records.size()>=MAX_RECORDS:return false
	var parents: Array=entry.parents.duplicate()
	var previous: Dictionary=records.get(key,{})
	for digest in previous.get("parents",[])+[previous.get("digest",""),entry.digest]:
		if not str(digest).is_empty() and digest not in parents:parents.append(digest)
	while parents.size()>64:parents.pop_front()
	var next: Dictionary=entry.duplicate(true)
	next.parents=parents
	next.snapshot=merged_snapshot.duplicate(true)
	next.digest=digest(merged_snapshot)
	next.revision=maxi(int(entry.revision),int(previous.get("revision",0)))+1
	if not valid(next):last_error=ERR_INVALID_DATA;return false
	if kind=="conflict":
		conflicts.append({"character":entry.character,"local":records[key].digest,"incoming":entry.digest})
		if conflicts.size()>64:conflicts.pop_front()
	records[key]=next
	dirty=true
	return save()==OK

static func valid(entry: Dictionary) -> bool:
	if entry.get("version")!=1 or not entry.get("character") is String or not entry.get("player") is String:return false
	if entry.character.length()>64 or entry.player.length()>64 or entry.character.is_empty() or entry.player.is_empty():return false
	if not entry.get("snapshot") is Dictionary:return false
	if not entry.get("parents") is Array or entry.parents.size()>64:return false
	for digest in entry.parents:
		if not digest is String or digest.length()!=64:return false
	if not (entry.get("revision") is float or entry.get("revision") is int) or not is_finite(float(entry.revision)) or float(entry.revision)<1 or float(entry.revision)>1000000000:return false
	if entry.player=="_npc_mood":
		if entry.snapshot.size()!=1 or not entry.snapshot.get("mood") is Dictionary or not _validator.valid_mood_record(entry.character,entry.snapshot.mood):return false
	elif not _validator.valid_social_record(entry.character,entry.player,entry.snapshot):return false
	if JSON.stringify(entry).to_utf8_buffer().size()>300000:return false
	return str(entry.get("digest",""))==digest(entry.snapshot)

func save() -> Error:
	if owner.is_empty() or not path.begins_with("user://character_memory/"):
		last_error=ERR_UNCONFIGURED;return last_error
	if blocked:return ERR_FILE_CORRUPT
	var old:=_read(path)
	var backup:=_read(path+".bak")
	if old.is_empty() and backup.is_empty() and (FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak")):
		blocked=true;last_error=ERR_FILE_CORRUPT;return last_error
	for source in [path,path+".bak"]:
		if FileAccess.file_exists(source) and (old.is_empty() if source==path else backup.is_empty()):
			var destination: String=source+".corrupt-"+FileAccess.get_sha256(source)
			if not FileAccess.file_exists(destination):
				var preserved:=DirAccess.copy_absolute(source,destination)
				if preserved!=OK:last_error=preserved;return last_error
	var error:=DirAccess.make_dir_recursive_absolute("user://character_memory")
	if error!=OK:last_error=error;return last_error
	var serialized:=JSON.stringify({"version":1,"records":records,"conflicts":conflicts})
	if serialized.to_utf8_buffer().size()>MAX_BYTES:last_error=ERR_OUT_OF_MEMORY;return last_error
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:last_error=FileAccess.get_open_error();return last_error
	file.store_string(serialized);file.flush();error=file.get_error();file.close()
	if error!=OK:last_error=error;return last_error
	if _read(path+".tmp").is_empty():last_error=ERR_INVALID_DATA;return last_error
	if not _read(path).is_empty():
		error=DirAccess.copy_absolute(path,path+".bak")
		if error!=OK:last_error=error;return last_error
	last_error=DirAccess.rename_absolute(path+".tmp",path)
	if last_error==OK:dirty=false
	return last_error

func _read(source: String) -> Dictionary:
	var file:=FileAccess.open(source,FileAccess.READ)
	if file==null:return {}
	if file.get_length()>MAX_BYTES:file.close();return {}
	var raw: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not raw is Dictionary or raw.get("version")!=1 or not raw.get("records") is Dictionary or raw.records.size()>MAX_RECORDS:return {}
	if not raw.get("conflicts",[]) is Array or raw.get("conflicts",[]).size()>64:return {}
	for key in raw.records:
		if not raw.records[key] is Dictionary or not valid(raw.records[key]):return {}
		if key!=str(raw.records[key].character)+":"+str(raw.records[key].player):return {}
	return raw

static func digest(value: Variant) -> String:
	# Normalize integer/float representation before hashing JSON across devices.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)),"",true).sha256_text()
