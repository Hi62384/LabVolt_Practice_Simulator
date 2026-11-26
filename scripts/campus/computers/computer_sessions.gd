extends Node
signal desktop_changed(snapshot: Dictionary)
signal occupancy_changed(occupancy: Dictionary)
signal power_changed(power: Dictionary)
signal connected_usb_changed(ports: Dictionary)
var connected_usb_ports: Dictionary = {}
signal owned_usb_preferences_changed
var owned_usb_mounts: Dictionary = {}
var owned_usb_preferences: Dictionary = {}
signal boot_changed(boot: Dictionary)
signal operation_failed(message: String)
signal file_opened(path: String, bytes: PackedByteArray)
signal usb_write_prepared(station: String, token: String)
signal usb_write_committed(station: String, token: String)
const Files = preload("res://scripts/campus/computers/virtual_files.gd")
const Documents = preload("res://scripts/campus/computers/local_documents.gd")
const UsbArchive = preload("res://scripts/campus/computers/usb_archive.gd")
const Preferences = preload("res://scripts/campus/computers/desktop_preferences.gd")
const EquipmentConfig = preload("res://scripts/campus/items/equipment_configuration.gd")
const Apps = preload("res://scripts/campus/computers/application_registry.gd")
const UsbTransfer = preload("res://scripts/campus/computers/usb_transfer.gd")
const UsbDrive = preload("res://scripts/campus/computers/device_filesystem.gd")
const Downloads = preload("res://scripts/campus/computers/browser_download.gd")
const FileOperations = preload("res://scripts/campus/computers/virtual_file_operations.gd")
const MAX_DOWNLOAD_NAMES := Files.MAX_FILES+1
# Restore packets can include the full local document quota; ordinary actions
# are much smaller. Bound total RPC payloads, not merely dictionary key count.
const MAX_REQUEST_BYTES := Files.MAX_TOTAL_BYTES + 32768
var game: Node
var stations := {}
var sessions := {}
var workspaces := {}
var workspace_identities := {}
var restored := {}
var public_workspaces := {}
var station_users := {}
var power_cycle := 0
var last_request := {}
var serial := 0
var local_snapshot := {}
var local_profile := ""
var local_restore_failure := ""
var timer: Timer
var usb_uploads := {}
var usb_writes := {}
var download_uploads := {}
var owner_copy_transfers := {}
var file_read := {}
static func bounded_request(action: Dictionary) -> bool:
	var entry: Variant=action.get("entry")
	var install_entry: bool=action.get("op")=="install_app" and entry is String and entry.length()<=180
	return action.size()<=9+int(install_entry) and var_to_bytes(action).size()<=MAX_REQUEST_BYTES and not action.has("owner") and not action.has("profile") and not action.has("identity")

func supports_operation(op: String) -> bool:
	return op in ["rename","copy","zip","extract","open_text","read_file"]
func build(owner_game: Node) -> void:
	game=owner_game
	game.session.roster_changed.connect(_prune)
	game.session.roster_changed.connect(_roster_power)
	game.session.leaving.connect(_reset)
	timer=Timer.new()
	timer.wait_time=.25
	timer.timeout.connect(_prune)
	add_child(timer)
	timer.start()
func register_station(id: String, chair_index: int, anchor: Vector3, public_device: bool = false, physical_power := false) -> bool:
	if id.length()>48 or Files.path(id)!=id or id.contains("/") or stations.has(id) or not anchor.is_finite():return false
	if chair_index<0 or chair_index>=game.chairs.size():return false
	for entry in stations.values():
		if entry.chair==chair_index:return false
	stations[id]={"chair":chair_index,"anchor":anchor,"public_device":public_device}
	if public_device or physical_power:
		stations[id].power=preload("res://scripts/campus/computers/device_power.gd").new()
	return true
func register_portable(id: String,anchor: Vector3,owner: String,tier: String,configuration: Dictionary={}) -> bool:
	var tiers=preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS
	if id.length()>48 or Files.path(id)!=id or id.contains("/") or stations.has(id) or not anchor.is_finite() or not tiers.has(tier) or not preload("res://scripts/campus/dorms/authority/persistent_dorm.gd").identity_ok(owner):return false
	if not configuration.is_empty() and (tier!="basic" or EquipmentConfig.quote(EquipmentConfig.LAPTOP,0,configuration).is_empty()):return false
	stations[id]={"chair":-1,"anchor":anchor,"private_owner":owner,"portable":true,"tier":tier,"configuration":configuration,"power":preload("res://scripts/campus/computers/device_power.gd").new()}
	return true

func unregister_portable(id: String) -> bool:
	if not stations.has(id) or not stations[id].get("portable",false) or not stations[id].power.usb.is_empty() or usb_writes.has(id) or usb_uploads.values().any(func(upload):return upload.station==id):return false
	if stations[id].power.powered:_power_off(id)
	stations.erase(id);public_workspaces.erase(id);station_users.erase(id);return true

func _has_access(peer: int,entry: Dictionary) -> bool:
	if not entry.get("portable",false):
		var seated_peer: int=game.chairs[entry.chair].occupant
		if seated_peer==peer:return true
		if seated_peer!=0 and game.session.roster.has(seated_peer):return false
	return _workstation_distance(peer,entry.anchor)<=3
func _workstation_distance(peer: int, anchor: Vector3) -> float:
	var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	return position.distance_to(anchor)
func set_private_owner(id: String,owner: String) -> bool:
	if not stations.has(id):return false
	if stations[id].get("private_owner",null)==owner:return true
	stations[id].private_owner=owner
	if multiplayer.is_server():
		for peer in sessions.keys():
			if sessions[peer].station==id and not _private_allowed(peer,stations[id]):_close(peer,true)
	return true
func _identity(peer: int) -> String:
	if not game.session.roster.has(peer):return ""
	return str(game.electronics_trade.authority.ledger.bindings.get(peer,"")) if game.session.online else (game.school.local_identity if peer==1 else "")
func _private_allowed(peer: int,entry: Dictionary) -> bool:
	return not entry.has("private_owner") or (not str(entry.private_owner).is_empty() and _identity(peer)==entry.private_owner)
func request(action: Dictionary) -> void:
	if action.get("op") in ["read_file","read_project"]:
		file_read={"path":str(action.get("path","")),"lease":action.get("lease"),"bytes":PackedByteArray()}
	if action.get("op","")=="usb_port" and game.session.online:
		action=action.duplicate()
		var slot: int=game.hotbar.active
		if slot in range(game.hotbar.slots.size()) and game.hotbar.slots[slot].get("kind","")=="usb":action.id=str(game.hotbar.slots[slot].id)
	if action.get("op","")=="enter":
		var identity: String=game.school.local_identity
		if identity.is_empty():operation_failed.emit("Select a student profile first.");return
		if local_profile!=identity:local_restore_failure=""
		local_profile=identity
	if multiplayer.is_server():_accept(multiplayer.get_unique_id(),action)
	elif game.session.online:
		if action.get("op")=="download" and action.get("bytes") is PackedByteArray and action.bytes.size()>UsbTransfer.CHUNK_SIZE:
			_send_download(action)
		else:_request.rpc_id(1,action)

func _send_download(action: Dictionary) -> void:
	var bytes: PackedByteArray=action.bytes
	var header: Dictionary=action.duplicate()
	header.erase("bytes")
	header.op="download_begin"
	header.size=bytes.size()
	header.digest=_download_digest(bytes)
	if rpc_id(1,"_request",header)!=OK:
		operation_failed.emit("Could not start saving this download.");return
	for offset in range(0,bytes.size(),UsbTransfer.CHUNK_SIZE):
		await get_tree().process_frame
		if not game.session.online or local_snapshot.get("lease")!=action.lease or local_snapshot.get("revision")!=action.revision:return
		var chunk := bytes.slice(offset,offset+UsbTransfer.CHUNK_SIZE)
		if rpc_id(1,"_request",{"op":"download_chunk","lease":action.lease,"revision":action.revision,"offset":offset,"bytes":chunk})!=OK:
			operation_failed.emit("Could not send this download.");return

