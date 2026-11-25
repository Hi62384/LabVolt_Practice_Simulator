extends RefCounted

const Packages=preload("res://scripts/campus/computers/application_package.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
const Files=preload("res://scripts/campus/computers/virtual_files.gd")
const ROOT:="Program Files"
const DATA_ROOT:="App Data"
const RECORD:="install.json"
const ARCHIVE:="Application.campusapp"
const OPERATIONS:=["install_app","uninstall_app","save_app_state"]
const MAX_APPS:=24
const MAX_STATE_BYTES:=4096

static func managed(path: String) -> bool:
	var lower:=path.to_lower()
	for root in [ROOT,DATA_ROOT]:
		if lower==root.to_lower() or lower.begins_with(root.to_lower()+"/"):return true
	return false

static func state_path(id: String) -> String:
	return DATA_ROOT+"/"+id.sha256_text()+".json"

static func valid_state(value: Variant) -> bool:
	return value is String and value.to_utf8_buffer().size()<=MAX_STATE_BYTES and JSON.parse_string(value) is Dictionary

static func installed(drive: RefCounted) -> Dictionary:
	var result:={}
	for path: String in drive.entries:
		if not path.begins_with(ROOT+"/") or not path.ends_with("/"+RECORD) or path.count("/")!=2:continue
		var record: Variant=_read_record(drive,path)
		if record==null or result.size()>=MAX_APPS:continue
		result[record.id]=record
	return result

static func _read_record(drive: RefCounted,path: String) -> Variant:
	var bytes: Variant=drive.entries[path].get("data")
	if not bytes is PackedByteArray or bytes.size()>2048:return null
	var value: Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not value is Dictionary:return null
	for field in ["id","name","publisher","version","sha256"]:
		if not value.get(field) is String or str(value[field]).is_empty() or str(value[field]).length()>80:return null
	if str(value.sha256).length()!=64 or not str(value.sha256).is_valid_hex_number():return null
	var archive:=path.get_base_dir()+"/"+ARCHIVE
	if drive.entries.get(archive,{}).get("type")!="file":return null
	var stored: Variant=drive.entries.get(state_path(str(value.id)),{}).get("data")
	var state: String=stored.get_string_from_utf8() if stored is PackedByteArray and stored.size()<=MAX_STATE_BYTES else "{}"
	return {"id":value.id,"name":value.name,"publisher":value.publisher,"version":value.version,
		"sha256":value.sha256,"archive":archive,"bytes":drive.entries[archive].data.size(),
		"shortcut":value.get("shortcut",true)==true,"desktop_shortcut":value.get("desktop_shortcut",false)==true,
		"state":state if valid_state(state) else "{}"}

static func apply(drive: RefCounted,action: Dictionary) -> String:
	var list:=installed(drive)
	var op:=str(action.get("op",""))
	if op=="save_app_state":
		var app: Dictionary=list.get(str(action.get("app_id","")),{})
		var state: Variant=action.get("state")
		if app.is_empty() or action.get("sha256","")!=app.sha256 or not valid_state(state):
			return "The application data is invalid or the installed version changed."
		var staging:=Drive.new(drive.capacity)
		staging.entries=drive.entries.duplicate()
		if not staging.entries.has(DATA_ROOT) and not staging.make_folder(DATA_ROOT):
			return "Could not create App Data."
		if not staging.write_file(state_path(str(app.id)),state.to_utf8_buffer()):
			return "There is insufficient space for the application data."
		drive.entries=staging.entries
		return ""
	if op=="uninstall_app":
		var old: Dictionary=list.get(str(action.get("app_id","")),{})
		if old.is_empty():return "The application is unavailable."
		if not drive.remove(str(old.archive).get_base_dir()):return "The application could not be removed."
		if action.get("keep_data",false)!=true and drive.entries.has(state_path(str(old.id))):
			drive.remove(state_path(str(old.id)))
		return ""
	if op!="install_app":return "Unknown installation action."
	var path:=str(action.get("path",""))
	if not Drive.valid_path(path) or managed(path) or path.get_extension().to_lower() not in ["campusapp","zip"]:
		return "Choose a Campus OS application package."
	var file: Dictionary=drive.entries.get(path,{})
	if file.get("type")!="file":return "The selected package is unavailable."
	var package:=Packages.inspect(file.data)
	if package.has("error"):return str(package.error)
	var digest:=sha256(file.data)
	if digest!=action.get("sha256",""):return "The package changed. Reopen it to review the new contents."
	var manifest: Dictionary=package.manifest
	var previous: Dictionary=list.get(manifest.id,{})
	if previous.is_empty() and list.size()>=MAX_APPS:return "The application limit is reached."
	if not previous.is_empty():
		if action.get("replace",false)!=true:return "Confirm an update or repair before replacing an app."
		if previous.publisher!=manifest.publisher or _older(str(manifest.version),str(previous.version)):
			return "This package does not match the installed publisher and version."
	var folder:=str(action.get("folder","")).strip_edges()
	if folder.is_empty():folder=str(manifest.id).left(20)+"-"+str(manifest.id).sha256_text().left(8)
	if folder.length()>30 or Files.path(folder)!=folder or folder.contains("/") or folder.begins_with("."):
		return "Choose a folder name under Program Files."
	var target:=ROOT+"/"+folder if previous.is_empty() else str(previous.archive).get_base_dir()
	if previous.is_empty() and drive.entries.keys().any(func(item):return str(item).to_lower()==target.to_lower()):
		return "That installation folder already exists."
	var staging:=Drive.new(drive.capacity)
	staging.entries=drive.entries.duplicate()
	if not staging.entries.has(ROOT) and not staging.make_folder(ROOT):return "Could not create Program Files."
	if not staging.entries.has(target) and not staging.make_folder(target):return "Could not create the installation folder."
	var record:={"id":manifest.id,"name":manifest.name,"publisher":manifest.publisher,"version":manifest.version,
		"sha256":digest,"shortcut":action.get("shortcut",true)==true,"desktop_shortcut":action.get("desktop_shortcut",false)==true}
	if not staging.write_file(target+"/"+ARCHIVE,file.data) or not staging.write_file(target+"/"+RECORD,JSON.stringify(record).to_utf8_buffer()):
		return "There is insufficient space to install this package."
	drive.entries=staging.entries
	return ""

static func _older(candidate: String,current: String) -> bool:
	for index in 3:
		var a:=int(candidate.get_slice(".",index))
		var b:=int(current.get_slice(".",index))
		if a!=b:return a<b
	return false

static func sha256(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
