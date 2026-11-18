extends Node
signal desktop_changed(snapshot: Dictionary)
signal occupancy_changed(occupancy: Dictionary)
signal power_changed(power: Dictionary)
signal boot_changed(boot: Dictionary)
signal operation_failed(message: String)
signal usb_write_prepared(station: String, token: String)
signal usb_write_committed(station: String, token: String)
const Files = preload("res://scripts/campus/computers/virtual_files.gd")
const Documents = preload("res://scripts/campus/computers/local_documents.gd")
const UsbArchive = preload("res://scripts/campus/computers/usb_archive.gd")
const UsbTransfer = preload("res://scripts/campus/computers/usb_transfer.gd")
const UsbDrive = preload("res://scripts/campus/computers/device_filesystem.gd")
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
func supports_operation(op: String) -> bool:
	return op=="rename"
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
func register_portable(id: String,anchor: Vector3,owner: String,tier: String) -> bool:
	var tiers=preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS
	if id.length()>48 or Files.path(id)!=id or id.contains("/") or stations.has(id) or not anchor.is_finite() or not tiers.has(tier) or not preload("res://scripts/campus/dorms/authority/persistent_dorm.gd").identity_ok(owner):return false
	stations[id]={"chair":-1,"anchor":anchor,"private_owner":owner,"portable":true,"tier":tier,"power":preload("res://scripts/campus/computers/device_power.gd").new()}
	return true

func unregister_portable(id: String) -> bool:
	if not stations.has(id) or not stations[id].get("portable",false) or stations[id].power.powered or not stations[id].power.usb.is_empty() or sessions.values().any(func(session):return session.station==id):return false
	stations.erase(id);public_workspaces.erase(id);station_users.erase(id);return true

func _has_access(peer: int,entry: Dictionary) -> bool:
	if entry.get("portable",false):return game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(entry.anchor)<=3
	return int(entry.chair)>=0 and game.chairs[entry.chair].occupant==peer
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
	if action.get("op","")=="usb_port" and game.session.online:
		action=action.duplicate()
		var slot: int=game.hotbar.active
		if slot in range(game.hotbar.slots.size()) and game.hotbar.slots[slot].get("kind","")=="usb":action.id=str(game.hotbar.slots[slot].id)
	if action.get("op","")=="exit" and game.get("player")!=null and game.player.seated!=null:
		game._stand_from_chair()
		if game.player.seated!=null:
			operation_failed.emit("Move clear of the desk before standing.")
			return
	if action.get("op","")=="enter":
		var identity: String=game.school.local_identity
		if identity.is_empty():operation_failed.emit("Select a student profile first.");return
		if local_profile!=identity:local_restore_failure=""
		local_profile=identity
	if multiplayer.is_server():_accept(multiplayer.get_unique_id(),action)
	elif game.session.online:_request.rpc_id(1,action)