func _download_digest(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func _receive_download(peer: int,action: Dictionary) -> Dictionary:
	if action.op=="download_begin":
		if download_uploads.has(peer) or not action.get("size") is int or not action.get("digest") is String or not action.get("name") is String or action.name.length()>25 or action.size<=UsbTransfer.CHUNK_SIZE or action.size>Downloads.MAX_BYTES:
			_error(peer,"Invalid download transfer.");return {}
		var receiver:=UsbTransfer.new()
		if not receiver.begin(action.size,action.digest,Time.get_ticks_msec()):
			_error(peer,"Invalid download transfer.");return {}
		download_uploads[peer]={"lease":action.lease,"revision":action.revision,"name":action.name,"receiver":receiver}
		return {}
	var upload: Dictionary=download_uploads.get(peer,{})
	if upload.is_empty() or upload.lease!=action.lease or upload.revision!=action.revision:return {}
	var receiver: RefCounted=upload.receiver
	var now:=Time.get_ticks_msec()
	if not action.get("offset") is int or not action.get("bytes") is PackedByteArray or not receiver.append(action.offset,action.bytes,now):
		download_uploads.erase(peer)
		_error(peer,"Invalid download transfer.");return {}
	if receiver.received<receiver.expected_size:return {}
	download_uploads.erase(peer)
	var completed: Dictionary=receiver.finish(now)
	if completed.has("error"):
		_error(peer,"Could not verify the download.");return {}
	return {"op":"download","name":upload.name,"bytes":completed.bytes}
@rpc("any_peer","call_remote","reliable",6)
func _request(action: Dictionary) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),action)
func _accept(peer: int, action: Dictionary) -> void:
	var local_download: bool=peer==multiplayer.get_unique_id() and action.get("op")=="download" and action.get("bytes") is PackedByteArray and action.bytes.size()<=Downloads.MAX_BYTES
	if not game.session.roster.has(peer) or (not local_download and not bounded_request(action)):return
	var op: String=str(action.get("op",""))
	if op=="usb_port":
		if game.session.online:_network_usb_port(peer,str(action.get("station","")),str(action.get("id","")));return
		_local_usb_port(peer,str(action.get("station","")))
		return
	if op=="power":
		var id:=str(action.get("station",""))
		if not stations.has(id) or not stations[id].has("power") or not _private_allowed(peer,stations[id]):return
		if _workstation_distance(peer,stations[id].anchor)>3:
			_error(peer,"Move closer to the power button.")
			return
		var device=stations[id].power
		if usb_writes.has(id):_error(peer,"Wait for the USB save to finish.");return
		if device.powered:_power_off(id)
		else:
			if stations[id].get("portable",false) and is_instance_valid(game.device_charging) and not game.device_charging.can_power_laptop(peer,id,str(stations[id].tier)):
				_error(peer,"Laptop battery is empty. Connect it to a charger in M110.");return
			device.turn_on(Time.get_ticks_msec())
			power_cycle+=1
			stations[id].cycle=power_cycle
			var boot_delay:=1600
			if stations[id].get("portable",false):
				boot_delay=int(EquipmentConfig.value(EquipmentConfig.LAPTOP,stations[id].configuration,"hardware","processor",900))
			stations[id].ready_at=Time.get_ticks_msec()+boot_delay
			_publish()
		return
	if op=="enter":
		if sessions.has(peer):
			var previous: Dictionary=sessions[peer]
			if str(previous.get("identity",""))==_identity(peer) and _private_allowed(peer,stations[previous.station]):_reply(peer);return
			_close(peer,true)
		var id: String=str(action.get("station",""))
		if not stations.has(id):return
		var entry: Dictionary=stations[id]
		if not _private_allowed(peer,entry):return
		if entry.has("power") and not entry.power.powered:_error(peer,"Turn on this computer first.");return
		if Time.get_ticks_msec()<int(entry.get("ready_at",0)):_error(peer,"Campus OS is starting.");return
		if entry.has("power") and not entry.power.usb.is_empty() and str(entry.power.usb.get("owner",""))!=_identity(peer):
			_error(peer,"This workstation has another player's USB drive connected.");return
		if not _has_access(peer,entry):return
		for current: Dictionary in sessions.values():
			if current.station==id:
				_error(peer,"This computer is in use.");return
		serial+=1
		var identity := _identity(peer)
		if workspace_identities.get(peer,"__unbound__")!=identity:
			workspaces.erase(peer);restored.erase(peer)
		workspace_identities[peer]=identity
		sessions[peer]={"station":id,"lease":serial,"revision":0,"identity":identity}
		if entry.get("portable",false):
			sessions[peer].tier=entry.tier
			sessions[peer].display_scale=EquipmentConfig.value(EquipmentConfig.LAPTOP,entry.configuration,"hardware","display",1.0)
			sessions[peer].display_fps=EquipmentConfig.phone_or_laptop_fps(EquipmentConfig.LAPTOP,entry.configuration)
			if entry.configuration.get("version")==EquipmentConfig.DEVICE_VERSION:
				sessions[peer].performance=EquipmentConfig.value(EquipmentConfig.LAPTOP,entry.configuration,"hardware","performance",4)
			sessions[peer].audio_quality=EquipmentConfig.value(EquipmentConfig.LAPTOP,entry.configuration,"hardware","audio_quality",3)
			sessions[peer].display_noise=EquipmentConfig.screen_noise(EquipmentConfig.LAPTOP,entry.configuration)
		if entry.has("power"):
			entry.power.touch(Time.get_ticks_msec())
			sessions[peer].power_cycle=int(entry.get("cycle",0))
		if entry.get("public_device",false) or entry.get("portable",false):
			var profiles: Dictionary=station_users.get_or_add(id,{})
			var owner_key := identity if not identity.is_empty() else "connection:%d"%peer
			if not profiles.has(owner_key):
				if profiles.size()>=16:profiles.erase(profiles.keys()[0])
				var local_drive=preload("res://scripts/campus/computers/device_filesystem.gd").new()
				local_drive.make_folder("Downloads")
				profiles[owner_key]={"workspace":{"files":{},"editor":{}},"drive":local_drive}
				if not entry.power.usb.is_empty():
					for path in entry.power.usb.drive.entries:
						var file: Dictionary=entry.power.usb.drive.entries[path]
						if file.type=="file" and Files.path(path)==path and Downloads.is_text(path.get_extension()):
							var bytes: PackedByteArray=file.data
							if bytes.size()<=Files.MAX_FILE_BYTES and Downloads.valid(bytes,path.get_extension()):
								profiles[owner_key].workspace.files[path]={"text":bytes.get_string_from_utf8(),"version":1}
			public_workspaces[id]=profiles[owner_key].workspace
			entry.power.drive=profiles[owner_key].drive if entry.power.usb.is_empty() else entry.power.usb.drive
			workspaces[peer]=public_workspaces[id]
			restored[peer]=true
			sessions[peer].public_device=true
		elif not workspaces.has(peer):workspaces[peer]={"files":{},"editor":{}}
		_publish()
		_reply(peer)
		return
	if not sessions.has(peer):return
	var session: Dictionary=sessions[peer]
	if str(session.get("identity",""))!=_identity(peer) or not _private_allowed(peer,stations[session.station]):_close(peer,true);return
	if op=="activity":
		if action.get("lease",-1)==session.lease and stations[session.station].has("power") and _has_access(peer,stations[session.station]):
			stations[session.station].power.touch(Time.get_ticks_msec())
		return
	if action.get("lease",-1)!=session.lease:return
	if op=="exit":_close(peer,false);return
	if action.get("revision",-1)!=session.revision:return
	var entry: Dictionary=stations[session.station]
	if usb_writes.has(session.station):_error(peer,"Wait for the USB save to finish.");return
	if not _has_access(peer,entry):_close(peer,false);return
	if entry.has("power"):entry.power.touch(Time.get_ticks_msec())
	if op in ["browser","run"]:_error(peer,"Unavailable: browser and code execution are not installed.");return
	if op in ["download_begin","download_chunk"]:
		if not session.get("public_device",false):return
		action=_receive_download(peer,action)
		if action.is_empty():return
		op="download"
	var now := Time.get_ticks_msec()
	if now-int(last_request.get(peer,-1000))<60:_error(peer,"Please retry after the current operation.");return
	last_request[peer]=now
	var workspace: Dictionary=workspaces[peer]
	var file_device := bool(session.get("public_device", false))
	var writes_usb: bool=file_device and not entry.power.usb.is_empty() and (op in ["save","mkdir","delete","rename","download","copy_download","copy","zip","extract","save_preferences"] or op in Apps.OPERATIONS)
	var download_path: String=""
	var usb_before: Dictionary=entry.power.usb.drive.entries.duplicate(true) if writes_usb else {}
	var workspace_before: Dictionary=workspace.duplicate(true) if writes_usb else {}
	for key in ["path","new_path"]:
		var path:=str(action.get(key,"")).to_lower()
		if path.begins_with(".recycle") or path==Preferences.PATH:
			_error(peer,"That path is reserved.");return
		var native_bundle: bool=not game.session.online and path.ends_with("/"+Apps.NATIVE_BUNDLE.to_lower())
		if Apps.managed(path) and (op!="read_file" or not path.begins_with("program files/") or not (path.ends_with("/application.campusapp") or path.ends_with("/application.exe") or native_bundle)):
			_error(peer,"Use Installed Apps to manage Program Files.");return
	match op:
		"install_app","uninstall_app","save_app_state":
			if not file_device:_error(peer,"Installation requires a virtual drive.");return
			if op=="install_app" and game.session.online and str(action.get("path","")).get_extension().to_lower() in Apps.WINDOWS_FORMATS:
				_error(peer,"Windows package installation requires a local session.");return
			var app_error:=Apps.apply(entry.power.drive,action)
			if not app_error.is_empty():_error(peer,app_error);return
		"save_preferences":
			var settings:=Preferences.clean(action.get("settings"))
			if not writes_usb or settings.is_empty() or not entry.power.usb.drive.write_file(Preferences.PATH,JSON.stringify(settings).to_utf8_buffer()):
				_error(peer,"Could not save Campus OS settings to this USB drive.");return
			action={"op":op,"settings":settings}
		"restore":
			if restored.has(peer):_error(peer,"This connection has already restored its files.");return
			var files = action.get("files",{})
			if not files is Dictionary or not Files.validate(files):_error(peer,"Invalid saved documents.");return
			workspace.files=files.duplicate(true)
			var editor = action.get("editor",{})
			if editor is Dictionary and workspace.files.has(str(editor.get("path",""))):
				workspace.editor={"path":str(editor.path),"cursor":clampi(int(editor.get("cursor",0)),0,str(workspace.files[editor.path].text).length())}
			restored[peer]=true
		"save":
			if not restored.has(peer):_error(peer,"Restore documents before editing.");return
			if not action.get("text") is String or not action.get("version") is int:return
			var result := Files.save(workspace.files,str(action.get("path","")),action.text,action.version)
			if result.has("error"):_error(peer,result.error);return
			if file_device and not entry.power.drive.write_file(str(action.path),action.text.to_utf8_buffer()):
				_error(peer,"Choose an existing folder and check available space.");return
			workspace.files=result.files
		"download":
			if not file_device:
				_error(peer,"Use the workstation drive to download a temporary file.");return
			var filename: Variant=action.get("name")
			var bytes: Variant=action.get("bytes")
			if not filename is String or not bytes is PackedByteArray or filename.length()>25 or Files.path(filename)!=filename or filename.contains("/") or filename.begins_with(".") or not Downloads.valid(bytes,filename.get_extension()):
				_error(peer,"Invalid download.");return
			if writes_usb:
				var write_seconds:=_usb_seconds(entry.power.usb,"write",bytes.size())
				if write_seconds>=.02:
					var lease: int=session.lease
					var revision: int=session.revision
					await get_tree().create_timer(write_seconds).timeout
					var current: Dictionary=sessions.get(peer,{})
					if current.get("lease")!=lease:return
					if current.get("revision")!=revision or usb_writes.has(session.station):
						_error(peer,"The drive changed during the download. Try the download again.")
						return
			var drive: Variant=entry.power.drive
			if drive==null:
				_error(peer,"This workstation drive is unavailable.");return
			var path: String="Downloads/"+filename
			for index in range(2,MAX_DOWNLOAD_NAMES+2):
				if not drive.entries.has(path) and not workspace.files.has(path):break
				path="Downloads/%s_%d.%s"%[filename.get_basename(),index,filename.get_extension()]
			if drive.entries.has(path) or workspace.files.has(path):
				_error(peer,"No free filename in Downloads.");return
			var files: Dictionary=workspace.files
			if Downloads.is_text(filename.get_extension()) and bytes.size()<=Files.MAX_FILE_BYTES:
				var result := Files.save(files,path,bytes.get_string_from_utf8(),0)
				if result.has("files"):files=result.files
			if not drive.entries.has("Downloads") and not drive.make_folder("Downloads"):
				_error(peer,"Could not create Downloads.");return
			if not drive.write_file(path,bytes):
				if writes_usb:drive.entries=usb_before
				_error(peer,"Could not save to Downloads. Check the available space.");return
			workspace.files=files
			download_path=path
			if writes_usb:action={"op":"copy_download","path":path,"bytes":bytes}
		"copy_download":
			if not writes_usb:
				_error(peer,"Attach a USB drive to copy a download.");return
			var path:=Files.path(str(action.get("path","")))
			var local: Variant=_workstation_drive(session.station,peer)
			if local==null or not path.begins_with("Downloads/") or path.count("/")!=1 or local.entries.get(path,{}).get("type")!="file":
				_error(peer,"Choose a file from the workstation Downloads folder.");return
			var bytes: PackedByteArray=local.entries[path].data
			var usb: RefCounted=entry.power.usb.drive
			if not Downloads.valid(bytes,path.get_extension()) or usb.entries.has(path) or workspace.files.has(path):
				_error(peer,"Cannot copy that file. Use an unused filename.");return
			var files: Dictionary=workspace.files
			if Downloads.is_text(path.get_extension()) and bytes.size()<=Files.MAX_FILE_BYTES:
				var result := Files.save(files,path,bytes.get_string_from_utf8(),0)
				if result.has("files"):files=result.files
			if (not usb.entries.has("Downloads") and not usb.make_folder("Downloads")) or not usb.write_file(path,bytes):
				usb.entries=usb_before
				_error(peer,"Cannot copy that file. Check USB space.");return
			workspace.files=files
			action={"op":"copy_download","path":path,"bytes":bytes}
		"mkdir":
			var path:=Files.path(str(action.get("path","")))
			if not file_device or path.is_empty() or not entry.power.drive.make_folder(path):
				_error(peer,"Choose a valid new folder inside an existing folder.");return
		"delete":
			var path:=Files.path(str(action.get("path","")))
			if not file_device or path.is_empty() or not entry.power.drive.remove(path):
				_error(peer,"Choose an existing file or folder.");return
			for name in workspace.files.keys():
				if name==path or str(name).begins_with(path+"/"):workspace.files.erase(name)
			if str(workspace.editor.get("path", ""))==path or str(workspace.editor.get("path", "")).begins_with(path+"/"):workspace.editor={}
		"rename":
			var source := Files.path(str(action.get("path","")))
			var target := Files.path(str(action.get("new_path","")))
			if file_device and entry.power.drive.entries.has(source):
				for name in workspace.files:
					if name==source or str(name).begins_with(source+"/"):
						var next_path: String=target+str(name).substr(source.length())
						if Files.path(next_path)!=next_path or int(workspace.files[name].version)>=2147483646:
							_error(peer,"Destination would exceed file limits.");return
				if target.is_empty() or not entry.power.drive.move(source,target):_error(peer,"Choose a valid unused destination.");return
				var moved:={}
				for name in workspace.files.keys():
					if name==source or str(name).begins_with(source+"/"):
						var renamed: String=target+str(name).substr(source.length())
						moved[renamed]=workspace.files[name].duplicate(true)
						moved[renamed].version+=1
						workspace.files.erase(name)
				workspace.files.merge(moved)
				var editor_path:=str(workspace.editor.get("path",""))
				if editor_path==source or editor_path.begins_with(source+"/"):workspace.editor.path=target+editor_path.substr(source.length())
			elif source.is_empty() or target.is_empty() or not workspace.files.has(source) or workspace.files.has(target) or int(workspace.files.get(source,{}).get("version",0))>=2147483646:
				_error(peer,"Choose an existing source and an unused valid destination.")
				return
			else:
				workspace.files[target]=workspace.files[source].duplicate(true)
				workspace.files[target].version+=1
				workspace.files.erase(source)
				if workspace.editor.get("path","")==source:workspace.editor.path=target
		"copy","zip","extract":
			var source:=str(action.get("path",""))
			var target:=str(action.get("new_path",""))
			if not file_device:
				if op!="copy" or not FileOperations.valid(source) or not FileOperations.valid(target) or not workspace.files.has(source) or workspace.files.has(target):
					_error(peer,"Choose an unused destination for this document.");return
				var result:=Files.save(workspace.files,target,workspace.files[source].text,0)
				if result.has("error"):_error(peer,result.error);return
				workspace.files=result.files
			else:
				var error:=FileOperations.apply(entry.power.drive,op,source,target)
				if not error.is_empty():_error(peer,error);return
		"read_project":
			var project_path:=str(action.get("path",""))
			if not file_device or not FileOperations.valid(project_path) or not (entry.power.drive.entries.has(project_path) or workspace.files.has(project_path)):
				_error(peer,"The project entry is unavailable.");return
			var assets:={}
			var folder:=project_path.get_base_dir()
			var prefix:=folder+"/" if not folder.is_empty() else ""
			var bytes_total:=0
			for file_path: String in entry.power.drive.entries:
				if not file_path.begins_with(prefix) or Apps.managed(file_path) or file_path.to_lower().begins_with(".recycle"):continue
				var relative:=file_path.trim_prefix(prefix)
				if prefix.is_empty() and relative.contains("/"):continue
				var asset: Dictionary=entry.power.drive.entries[file_path]
				if asset.get("type")!="file" or relative.get_extension().to_lower() not in Apps.Packages.CONTENT:continue
				bytes_total+=asset.data.size()
				if assets.size()>=128 or bytes_total>Apps.Packages.MAX_EXPANDED:
					_error(peer,"Web preview supports up to 128 assets and 16 MiB of project files.");return
				assets[relative]=asset.data
			var archive: PackedByteArray=Apps.Packages.Zip.new().Pack(assets)
			if archive.is_empty():_error(peer,"The project archive exceeds the 8 MiB preview transfer limit.");return
			_deliver_file(peer,session.lease,project_path,archive)
			return
		"read_file","open_text":
			var path:=str(action.get("path",""))
			var file: Dictionary=entry.power.drive.entries.get(path,{}) if file_device and FileOperations.valid(path) else {}
			if file.get("type","")!="file":_error(peer,"The file is unavailable.");return
			var bytes: PackedByteArray=file.data
			if op=="read_file":
				var native_bundle: bool=not game.session.online and Apps.managed(path) and path.ends_with("/"+Apps.NATIVE_BUNDLE)
				if bytes.size()>(Apps.MAX_NATIVE_BUNDLE if native_bundle else Downloads.MAX_BYTES):
					_error(peer,"The file exceeds the supported size for this operation.");return
				_deliver_file(peer,session.lease,path,bytes)
				return
			if bytes.size()>Files.MAX_FILE_BYTES or not Downloads.valid(bytes,path.get_extension()) or not Downloads.is_text(path.get_extension()):
				_error(peer,"This file cannot be edited here. The editor supports UTF-8 documents up to 32 KiB.");return
			if not workspace.files.has(path):
				var result:=Files.save(workspace.files,path,bytes.get_string_from_utf8(),0)
				if result.has("error"):_error(peer,result.error);return
				workspace.files=result.files
		"editor":
			var path := Files.path(str(action.get("path","")))
			if not workspace.files.has(path):return
			workspace.editor={"path":path,"cursor":clampi(int(action.get("cursor",0)),0,str(workspace.files[path].text).length())}
		"trash","untrash","purge":
			if not file_device or not entry.power.usb.is_empty():
				_error(peer,"Recycle Bin is available on the workstation drive.");return
			var recycle_error := _recycle_operation(workspace,entry.power.drive,action)
			if not recycle_error.is_empty():_error(peer,recycle_error);return
		"refresh":
			pass
		"answer", "submit":
			if not _assignment(peer,action):return
		_:
			return
	if not workspace_before.is_empty() and entry.power.usb.get("remote",false):
		_begin_usb_write(peer,session.station,action,usb_before,workspace_before,download_path)
		return
	if not workspace_before.is_empty() and entry.power.save_local_usb()!=OK:
		entry.power.usb.drive.entries=usb_before
		workspace.clear();workspace.merge(workspace_before,true)
		_error(peer,"USB save failed; the change was not applied.")
		return
	if not download_path.is_empty():session.download_path=download_path
	session.revision+=1
	_reply(peer)