@rpc("any_peer","call_remote","reliable",6)
func _request(action: Dictionary) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),action)
func _accept(peer: int, action: Dictionary) -> void:
	if not game.session.roster.has(peer) or action.size()>9 or action.has("owner") or action.has("profile") or action.has("identity"):return
	var op: String=str(action.get("op",""))
	if op=="usb_port":
		if game.session.online:_network_usb_port(peer,str(action.get("station","")),str(action.get("id","")));return
		_local_usb_port(peer,str(action.get("station","")))
		return
	if op=="power":
		var id:=str(action.get("station",""))
		if not stations.has(id) or not stations[id].has("power") or not _private_allowed(peer,stations[id]):return
		if game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(stations[id].anchor)>3:return
		var device=stations[id].power
		if usb_writes.has(id):_error(peer,"Wait for the USB save to finish.");return
		if device.powered:_power_off(id)
		else:
			device.turn_on(Time.get_ticks_msec())
			power_cycle+=1
			stations[id].cycle=power_cycle
			if not stations[id].get("portable",false):stations[id].ready_at=Time.get_ticks_msec()+1600
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
		var position: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
		if position.distance_to(entry.anchor)>3:return
		if not entry.get("portable",false):
			var chair = game.chairs[entry.chair]
			if chair.occupant!=0 and not game.session.roster.has(chair.occupant):
				game._release_chair(chair.occupant)
			if chair.occupant==0:game._claim_chair(peer,entry.chair)
			if chair.occupant!=peer:return
		serial+=1
		var identity := _identity(peer)
		if workspace_identities.get(peer,"__unbound__")!=identity:
			workspaces.erase(peer);restored.erase(peer)
		workspace_identities[peer]=identity
		sessions[peer]={"station":id,"lease":serial,"revision":0,"identity":identity}
		if entry.get("portable",false):sessions[peer].tier=entry.tier
		if entry.has("power"):
			entry.power.touch(Time.get_ticks_msec())
			sessions[peer].power_cycle=int(entry.get("cycle",0))
		if entry.get("public_device",false) or entry.get("portable",false):
			var profiles: Dictionary=station_users.get_or_add(id,{})
			var owner_key := identity if not identity.is_empty() else "connection:%d"%peer
			if not profiles.has(owner_key):
				if profiles.size()>=16:profiles.erase(profiles.keys()[0])
				var local_drive=preload("res://scripts/campus/computers/device_filesystem.gd").new()
				profiles[owner_key]={"workspace":{"files":{},"editor":{}},"drive":local_drive}
				if not entry.power.usb.is_empty():
					for path in entry.power.usb.drive.entries:
						var file: Dictionary=entry.power.usb.drive.entries[path]
						if file.type=="file" and Files.path(path)==path:
							var bytes: PackedByteArray=file.data
							var text:=bytes.get_string_from_utf8()
							if text.to_utf8_buffer()==bytes:profiles[owner_key].workspace.files[path]={"text":text,"version":1}
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
	if action.get("lease",-1)!=session.lease or action.get("revision",-1)!=session.revision:return
	if op=="exit":_close(peer,true);return
	var entry: Dictionary=stations[session.station]
	if usb_writes.has(session.station):_error(peer,"Wait for the USB save to finish.");return
	if not _has_access(peer,entry):_close(peer,false);return
	if entry.has("power"):entry.power.touch(Time.get_ticks_msec())
	if op in ["browser","run"]:_error(peer,"Unavailable: browser and code execution are not installed.");return
	var now := Time.get_ticks_msec()
	if now-int(last_request.get(peer,-1000))<60:_error(peer,"Please retry after the current operation.");return
	last_request[peer]=now
	var workspace: Dictionary=workspaces[peer]
	var file_device := bool(session.get("public_device", false))
	var usb_before: Dictionary=entry.power.usb.drive.entries.duplicate(true) if file_device and not entry.power.usb.is_empty() and op in ["save","mkdir","delete","rename"] else {}
	var workspace_before: Dictionary=workspace.duplicate(true) if not usb_before.is_empty() or (file_device and not entry.power.usb.is_empty() and op in ["save","mkdir","delete","rename"]) else {}
	if str(action.get("path","")).to_lower().begins_with(".recycle") or str(action.get("new_path","")).to_lower().begins_with(".recycle"):
		_error(peer,"That path is reserved.");return
	match op:
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
		_begin_usb_write(peer,session.station,action,usb_before,workspace_before)
		return
	if not workspace_before.is_empty() and entry.power.save_local_usb()!=OK:
		entry.power.usb.drive.entries=usb_before
		workspace.clear();workspace.merge(workspace_before,true)
		_error(peer,"USB save failed; the change was not applied.")
		return
	session.revision+=1
	_reply(peer)

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

func _begin_usb_write(actor: int,station: String,action: Dictionary,old_entries: Dictionary,old_workspace: Dictionary) -> void:
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
	if action.op=="rename":operation.new_path=str(action.get("new_path",""))
	usb_writes[station]={"token":token,"owner_peer":owner_peer,"actor":actor,"lease":sessions[actor].lease,"entries":old_entries,"workspace":old_workspace,"started":Time.get_ticks_msec()}
	if owner_peer==multiplayer.get_unique_id():_apply_owner_usb_write(station,token,str(usb.id),int(usb.capacity_mb),operation)
	else:_usb_write_requested.rpc_id(owner_peer,station,token,str(usb.id),int(usb.capacity_mb),operation)