func _deliver_file(peer: int, lease: int, path: String, bytes: PackedByteArray) -> void:
	var entry: Dictionary=stations.get(sessions.get(peer,{}).get("station",""),{})
	if entry.has("power"):
		var read_seconds:=_usb_seconds(entry.power.usb,"read",bytes.size())
		if read_seconds>=.02:
			await get_tree().create_timer(read_seconds).timeout
			if sessions.get(peer,{}).get("lease")!=lease:return
	if peer==multiplayer.get_unique_id():
		file_read.clear()
		file_opened.emit(path,bytes)
		return
	for offset in range(0,maxi(1,bytes.size()),UsbTransfer.CHUNK_SIZE):
		_receive_file_chunk.rpc_id(peer,lease,path,bytes.size(),offset,bytes.slice(offset,offset+UsbTransfer.CHUNK_SIZE))

static func _usb_seconds(usb: Dictionary,direction: String,byte_count: int) -> float:
	var rate:=int(EquipmentConfig.value(EquipmentConfig.USB,usb.get("configuration",{}),"hardware",direction,0))
	return float(byte_count)/(float(rate)*1048576.0) if rate>0 else 0.0

@rpc("authority","call_remote","reliable",6)
func _receive_file_chunk(lease: int, path: String, total: int, offset: int, bytes: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id()!=1 or local_snapshot.get("lease")!=lease or file_read.get("lease")!=lease or file_read.get("path")!=path:return
	var received: PackedByteArray=file_read.bytes
	if total<0 or total>Downloads.MAX_BYTES or bytes.size()>UsbTransfer.CHUNK_SIZE or offset!=received.size() or offset+bytes.size()>total:return
	received.append_array(bytes)
	if received.size()==total:
		file_read.clear()
		file_opened.emit(path,received)
	else:file_read.bytes=received

func _recycle_operation(workspace: Dictionary, drive: RefCounted, action: Dictionary) -> String:
	var records: Dictionary=workspace.get_or_add("recycle",{})
	var id:=str(action.get("item",""))
	if action.op=="purge":
		var keys: Array=records.keys() if id.is_empty() else [id]
		for key in keys:
			if not records.has(key):continue
			var stored: String=records[key].stored
			if not drive.remove(stored):return "Could not erase the recycled item."
			for path in workspace.files.keys():
				if path==stored or str(path).begins_with(stored+"/"):workspace.files.erase(path)
			records.erase(key)
		return ""
	var origin := Files.path(str(action.get("path","")))
	var target := ""
	if action.op=="trash":
		if records.size()>=24:return "Recycle Bin is full. Empty it before deleting more items."
		if origin.is_empty() or not drive.entries.has(origin):return "Select an existing workspace item."
		id=Crypto.new().generate_random_bytes(8).hex_encode()
		target=".Recycle/"+id
		if not drive.entries.has(".Recycle") and not drive.make_folder(".Recycle"):
			return "The virtual drive could not create its Recycle Bin."
	else:
		if not records.has(id):return "That recycled item no longer exists."
		target=records[id].original
		origin=records[id].stored
	for path in workspace.files:
		if path!=origin and not str(path).begins_with(origin+"/"):continue
		var moved:=target+str(path).substr(origin.length())
		if Files.path(moved)!=moved or int(workspace.files[path].version)>=2147483646:
			return "The move would exceed the virtual file limits."
	if not drive.move(origin,target):return "Choose an unused destination in an existing folder."
	for path in workspace.files.keys():
		if path!=origin and not str(path).begins_with(origin+"/"):continue
		var moved:=target+str(path).substr(origin.length())
		workspace.files[moved]=workspace.files[path]
		workspace.files[moved].version+=1
		workspace.files.erase(path)
	var editor_path:=str(workspace.editor.get("path",""))
	if editor_path==origin or editor_path.begins_with(origin+"/"):workspace.editor={}
	if action.op=="trash":records[id]={"original":origin,"stored":target,"deleted":int(Time.get_unix_time_from_system())}
	else:records.erase(id)
	return ""

func _begin_usb_write(actor: int,station: String,action: Dictionary,old_entries: Dictionary,old_workspace: Dictionary,download_path := "") -> void:
	var usb: Dictionary=stations[station].power.usb
	var owner_peer:=0
	for peer in game.session.roster:
		if _identity(peer)==usb.owner:owner_peer=int(peer);break
	if owner_peer==0:
		stations[station].power.usb.drive.entries=old_entries
		var workspace: Dictionary=public_workspaces[station];workspace.clear();workspace.merge(old_workspace,true)
		_error(actor,"USB owner is no longer connected.");return
	var token:=Crypto.new().generate_random_bytes(16).hex_encode()
	var operation:={"op":str(action.op),"path":str(action.get("path",""))}
	if action.op=="save":operation.text=str(action.text)
	if action.op=="copy_download":operation.bytes=action.bytes
	if action.op=="save_preferences":operation.settings=action.settings
	if action.op=="install_app":
		operation.sha256=str(action.get("sha256",""))
		operation.folder=str(action.get("folder",""))
		operation.replace=action.get("replace",false)==true
		operation.shortcut=action.get("shortcut",true)==true
		operation.desktop_shortcut=action.get("desktop_shortcut",false)==true
	if action.op in ["uninstall_app","save_app_state"]:operation.app_id=str(action.get("app_id",""))
	if action.op=="uninstall_app":operation.keep_data=action.get("keep_data",false)==true
	if action.op=="save_app_state":
		operation.sha256=action.sha256
		operation.state=action.state
	if action.op in ["rename","copy","zip","extract"]:operation.new_path=str(action.get("new_path",""))
	usb_writes[station]={"token":token,"owner_peer":owner_peer,"actor":actor,"lease":sessions[actor].lease,"entries":old_entries,"workspace":old_workspace,"started":Time.get_ticks_msec()}
	if not download_path.is_empty():usb_writes[station].download_path=download_path
	if owner_peer==multiplayer.get_unique_id():_apply_owner_usb_write(station,token,str(usb.id),int(usb.capacity_mb),operation)
	elif action.op=="copy_download" and action.bytes.size()>UsbTransfer.CHUNK_SIZE:
		_send_owner_download(owner_peer,station,token,str(usb.id),int(usb.capacity_mb),operation)
	else:_usb_write_requested.rpc_id(owner_peer,station,token,str(usb.id),int(usb.capacity_mb),operation)

func _send_owner_download(peer: int,station: String,token: String,id: String,capacity: int,operation: Dictionary) -> void:
	var bytes: PackedByteArray=operation.bytes
	operation.erase("bytes")
	operation.size=bytes.size()
	operation.digest=_download_digest(bytes)
	if rpc_id(peer,"_usb_write_requested",station,token,id,capacity,operation)!=OK:
		_finish_usb_write(peer,station,token,false);return
	for offset in range(0,bytes.size(),UsbTransfer.CHUNK_SIZE):
		await get_tree().process_frame
		if usb_writes.get(station,{}).get("token")!=token:return
		if rpc_id(peer,"_usb_write_chunk",token,offset,bytes.slice(offset,offset+UsbTransfer.CHUNK_SIZE))!=OK:
			_finish_usb_write(peer,station,token,false);return

@rpc("authority","call_remote","reliable",6)
func _usb_write_requested(station: String,token: String,id: String,capacity: int,operation: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()!=1:return
	if operation.get("op")!="copy_download" or not operation.has("size"):
		_apply_owner_usb_write(station,token,id,capacity,operation)
		return
	var receiver:=UsbTransfer.new()
	if not owner_copy_transfers.is_empty() or not operation.size is int or operation.size>Downloads.MAX_BYTES or not operation.get("digest") is String or not receiver.begin(operation.size,operation.digest,Time.get_ticks_msec()):
		_usb_write_ack.rpc_id(1,station,token,false)
		return
	owner_copy_transfers[token]={"station":station,"id":id,"capacity":capacity,"operation":operation,"receiver":receiver}

@rpc("authority","call_remote","reliable",6)
func _usb_write_chunk(token: String,offset: int,bytes: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id()!=1 or not owner_copy_transfers.has(token):return
	var transfer: Dictionary=owner_copy_transfers[token]
	var receiver: RefCounted=transfer.receiver
	var now:=Time.get_ticks_msec()
	if not receiver.append(offset,bytes,now):
		owner_copy_transfers.erase(token)
		_usb_write_ack.rpc_id(1,transfer.station,token,false)
		return
	if receiver.received<receiver.expected_size:return
	owner_copy_transfers.erase(token)
	var completed: Dictionary=receiver.finish(now)
	if completed.has("error"):
		_usb_write_ack.rpc_id(1,transfer.station,token,false)
		return
	transfer.operation.bytes=completed.bytes
	_apply_owner_usb_write(transfer.station,token,transfer.id,transfer.capacity,transfer.operation)

func _apply_owner_usb_write(station: String,token: String,id: String,capacity: int,operation: Dictionary) -> void:
	var prior: Dictionary=game.electronics.profile.data.get("usb_write_pending",{}).get(token,{})
	if not prior.is_empty() or bool(game.electronics.profile.data.get("usb_write_completed",{}).get(token,false)):
		var repeated: bool=bool(game.electronics.profile.data.get("usb_write_completed",{}).get(token,false))
		if not prior.is_empty():
			repeated=prior.get("id","")==id and int(prior.get("capacity",0))==capacity and not UsbArchive.load(game.school.local_identity,token,capacity).has("error")
		if multiplayer.is_server():_finish_usb_write(multiplayer.get_unique_id(),station,token,repeated)
		else:_usb_write_ack.rpc_id(1,station,token,repeated)
		return
	var metadata: Dictionary=game.electronics.profile.data.get("dorm",{}).get("usb_drives",{}).get(id,{})
	var loaded: Dictionary=UsbArchive.load(game.school.local_identity,id,capacity)
	var ok: bool=metadata.get("location","")=="connected" and int(metadata.get("capacity_mb",0))==capacity and not loaded.has("error")
	if ok:
		var drive=loaded.drive
		var path:=str(operation.get("path",""))
		match str(operation.get("op","")):
			"install_app","uninstall_app","save_app_state":ok=Apps.apply(drive,operation).is_empty()
			"save_preferences":
				var settings:=Preferences.clean(operation.get("settings"))
				ok=not settings.is_empty() and drive.write_file(Preferences.PATH,JSON.stringify(settings).to_utf8_buffer())
			"save":ok=operation.get("text") is String and drive.write_file(path,str(operation.text).to_utf8_buffer())
			"mkdir":ok=drive.make_folder(path)
			"copy_download":
				var bytes: Variant=operation.get("bytes")
				ok=Files.path(path)==path and path.begins_with("Downloads/") and path.count("/")==1 and bytes is PackedByteArray and Downloads.valid(bytes,path.get_extension()) and not drive.entries.has(path) and (drive.entries.has("Downloads") or drive.make_folder("Downloads")) and drive.write_file(path,bytes)
			"delete":ok=drive.remove(path)
			"rename":ok=drive.move(path,str(operation.get("new_path","")))
			"copy","zip","extract":ok=FileOperations.apply(drive,str(operation.op),path,str(operation.get("new_path",""))).is_empty()
			_:ok=false
		if ok:
			var profile=game.electronics.profile
			var authority=game.electronics_trade.authority
			var host: String=authority.bound_host
			ok=not host.is_empty() and token!=id and not FileAccess.file_exists(UsbArchive.path(game.school.local_identity,token)) and not profile.data.get("usb_write_pending",{}).has(token) and profile.data.get("usb_write_pending",{}).size()<16
			if ok:ok=UsbArchive.save(game.school.local_identity,token,str(metadata.name),capacity,drive)==OK
			if ok:
				var before: Dictionary=profile.data.duplicate(true)
				if not profile.data.has("usb_write_pending"):profile.data.usb_write_pending={}
				profile.data.usb_write_pending[token]={"id":id,"capacity":capacity,"host":host}
				var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
				ok=profile.save()==OK;profile.authority_submit=callback
				if not ok:profile.data=before
				else:usb_write_prepared.emit(station,token)
	if not game.session.online:return
	if multiplayer.is_server():_finish_usb_write(multiplayer.get_unique_id(),station,token,ok)
	else:_usb_write_ack.rpc_id(1,station,token,ok)

@rpc("any_peer","call_remote","reliable",6)
func _usb_write_ack(station: String,token: String,ok: bool) -> void:
	if multiplayer.is_server():_finish_usb_write(multiplayer.get_remote_sender_id(),station,token,ok)

func _finish_usb_write(peer: int,station: String,token: String,ok: bool) -> void:
	var pending: Dictionary=usb_writes.get(station,{})
	if pending.is_empty() or pending.token!=token or int(pending.owner_peer)!=peer:return
	var actor: int=pending.actor
	if not ok:
		usb_writes.erase(station)
		stations[station].power.usb.drive.entries=pending.entries
		if public_workspaces.has(station):
			var workspace: Dictionary=public_workspaces[station];workspace.clear();workspace.merge(pending.workspace,true)
		_error(actor,"USB save failed; the change was not applied.")
		return
	var usb: Dictionary=stations[station].power.usb
	var ledger=game.electronics_trade.authority.ledger
	var next: Dictionary=ledger.state.duplicate(true)
	var account: Dictionary=next.get("accounts",{}).get(str(usb.owner),{})
	if account.is_empty():_error(actor,"USB owner is unavailable; the prepared write was not committed.");return
	if not account.has("usb_write_commits"):account.usb_write_commits={}
	var existing: Dictionary=account.usb_write_commits.get(token,{})
	var record:={"id":str(usb.id),"capacity":int(usb.capacity_mb)}
	if not existing.is_empty() and existing!=record:_error(actor,"USB write identity conflict.");return
	account.usb_write_commits[token]=record
	if not ledger.persist(next):_error(actor,"USB write could not be committed; reconnect to recover.");return
	usb_write_committed.emit(station,token)
	if not game.session.online:return
	if peer==multiplayer.get_unique_id():_apply_committed_usb_write(station,token)
	else:_usb_write_commit.rpc_id(peer,station,token)

@rpc("authority","call_remote","reliable",6)
func _usb_write_commit(station: String,token: String) -> void:
	if multiplayer.get_remote_sender_id()==1:_apply_committed_usb_write(station,token)

func _apply_committed_usb_write(station: String,token: String) -> void:
	var profile=game.electronics.profile
	var pending: Dictionary=profile.data.get("usb_write_pending",{}).get(token,{})
	var ok: bool=bool(profile.data.get("usb_write_completed",{}).get(token,false))
	var committed_drive: RefCounted
	if not pending.is_empty():
		var staged: Dictionary=UsbArchive.load(game.school.local_identity,token,int(pending.capacity))
		if not staged.has("error") and UsbArchive.save(game.school.local_identity,str(pending.id),str(staged.name),int(pending.capacity),staged.drive)==OK:
			var before: Dictionary=profile.data.duplicate(true)
			profile.data.usb_write_pending.erase(token)
			if not profile.data.has("usb_write_completed"):profile.data.usb_write_completed={}
			profile.data.usb_write_completed[token]=true
			var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
			ok=profile.save()==OK;profile.authority_submit=callback
			if not ok:profile.data=before
			else:committed_drive=staged.drive
	if multiplayer.is_server():_finish_usb_commit(multiplayer.get_unique_id(),station,token,ok)
	else:
		if committed_drive!=null and owned_usb_mounts.get(station,{}).get("id")==pending.id:
			if _cache_owned_usb_preferences(station,committed_drive):owned_usb_preferences_changed.emit()
		_usb_commit_ack.rpc_id(1,station,token,ok)

@rpc("any_peer","call_remote","reliable",6)
func _usb_commit_ack(station: String,token: String,ok: bool) -> void:
	if multiplayer.is_server():_finish_usb_commit(multiplayer.get_remote_sender_id(),station,token,ok)

func _finish_usb_commit(peer: int,station: String,token: String,ok: bool) -> void:
	var pending: Dictionary=usb_writes.get(station,{})
	if pending.is_empty() or pending.token!=token or int(pending.owner_peer)!=peer:return
	if not ok:_error(int(pending.actor),"USB write is committed but needs recovery; reconnect to the original host.");return
	usb_writes.erase(station)
	var actor: int=pending.actor
	if sessions.has(actor) and sessions[actor].lease==pending.lease:
		if pending.has("download_path"):sessions[actor].download_path=pending.download_path
		sessions[actor].revision+=1
		_reply(actor)

func _network_usb_port(peer: int,id: String,usb_id: String) -> void:
	if not stations.has(id) or not (stations[id].get("public_device",false) or stations[id].get("portable",false)) or not _private_allowed(peer,stations[id]):return
	if _workstation_distance(peer,stations[id].anchor)>3:
		_error(peer,"Move closer to the USB port.")
		return
	var device=stations[id].power
	var identity:=_identity(peer)
	var profile: Dictionary=game.dorm_interactions._profile(identity).duplicate(true)
	var dorm: Dictionary=profile.get("dorm",{})
	if device.powered:_error(peer,"Turn off the computer before changing its USB drive.");return
	if not device.usb.is_empty():
		if not device.usb.get("remote",false) or device.usb.owner!=identity:_error(peer,"Only the owner can remove this drive.");return
		var drive_id: String=device.usb.id
		var item: Dictionary=dorm.get("usb_drives",{}).get(drive_id,{})
		if item.get("location","")!="connected":return
		var carried: Array=dorm.get("carry_items",[]).duplicate()
		if carried.size()+dorm.get("carried_components",[]).size()>=6:_error(peer,"Free a hotbar slot first.");return
		carried.append("usb:"+drive_id);dorm.carry_items=carried;item.location="hotbar";dorm.revision+=1
		var saved: Dictionary=game.dorm_interactions._commit_world_inventory(peer,identity,profile)
		if not saved.ok:_error(peer,str(saved.error));return
		device.usb={};_publish_usb_ports();_error(peer,"USB drive removed.");return
	if usb_uploads.size()>=4 or usb_uploads.has(peer) or usb_uploads.values().any(func(record):return record.station==id):_error(peer,"A USB transfer is already in progress.");return
	var item: Dictionary=dorm.get("usb_drives",{}).get(usb_id,{})
	if game.personal_placement.is_placed(peer,"usb:"+usb_id):_error(peer,"Pick up the USB drive first.");return
	if item.get("location","")!="hotbar" or "usb:"+usb_id not in dorm.get("carry_items",[]):_error(peer,"Hold your USB drive to connect it.");return
	var token:=Crypto.new().generate_random_bytes(16).hex_encode()
	usb_uploads[peer]={"station":id,"id":usb_id,"identity":identity,"capacity":int(item.capacity_mb),"name":str(item.name),"token":token,"receiver":UsbTransfer.new(),"started":Time.get_ticks_msec()}
	if peer==multiplayer.get_unique_id():_send_usb_archive(token,usb_id,int(item.capacity_mb))
	else:_usb_upload_requested.rpc_id(peer,token,usb_id,int(item.capacity_mb))

@rpc("authority","call_remote","reliable",6)
func _usb_upload_requested(token: String,id: String,capacity: int) -> void:
	if multiplayer.get_remote_sender_id()==1:_send_usb_archive(token,id,capacity)

func _send_usb_archive(token: String,id: String,capacity: int) -> void:
	var loaded: Dictionary=UsbArchive.load(game.school.local_identity,id,capacity)
	if loaded.has("error"):
		if multiplayer.is_server():_usb_cancel(multiplayer.get_unique_id(),token)
		else:_usb_upload_cancel.rpc_id(1,token)
		operation_failed.emit(str(loaded.error));return
	var bytes:=var_to_bytes(loaded.drive.entries)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	var digest:=hash.finish().hex_encode()
	if multiplayer.is_server():_usb_begin(multiplayer.get_unique_id(),token,bytes.size(),digest)
	else:_usb_upload_begin.rpc_id(1,token,bytes.size(),digest)
	for offset in range(0,bytes.size(),UsbTransfer.CHUNK_SIZE):
		if not game.session.online:return
		var chunk:=bytes.slice(offset,mini(offset+UsbTransfer.CHUNK_SIZE,bytes.size()))
		if multiplayer.is_server():_usb_chunk(multiplayer.get_unique_id(),token,offset,chunk)
		else:_usb_upload_chunk.rpc_id(1,token,offset,chunk)
		await get_tree().process_frame
	if multiplayer.is_server():_usb_finish(multiplayer.get_unique_id(),token)
	else:_usb_upload_finish.rpc_id(1,token)

@rpc("any_peer","call_remote","reliable",6)
func _usb_upload_begin(token: String,size: int,digest: String) -> void:
	if multiplayer.is_server():_usb_begin(multiplayer.get_remote_sender_id(),token,size,digest)
func _usb_begin(peer: int,token: String,size: int,digest: String) -> void:
	var record: Dictionary=usb_uploads.get(peer,{})
	if record.is_empty() or record.token!=token:return
	if size>int(record.capacity)*1024*1024+UsbArchive.MAX_OVERHEAD or not record.receiver.begin(size,digest,Time.get_ticks_msec()):_usb_cancel(peer,token)

@rpc("any_peer","call_remote","reliable",6)
func _usb_upload_chunk(token: String,offset: int,chunk: PackedByteArray) -> void:
	if multiplayer.is_server():_usb_chunk(multiplayer.get_remote_sender_id(),token,offset,chunk)
func _usb_chunk(peer: int,token: String,offset: int,chunk: PackedByteArray) -> void:
	var record: Dictionary=usb_uploads.get(peer,{})
	if record.is_empty() or record.token!=token:return
	if not record.receiver.append(offset,chunk,Time.get_ticks_msec()):_usb_cancel(peer,token)

@rpc("any_peer","call_remote","reliable",6)
func _usb_upload_finish(token: String) -> void:
	if multiplayer.is_server():_usb_finish(multiplayer.get_remote_sender_id(),token)
func _usb_finish(peer: int,token: String) -> void:
	var record: Dictionary=usb_uploads.get(peer,{})
	if record.is_empty() or record.token!=token:return
	var completed: Dictionary=record.receiver.finish(Time.get_ticks_msec())
	if completed.has("error"):_usb_cancel(peer,token);return
	var decoded: Variant=bytes_to_var(completed.bytes)
	var id: String=record.station
	if not UsbArchive._valid_entries(decoded,int(record.capacity)*1024*1024) or not game.session.roster.has(peer) or _identity(peer)!=record.identity or not stations.has(id):_usb_cancel(peer,token);return
	var device=stations[id].power
	var profile: Dictionary=game.dorm_interactions._profile(record.identity).duplicate(true)
	var dorm: Dictionary=profile.get("dorm",{})
	var item: Dictionary=dorm.get("usb_drives",{}).get(record.id,{})
	if device.powered or not device.usb.is_empty() or item.get("location","")!="hotbar" or int(item.get("capacity_mb",0))!=int(record.capacity) or "usb:"+str(record.id) not in dorm.get("carry_items",[]) or game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(stations[id].anchor)>3:_usb_cancel(peer,token);return
	dorm.carry_items.erase("usb:"+str(record.id));item.location="connected";dorm.revision+=1
	var saved: Dictionary=game.dorm_interactions._commit_world_inventory(peer,record.identity,profile)
	if not saved.ok:_usb_cancel(peer,token);return
	var drive=UsbDrive.new(int(record.capacity)*1024*1024);drive.entries=decoded
	device.usb={"owner":record.identity,"id":record.id,"capacity_mb":record.capacity,"name":item.name,"drive":drive,"remote":true,"configuration":item.get("configuration",{})}
	_publish_usb_ports()
	usb_uploads.erase(peer)
	_error(peer,"USB drive connected.")

@rpc("any_peer","call_remote","reliable",6)
func _usb_upload_cancel(token: String) -> void:
	if multiplayer.is_server():_usb_cancel(multiplayer.get_remote_sender_id(),token)
func _usb_cancel(peer: int,token: String) -> void:
	if usb_uploads.has(peer) and usb_uploads[peer].token==token:usb_uploads.erase(peer)

func _local_usb_port(peer: int,id: String) -> void:
	if peer!=multiplayer.get_unique_id() or not stations.has(id) or not (stations[id].get("public_device",false) or stations[id].get("portable",false)):return
	if _workstation_distance(peer,stations[id].anchor)>3:
		_error(peer,"Move closer to the USB port.")
		return
	var device=stations[id].power
	var profile=game.electronics.profile
	var dorm: Dictionary=profile.data.get("dorm",{})
	var before: Dictionary=profile.data.duplicate(true)
	if not device.usb.is_empty():
		if device.powered:_error(peer,"Turn off the computer before removing the USB drive.");return
		var usb_id: String=device.usb.id
		if device.usb.owner!=_identity(peer) or dorm.get("usb_drives",{}).get(usb_id,{}).get("location","")!="connected":_error(peer,"USB ownership could not be verified.");return
		var carried: Array=dorm.get("carry_items",[]).duplicate()
		if carried.size()+dorm.get("carried_components",[]).size()>=6:_error(peer,"Free a hotbar slot first.");return
		if device.save_local_usb()!=OK:_error(peer,"USB data could not be saved.");return
		carried.append("usb:"+usb_id);dorm.carry_items=carried;dorm.usb_drives[usb_id].location="hotbar";dorm.revision+=1
		if profile.save()!=OK:profile.data=before;_error(peer,"USB removal could not be saved.");return
		device.usb={};_publish_usb_ports();_error(peer,"USB drive removed.");return
	if device.powered:_error(peer,"Turn off the computer before connecting a USB drive.");return
	var active: int=game.hotbar.active
	if active not in range(game.hotbar.slots.size()) or game.hotbar.slots[active].get("kind","")!="usb":_error(peer,"Hold a USB drive to connect it.");return
	var usb_id: String=str(game.hotbar.slots[active].id)
	var metadata: Dictionary=dorm.get("usb_drives",{}).get(usb_id,{})
	if metadata.get("location","")!="hotbar" or "usb:"+usb_id not in dorm.get("carry_items",[]):return
	var result: Dictionary=device.insert_local_usb(_identity(peer),usb_id,int(metadata.capacity_mb))
	if not result.get("ok",false):_error(peer,str(result.get("error","USB could not be opened.")));return
	device.usb.name=str(metadata.name)
	device.usb.configuration=metadata.get("configuration",{})
	dorm.carry_items.erase("usb:"+usb_id);metadata.location="connected";dorm.revision+=1
	if profile.save()!=OK:profile.data=before;device.usb={};_error(peer,"USB connection could not be saved.");return
	_publish_usb_ports()
	_error(peer,"USB drive connected.")
func _assignment(peer: int, action: Dictionary) -> bool:
	var id := int(action.get("paper",0))
	var paper: Dictionary=game.school.papers.get(id,{})
	if paper.is_empty() or paper.owner!=peer or not paper.get("mark",{}).is_empty():return false
	# Preserve classroom authority, seating, deadlines and grade policy. Lab hand-in
	# still requires the teacher; do not silently bypass its physical evidence checks.
	if action.op=="submit" and game.school.activity.get("kind","")!="lecture":
		_error(peer,"Take this lab paper to the teacher for submission.")
		return false
	var a := {"op":str(action.op),"id":id}
	if action.op=="answer":
		if not action.get("value") is String or str(action.value).length()>512:return false
		a.key=str(action.get("question",""))
		a.value=action.value
	game.school.apply(peer,a)
	return true
func _reply(peer: int) -> void:
	var packet: Dictionary=sessions[peer].duplicate(true)
	sessions[peer].erase("download_path")
	packet.erase("identity")
	packet.merge(workspaces[peer].duplicate(true))
	if packet.get("public_device",false):
		packet.folders=[]
		packet.binary_files={}
		packet.executable_icons={}
		packet.modified={}
		packet.copyable_downloads=[]
		var device=stations[packet.station].power
		var drive=device.drive
		packet.installed_apps=Apps.installed(drive)
		packet.app_volume="" if device.usb.is_empty() else (str(device.usb.owner)+":"+str(device.usb.id)).sha256_text()
		if not device.usb.is_empty():
			packet.usb_storage={"name":str(device.usb.name),"used":drive.used_bytes(),"capacity":drive.capacity}
			packet.usb_preferences=Preferences.read(drive)
			var local: Variant=_workstation_drive(packet.station,peer)
			if local!=null:
				for path: String in local.entries:
					if path.begins_with("Downloads/") and path.count("/")==1 and local.entries[path].type=="file":packet.copyable_downloads.append(path)
		packet.recycle_available=device.usb.is_empty()
		packet.erase("recycle")
		if packet.recycle_available:
			packet.recycle=[]
			for id in workspaces[peer].get("recycle",{}):
				var record: Dictionary=workspaces[peer].recycle[id]
				var recycled: Dictionary=drive.entries.get(record.stored,{})
				var item: Dictionary={"id":id,"path":record.original,"deleted":record.deleted,"folder":recycled.get("type","")=="folder"}
				if recycled.has("data"):item.bytes=recycled.data.size()
				packet.recycle.append(item)
		for path in packet.files.keys():
			if str(path).begins_with(".Recycle/"):packet.files.erase(path)
		var icon_bytes:=0
		for name: String in drive.entries:
			if name==".Recycle" or name.begins_with(".Recycle/") or name.to_lower()==Preferences.PATH or name==Apps.DATA_ROOT or name.begins_with(Apps.DATA_ROOT+"/"):continue
			if drive.entries[name].has("modified"):packet.modified[name]=drive.entries[name].modified
			if drive.entries[name].type=="folder":packet.folders.append(name)
			elif not packet.files.has(name) and Files.path(name)==name:
				packet.binary_files[name]=drive.entries[name].data.size()
				if icon_bytes<65536 and name.get_extension().to_lower() in ["exe","dll"]:
					var icon: PackedByteArray=drive.executable_icon(name)
					if not icon.is_empty():
						packet.executable_icons[name]=icon
						icon_bytes+=icon.size()
	packet.restored=restored.has(peer)
	packet.assignments=[]
	for paper in game.school.papers.values():
		if paper.owner!=peer:continue
		var safe: Dictionary=game.school._public_project(paper.project,not paper.mark.is_empty() or paper.lesson)
		packet.assignments.append({"id":paper.id,"title":str(safe.get("title","Assignment")),"questions":safe.get("questions",[]),"answers":paper.answers.duplicate(true),"mark":paper.mark.duplicate(true),"can_submit":paper.mark.is_empty() and game.school.activity.get("kind","")=="lecture"})
	packet.materials=[]
	if game.school.phase=="lesson":
		var stage: Dictionary=game.school.teaching_stage()
		packet.materials.append({"title":str(stage.get("title","Lesson")),"text":str(stage.get("text",stage.get("caption","")))})
	if peer==multiplayer.get_unique_id():_receive(packet)
	elif game.session.online:_private.rpc_id(peer,packet)

func _workstation_drive(station: String,peer: int) -> Variant:
	var identity:=_identity(peer)
	var key:=identity if not identity.is_empty() else "connection:%d"%peer
	return station_users.get(station,{}).get(key,{}).get("drive")
@rpc("authority","call_remote","reliable",6)
func _private(packet: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive(packet)
func _receive(packet: Dictionary) -> void:
	local_snapshot=packet.duplicate(true)
	if packet.is_empty():
		file_read.clear()
		local_restore_failure=""
		desktop_changed.emit({});return
	if not packet.get("restored",false):
		if not local_restore_failure.is_empty():
			local_snapshot.local_error=local_restore_failure
			desktop_changed.emit(local_snapshot.duplicate(true))
			return
		var loaded: Dictionary=Documents.load_state(local_profile)
		if loaded.status=="error":
			local_restore_failure=str(loaded.message)+" Original data was left untouched. Repair the local save, then retry."
			local_snapshot.local_error=local_restore_failure
			operation_failed.emit(local_restore_failure)
			desktop_changed.emit(local_snapshot.duplicate(true))
			return
		request({"op":"restore","lease":packet.lease,"revision":packet.revision,"files":loaded.files,"editor":loaded.editor})
		return
	local_restore_failure=""
	if not packet.get("public_device",false):
		var error := Documents.save_documents(local_profile,packet.files,packet.editor)
		if error!=OK:
			local_snapshot.local_error="Documents are in memory; local save failed (%d). Retry before leaving this computer."%error
			operation_failed.emit(local_snapshot.local_error)
	desktop_changed.emit(local_snapshot.duplicate(true))

func retry_local_documents() -> void:
	if local_snapshot.is_empty() or local_profile.is_empty() or local_snapshot.get("public_device",false):return
	if not local_snapshot.get("restored",false):
		local_restore_failure=""
		_receive(local_snapshot.duplicate(true))
		return
	var error := Documents.save_documents(local_profile,local_snapshot.get("files",{}),local_snapshot.get("editor",{}))
	if error!=OK:
		local_snapshot.local_error="Documents are in memory; local save failed (%d). Retry before leaving this computer."%error
		operation_failed.emit(local_snapshot.local_error)
	else:local_snapshot.erase("local_error")
	desktop_changed.emit(local_snapshot.duplicate(true))
func _error(peer: int, message: String) -> void:
	if peer==multiplayer.get_unique_id():operation_failed.emit(message)
	elif game.session.online and peer in multiplayer.get_peers():_failed.rpc_id(peer,message)
@rpc("authority","call_remote","reliable",6)
func _failed(message: String) -> void:
	if multiplayer.get_remote_sender_id()==1:operation_failed.emit(message)
# Screen previews are presentation data. The host derives the station from the
# sender's current lease and forwards only to nearby players.
const SCREEN_SIZE := Vector2i(128,72)
const SCREEN_BYTES := SCREEN_SIZE.x * SCREEN_SIZE.y * 3
const SCREEN_INTERVAL_MS := 100
var last_screen_frame := {}
var last_screen_delivery := {}
signal monitor_frame(station: String, sender: int, pixels: PackedByteArray)

static func screen_preview_interval(position: Vector3, anchor: Vector3) -> int:
	var distance:=position.distance_to(anchor)
	if distance>2.0:return 0
	return roundi(lerpf(float(SCREEN_INTERVAL_MS),700.0,smoothstep(.65,2.0,distance)))

static func local_screen_interval(distance: float, settings: Dictionary) -> int:
	var cutoff:=float(settings.distance)
	if cutoff<=0.0 or distance>cutoff:return 0
	var near_fps:=float(settings.near_fps)
	var edge_fps:=minf(near_fps,float(settings.edge_fps))
	return roundi(lerpf(1000.0/near_fps,1000.0/edge_fps,smoothstep(cutoff*.325,cutoff,distance)))

func submit_monitor_frame(lease: int, pixels: PackedByteArray) -> void:
	if not game.session.online: return
	if multiplayer.is_server():
		_forward_monitor_frame(multiplayer.get_unique_id(), lease, pixels)
	else:
		_submit_monitor_frame.rpc_id(1, lease, pixels)

@rpc("any_peer", "call_remote", "unreliable", 6)
func _submit_monitor_frame(lease: int, pixels: PackedByteArray) -> void:
	if multiplayer.is_server():
		_forward_monitor_frame(multiplayer.get_remote_sender_id(), lease, pixels)

func _forward_monitor_frame(peer: int, lease: int, pixels: PackedByteArray) -> void:
	var current: Dictionary = sessions.get(peer, {})
	if current.is_empty() or current.lease != lease or pixels.size() > SCREEN_BYTES: return
	var station: String = current.station
	var device: Dictionary = stations[station]
	if device.get("portable", false) or not device.get("private_owner", "").is_empty(): return
	if not device.has("power") or not device.power.powered or not _has_access(peer, device): return
	var now := Time.get_ticks_msec()
	if not pixels.is_empty() and now - int(last_screen_frame.get(peer, -SCREEN_INTERVAL_MS)) < SCREEN_INTERVAL_MS: return
	last_screen_frame[peer] = now
	var delivered: Dictionary=last_screen_delivery.get_or_add(peer,{})
	for receiver in game.session.roster:
		if receiver == peer: continue
		var pose: Vector3 = game.session.poses.get(receiver, {}).get("position", Vector3.INF)
		var interval:=screen_preview_interval(pose+Vector3.UP*1.4,device.get("preview_position",device.anchor))
		if interval==0 or (not pixels.is_empty() and now-int(delivered.get(receiver,-1000))<interval):continue
		delivered[receiver]=now
		if receiver == multiplayer.get_unique_id():
			monitor_frame.emit(station, peer, pixels)
		elif game.session.peer_connected_now(int(receiver)):
			_receive_monitor_frame.rpc_id(receiver, station, peer, pixels)

@rpc("authority", "call_remote", "unreliable", 6)
func _receive_monitor_frame(station: String, sender: int, pixels: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		monitor_frame.emit(station, sender, pixels)

func _publish() -> void:
	var public := {}
	for peer in sessions:public[sessions[peer].station]=peer
	occupancy_changed.emit(public)
	if game.session.online:_occupancy.rpc(public)
	var power := {}
	for id in stations:
		if stations[id].has("power"):power[id]=stations[id].power.powered
	power_changed.emit(power)
	if game.session.online:_power_state.rpc(power)
	_publish_usb_ports()
	var boot := {}
	for id in stations:
		var remaining := int(stations[id].get("ready_at",0))-Time.get_ticks_msec()
		if power.get(id,false) and remaining>0:boot[id]={"cycle":int(stations[id].get("cycle",0)),"remaining":remaining}
	boot_changed.emit(boot)
	if game.session.online:_boot_state.rpc(boot)

@rpc("authority","call_remote","reliable",6)
func _boot_state(boot: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:boot_changed.emit(boot)
@rpc("authority","call_remote","reliable",6)
func _occupancy(public: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:occupancy_changed.emit(public)
@rpc("authority","call_remote","reliable",6)
func _power_state(power: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:power_changed.emit(power)

func _publish_usb_ports() -> void:
	var ports:={}
	var mounts_by_owner:={}
	for id in stations:
		if not stations[id].has("power"):continue
		var usb: Dictionary=stations[id].power.usb
		if usb.is_empty():continue
		var configuration: Dictionary=usb.get("configuration",{})
		ports[id]=true if configuration.is_empty() else {"appearance":configuration.appearance}
		if configuration.has("decoration"):ports[id].decoration=configuration.decoration
		mounts_by_owner.get_or_add(usb.owner,{})[id]={"id":usb.id,"capacity":usb.capacity_mb}
	_set_usb_ports(ports)
	if game.session.online and multiplayer.is_server():
		_usb_port_state.rpc(ports)
		for peer in game.session.roster:
			if peer!=multiplayer.get_unique_id() and game.session.peer_connected_now(int(peer)):
				_owned_usb_mount_state.rpc_id(peer,mounts_by_owner.get(_identity(peer),{}))

@rpc("authority","call_remote","reliable",6)
func _owned_usb_mount_state(mounts: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()!=1 or owned_usb_mounts==mounts:return
	var previous:=owned_usb_mounts
	owned_usb_mounts=mounts
	for station in previous:
		if not mounts.has(station):owned_usb_preferences.erase(station)
	for station in mounts:
		var mount: Dictionary=mounts[station]
		if previous.get(station)==mount:continue
		var loaded:=UsbArchive.load(game.school.local_identity,str(mount.id),int(mount.capacity))
		_cache_owned_usb_preferences(station,loaded.get("drive"))
	owned_usb_preferences_changed.emit()

func _cache_owned_usb_preferences(station: String,drive: RefCounted) -> bool:
	var bytes:=PackedByteArray()
	if drive!=null:bytes=drive.entries.get(Preferences.PATH,{}).get("data",PackedByteArray())
	if bytes==owned_usb_preferences.get(station,PackedByteArray()):return false
	if bytes.is_empty():owned_usb_preferences.erase(station)
	else:owned_usb_preferences[station]=bytes
	return true

@rpc("authority","call_remote","reliable",6)
func _usb_port_state(ports: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:_set_usb_ports(ports)

func _set_usb_ports(ports: Dictionary) -> void:
	if ports==connected_usb_ports:return
	connected_usb_ports=ports.duplicate()
	connected_usb_changed.emit(connected_usb_ports)
func _close(peer: int, release: bool) -> void:
	if not sessions.has(peer):return
	var was_public: bool=bool(sessions[peer].get("public_device",false))
	var chair_index:=int(stations[sessions[peer].station].get("chair",-1))
	sessions.erase(peer)
	download_uploads.erase(peer)
	last_screen_frame.erase(peer)
	last_screen_delivery.erase(peer)
	for delivered: Dictionary in last_screen_delivery.values():delivered.erase(peer)
	if was_public:workspaces.erase(peer);restored.erase(peer)
	if release and chair_index>=0 and game.chairs[chair_index].occupant==peer:
		game._release_chair(peer)
		game._send_chairs()
		if peer==multiplayer.get_unique_id() and game.player.seated!=null:game.player.stand_up()
	if peer==multiplayer.get_unique_id():_receive({})
	elif game.session.online and game.session.roster.has(peer):_private.rpc_id(peer,{})
	_publish()
func _power_off(id: String) -> void:
	if not stations.has(id) or not stations[id].has("power"):return
	stations[id].power.turn_off()
	public_workspaces.erase(id)
	station_users.erase(id)
	for peer in sessions.keys():
		if sessions[peer].station==id:
			if bool(sessions[peer].get("public_device",false)):
				workspaces.erase(peer);restored.erase(peer)
			_close(peer,false)
	_publish()
func _prune() -> void:
	var now:=Time.get_ticks_msec()
	for token in owner_copy_transfers.keys():
		if now-int(owner_copy_transfers[token].receiver.last_activity_ms)>UsbTransfer.TIMEOUT_MS:owner_copy_transfers.erase(token)
	if not multiplayer.is_server():return
	for peer in download_uploads.keys():
		var upload: Dictionary=download_uploads[peer]
		if sessions.get(peer,{}).get("revision")!=upload.revision:
			download_uploads.erase(peer)
		elif now-int(upload.receiver.last_activity_ms)>UsbTransfer.TIMEOUT_MS:
			download_uploads.erase(peer)
			_error(peer,"The download transfer timed out.")
	for station in usb_writes.keys():
		var pending: Dictionary=usb_writes[station]
		if Time.get_ticks_msec()-int(pending.started)<30000 and game.session.roster.has(int(pending.owner_peer)):continue
		var device=stations[station].power
		var ledger=game.electronics_trade.authority.ledger
		var next: Dictionary=ledger.state.duplicate(true)
		var account: Dictionary=next.get("accounts",{}).get(str(device.usb.owner),{})
		var item: Dictionary=account.get("profile",{}).get("dorm",{}).get("usb_drives",{}).get(str(device.usb.id),{})
		if item.get("location","")!="connected":continue
		item.location="lost";account.profile.dorm.revision+=1;account.revision+=1
		if not ledger.persist(next):continue
		usb_writes.erase(station)
		if game.session.roster.has(int(pending.owner_peer)):game.electronics_trade.authority.send_snapshot(int(pending.owner_peer),ledger.snapshot(int(pending.owner_peer)))
		_power_off(station);device.usb={}
		_error(int(pending.actor),"USB save was interrupted; retrieve the drive from lost and found.")
	for peer in usb_uploads.keys():
		if not game.session.roster.has(peer) or Time.get_ticks_msec()-int(usb_uploads[peer].started)>UsbTransfer.TIMEOUT_MS:usb_uploads.erase(peer)
	if game.session.online:
		for id in stations:
			if not stations[id].has("power"):continue
			var device=stations[id].power
			if device.usb.is_empty() or not device.usb.get("remote",false):continue
			var owner: String=device.usb.owner
			if game.electronics_trade.authority.ledger.bindings.values().has(owner) and game.session.roster.keys().any(func(peer):return _identity(peer)==owner):continue
			var ledger=game.electronics_trade.authority.ledger
			var next: Dictionary=ledger.state.duplicate(true)
			var account: Dictionary=next.get("accounts",{}).get(owner,{})
			var item: Dictionary=account.get("profile",{}).get("dorm",{}).get("usb_drives",{}).get(str(device.usb.id),{})
			if item.get("location","")!="connected":continue
			item.location="lost";account.profile.dorm.revision+=1;account.revision+=1
			if ledger.persist(next):
				_power_off(id)
				device.usb={}
	for id in stations:
		if stations[id].has("power") and stations[id].power.powered and not usb_writes.has(id) and Time.get_ticks_msec()-stations[id].power.last_activity_ms>=stations[id].power.IDLE_TIMEOUT_MS:_power_off(id)
	for peer in sessions.keys():
		var entry: Dictionary=stations[sessions[peer].station]
		if not game.session.roster.has(peer) or not _private_allowed(peer,entry) or not _has_access(peer,entry):_close(peer,false)
	for peer in workspaces.keys():
		if not game.session.roster.has(peer):
			workspaces.erase(peer);workspace_identities.erase(peer)
			restored.erase(peer)
			last_request.erase(peer)
func _roster_power() -> void:
	if multiplayer.is_server():_publish()
func _reset() -> void:
	set_meta("resetting",true)
	usb_uploads.clear()
	usb_writes.clear()
	download_uploads.clear()
	owner_copy_transfers.clear()
	if game.session.online and multiplayer.is_server():
		var ledger=game.electronics_trade.authority.ledger
		var next: Dictionary=ledger.state.duplicate(true)
		var changed:=false
		for station in stations.values():
			if not station.has("power") or station.power.usb.is_empty() or not station.power.usb.get("remote",false):continue
			var usb: Dictionary=station.power.usb
			var account: Dictionary=next.get("accounts",{}).get(str(usb.owner),{})
			var item: Dictionary=account.get("profile",{}).get("dorm",{}).get("usb_drives",{}).get(str(usb.id),{})
			if item.get("location","")=="connected":
				item.location="lost";account.profile.dorm.revision+=1;account.revision+=1;changed=true
		if changed:
			if not ledger.persist(next):game.ui.log_message("Could not save connected USB recovery; the drive remains in the host inventory record.")
			else:
				for station in stations.values():
					if station.has("power") and station.power.usb.get("remote",false):station.power.usb={}
	sessions.clear()
	workspaces.clear();workspace_identities.clear()
	for id in stations:
		if stations[id].has("power"):
			var device=stations[id].power
			device.turn_off()
			# Mark the drive for the owner's client-local lost-and-found journal.
			if not game.session.online and not device.usb.is_empty():
				var profile=game.electronics.profile
				var dorm: Dictionary=profile.data.get("dorm",{})
				var usb_id: String=device.usb.id
				if dorm.get("usb_drives",{}).has(usb_id) and device.save_local_usb()==OK:
					var before: Dictionary=profile.data.duplicate(true)
					dorm.usb_drives[usb_id].location="lost";dorm.revision+=1
					if profile.save()!=OK:profile.data=before
					else:device.usb={}
	public_workspaces.clear()
	station_users.clear()
	restored.clear()
	last_request.clear()
	local_snapshot.clear()
	local_profile=""
	local_restore_failure=""
	desktop_changed.emit({})
	occupancy_changed.emit({})
	power_changed.emit({})
	owned_usb_mounts.clear()
	owned_usb_preferences.clear()
	owned_usb_preferences_changed.emit()
	_set_usb_ports({})
	set_meta("resetting",false)