@rpc("authority","call_remote","reliable",6)
func _usb_write_requested(station: String,token: String,id: String,capacity: int,operation: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:_apply_owner_usb_write(station,token,id,capacity,operation)

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
			"save":ok=operation.get("text") is String and drive.write_file(path,str(operation.text).to_utf8_buffer())
			"mkdir":ok=drive.make_folder(path)
			"delete":ok=drive.remove(path)
			"rename":ok=drive.move(path,str(operation.get("new_path","")))
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
	if multiplayer.is_server():_finish_usb_commit(multiplayer.get_unique_id(),station,token,ok)
	else:_usb_commit_ack.rpc_id(1,station,token,ok)

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
		sessions[actor].revision+=1
		_reply(actor)

func _network_usb_port(peer: int,id: String,usb_id: String) -> void:
	if not stations.has(id) or not (stations[id].get("public_device",false) or stations[id].get("portable",false)) or not _private_allowed(peer,stations[id]):return
	if game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(stations[id].anchor)>3:return
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
		device.usb={};_error(peer,"USB drive removed.");return
	if usb_uploads.size()>=4 or usb_uploads.has(peer) or usb_uploads.values().any(func(record):return record.station==id):_error(peer,"A USB transfer is already in progress.");return
	var item: Dictionary=dorm.get("usb_drives",{}).get(usb_id,{})
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
	device.usb={"owner":record.identity,"id":record.id,"capacity_mb":record.capacity,"name":item.name,"drive":drive,"remote":true}
	usb_uploads.erase(peer)
	_error(peer,"USB drive connected.")

@rpc("any_peer","call_remote","reliable",6)
func _usb_upload_cancel(token: String) -> void:
	if multiplayer.is_server():_usb_cancel(multiplayer.get_remote_sender_id(),token)
func _usb_cancel(peer: int,token: String) -> void:
	if usb_uploads.has(peer) and usb_uploads[peer].token==token:usb_uploads.erase(peer)

func _local_usb_port(peer: int,id: String) -> void:
	if peer!=multiplayer.get_unique_id() or not stations.has(id) or not (stations[id].get("public_device",false) or stations[id].get("portable",false)):return
	if game.session.poses.get(peer,{}).get("position",Vector3.INF).distance_to(stations[id].anchor)>3:return
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
		device.usb={};_error(peer,"USB drive removed.");return
	if device.powered:_error(peer,"Turn off the computer before connecting a USB drive.");return
	var active: int=game.hotbar.active
	if active not in range(game.hotbar.slots.size()) or game.hotbar.slots[active].get("kind","")!="usb":_error(peer,"Hold a USB drive to connect it.");return
	var usb_id: String=str(game.hotbar.slots[active].id)
	var metadata: Dictionary=dorm.get("usb_drives",{}).get(usb_id,{})
	if metadata.get("location","")!="hotbar" or "usb:"+usb_id not in dorm.get("carry_items",[]):return
	var result: Dictionary=device.insert_local_usb(_identity(peer),usb_id,int(metadata.capacity_mb))
	if not result.get("ok",false):_error(peer,str(result.get("error","USB could not be opened.")));return
	device.usb.name=str(metadata.name)
	dorm.carry_items.erase("usb:"+usb_id);metadata.location="connected";dorm.revision+=1
	if profile.save()!=OK:profile.data=before;device.usb={};_error(peer,"USB connection could not be saved.");return
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
	packet.erase("identity")
	packet.merge(workspaces[peer].duplicate(true))
	if packet.get("public_device",false):
		packet.folders=[]
		var device=stations[packet.station].power
		var drive=device.drive
		packet.recycle_available=device.usb.is_empty()
		packet.erase("recycle")
		if packet.recycle_available:
			packet.recycle=[]
			for id in workspaces[peer].get("recycle",{}):
				var record: Dictionary=workspaces[peer].recycle[id]
				packet.recycle.append({"id":id,"path":record.original,"deleted":record.deleted})
		for path in packet.files.keys():
			if str(path).begins_with(".Recycle/"):packet.files.erase(path)
		for name in drive.entries:
			if str(name)==".Recycle" or str(name).begins_with(".Recycle/"):continue
			if drive.entries[name].type=="folder":packet.folders.append(name)
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
@rpc("authority","call_remote","reliable",6)
func _private(packet: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive(packet)
func _receive(packet: Dictionary) -> void:
	local_snapshot=packet.duplicate(true)
	if packet.is_empty():
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
const SCREEN_SIZE := Vector2i(160, 90)
const SCREEN_BYTES := 160 * 90 * 3
const SCREEN_INTERVAL_MS := 250
var last_screen_frame := {}
signal monitor_frame(station: String, sender: int, pixels: PackedByteArray)

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
	for receiver in game.session.roster:
		if receiver == peer: continue
		var pose: Vector3 = game.session.poses.get(receiver, {}).get("position", Vector3.INF)
		if pose.distance_squared_to(device.anchor) > 64.0: continue
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
	var boot := {}
	for id in stations:
		var remaining := int(stations[id].get("ready_at",0))-Time.get_ticks_msec()
		if power.get(id,false) and remaining>0:boot[id]=int(stations[id].get("cycle",0))
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
func _close(peer: int, release: bool) -> void:
	if not sessions.has(peer):return
	var was_public: bool=bool(sessions[peer].get("public_device",false))
	var portable: bool=stations[sessions[peer].station].get("portable",false)
	sessions.erase(peer)
	last_screen_frame.erase(peer)
	if was_public:workspaces.erase(peer);restored.erase(peer)
	if release and not portable:
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
			_close(peer,true)
	_publish()
func _prune() -> void:
	if not multiplayer.is_server():return
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
	set_meta("resetting",false)

