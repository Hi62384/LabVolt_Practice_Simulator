extends Node
## Host-coordinated, two-client handoff. Inventory stays reserved until the
## recipient has saved a validated archive and the ledger commits both sides.
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Chunks=preload("res://scripts/campus/computers/usb_transfer.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
var world: Node
var game: Node
var pending := {}
var incoming := {}

func build(owner_world: Node) -> void:
	world=owner_world;game=world.game
	game.session.roster_changed.connect(_prune)
	game.session.leaving.connect(func():pending.clear();incoming.clear())
	var timer:=Timer.new();timer.wait_time=1.0;timer.timeout.connect(_prune);add_child(timer);timer.start()

func start(target: int,drop_id: int,slots: int) -> void:
	if not multiplayer.is_server() or not game.session.online or pending.size()>=4 or slots<=0:return
	var drop: Dictionary=world.drops.get(drop_id,{})
	var source:=int(drop.get("owner",0));var usb: Dictionary=drop.get("parcel",{}).get("usb",{})
	if source==target or not game.session.roster.has(source) or usb.is_empty():return
	if pending.values().any(func(record):return record.drop==drop_id or record.source==source or record.target==target):return
	var ledger=game.electronics_trade.authority.ledger
	var source_account: Dictionary=ledger.account(source);var target_account: Dictionary=ledger.account(target)
	var source_item: Dictionary=source_account.get("profile",{}).get("dorm",{}).get("usb_drives",{}).get(str(usb.id),{})
	var dest: Dictionary=target_account.get("profile",{}).get("dorm",{})
	if source_item.get("location","")!="lost" or str(usb.owner)!=str(ledger.bindings.get(source,"")) or dest.is_empty() or dest.get("usb_drives",{}).has(str(usb.id)) or dest.get("carry_items",[]).size()+dest.get("carried_components",[]).size()>=6:
		world._notice(target,"USB ownership or inventory space changed.");return
	var token:=Crypto.new().generate_random_bytes(16).hex_encode()
	var next: Dictionary=ledger.state.duplicate(true)
	var owner: String=ledger.bindings[source]
	var source_profile: Dictionary=next.accounts[owner].profile
	source_profile.dorm.usb_drives[usb.id].location="handoff"
	if not source_profile.has("usb_handoff_pending"):source_profile.usb_handoff_pending={}
	source_profile.usb_handoff_pending[usb.id]=token
	source_profile.dorm.revision+=1;next.accounts[owner].revision+=1
	if not ledger.persist(next):world._notice(target,"USB reservation could not be saved.");return
	pending[token]={"source":source,"target":target,"drop":drop_id,"id":str(usb.id),"capacity":int(usb.capacity_mb),"name":str(usb.name),"receiver":Chunks.new(),"phase":"upload","started":Time.get_ticks_msec()}
	game.electronics_trade.authority.send_snapshot(source,ledger.snapshot(source))
	if source==multiplayer.get_unique_id():_prepare_source(token,str(usb.id),int(usb.capacity_mb))
	else:prepare_source.rpc_id(source,token,str(usb.id),int(usb.capacity_mb))

@rpc("authority","call_remote","reliable",6)
func prepare_source(token: String,id: String,capacity: int) -> void:
	if multiplayer.get_remote_sender_id()==1:_prepare_source(token,id,capacity)

func _prepare_source(token: String,id: String,capacity: int) -> void:
	var profile=game.electronics.profile
	var item: Dictionary=profile.data.get("dorm",{}).get("usb_drives",{}).get(id,{})
	var loaded: Dictionary=Archive.load(game.school.local_identity,id,capacity)
	if item.get("location","")!="handoff" or profile.data.get("usb_handoff_pending",{}).get(id,"")!=token or int(item.get("capacity_mb",0))!=capacity or loaded.has("error"):
		_send_abort(token);return
	var before: Dictionary=profile.data.duplicate(true)
	item.location="handoff"
	if not profile.data.has("usb_handoff_pending"):profile.data.usb_handoff_pending={}
	profile.data.usb_handoff_pending[id]=token
	var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
	var error: Error=profile.save();profile.authority_submit=callback
	if error!=OK:profile.data=before;_send_abort(token);return
	var bytes:=var_to_bytes(loaded.drive.entries)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
	_send_begin(token,bytes.size(),hash.finish().hex_encode())
	for offset in range(0,bytes.size(),Chunks.CHUNK_SIZE):
		if not game.session.online:return
		_send_chunk(token,offset,bytes.slice(offset,mini(offset+Chunks.CHUNK_SIZE,bytes.size())))
		await get_tree().process_frame
	_send_finish(token)

func _send_begin(token: String,size: int,digest: String) -> void:
	if multiplayer.is_server():_begin(multiplayer.get_unique_id(),token,size,digest)
	else:upload_begin.rpc_id(1,token,size,digest)
func _send_chunk(token: String,offset: int,bytes: PackedByteArray) -> void:
	if multiplayer.is_server():_chunk(multiplayer.get_unique_id(),token,offset,bytes)
	else:upload_chunk.rpc_id(1,token,offset,bytes)
func _send_finish(token: String) -> void:
	if multiplayer.is_server():_finish(multiplayer.get_unique_id(),token)
	else:upload_finish.rpc_id(1,token)
func _send_abort(token: String) -> void:
	if multiplayer.is_server():_abort(token)
	else:abort_request.rpc_id(1,token)

@rpc("any_peer","call_remote","reliable",6)
func upload_begin(token: String,size: int,digest: String) -> void:
	if multiplayer.is_server():_begin(multiplayer.get_remote_sender_id(),token,size,digest)
func _begin(peer: int,token: String,size: int,digest: String) -> void:
	var record: Dictionary=pending.get(token,{})
	if record.is_empty() or record.source!=peer or record.phase!="upload":return
	if size>int(record.capacity)*1024*1024+Archive.MAX_OVERHEAD or not record.receiver.begin(size,digest,Time.get_ticks_msec()):_abort(token)

@rpc("any_peer","call_remote","reliable",6)
func upload_chunk(token: String,offset: int,bytes: PackedByteArray) -> void:
	if multiplayer.is_server():_chunk(multiplayer.get_remote_sender_id(),token,offset,bytes)
func _chunk(peer: int,token: String,offset: int,bytes: PackedByteArray) -> void:
	var record: Dictionary=pending.get(token,{})
	if record.is_empty() or record.source!=peer or record.phase!="upload":return
	if not record.receiver.append(offset,bytes,Time.get_ticks_msec()):_abort(token)

@rpc("any_peer","call_remote","reliable",6)
func upload_finish(token: String) -> void:
	if multiplayer.is_server():_finish(multiplayer.get_remote_sender_id(),token)
func _finish(peer: int,token: String) -> void:
	var record: Dictionary=pending.get(token,{})
	if record.is_empty() or record.source!=peer or record.phase!="upload":return
	var result: Dictionary=record.receiver.finish(Time.get_ticks_msec())
	if result.has("error"):_abort(token);return
	var entries: Variant=bytes_to_var(result.bytes)
	if not Archive._valid_entries(entries,int(record.capacity)*1024*1024):_abort(token);return
	record.phase="download";record.receiver=null
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(result.bytes)
	var digest:=hash.finish().hex_encode()
	var target: int=record.target
	if target==multiplayer.get_unique_id():_receive_begin(token,record.id,record.name,record.capacity,result.bytes.size(),digest)
	else:receive_begin.rpc_id(target,token,record.id,record.name,record.capacity,result.bytes.size(),digest)
	for offset in range(0,result.bytes.size(),Chunks.CHUNK_SIZE):
		if not pending.has(token) or not game.session.roster.has(target):return
		var bytes: PackedByteArray=result.bytes.slice(offset,mini(offset+Chunks.CHUNK_SIZE,result.bytes.size()))
		if target==multiplayer.get_unique_id():_receive_chunk(token,offset,bytes)
		else:receive_chunk.rpc_id(target,token,offset,bytes)
		await get_tree().process_frame
	if not pending.has(token):return
	if target==multiplayer.get_unique_id():_receive_finish(token)
	else:receive_finish.rpc_id(target,token)

@rpc("authority","call_remote","reliable",6)
func receive_begin(token: String,id: String,drive_name: String,capacity: int,size: int,digest: String) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive_begin(token,id,drive_name,capacity,size,digest)
func _receive_begin(token: String,id: String,drive_name: String,capacity: int,size: int,digest: String) -> void:
	if incoming.size()>=4 or token.length()!=32 or not token.is_valid_hex_number() or Archive.path(game.school.local_identity,id).is_empty() or capacity not in Archive.CAPACITIES_MB or not Archive.valid_name(drive_name) or size>capacity*1024*1024+Archive.MAX_OVERHEAD:return
	if game.electronics.profile.data.get("dorm",{}).get("usb_drives",{}).has(id):return
	var receiver=Chunks.new()
	if receiver.begin(size,digest,Time.get_ticks_msec()):incoming[token]={"id":id,"name":drive_name,"capacity":capacity,"receiver":receiver}

@rpc("authority","call_remote","reliable",6)
func receive_chunk(token: String,offset: int,bytes: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive_chunk(token,offset,bytes)
func _receive_chunk(token: String,offset: int,bytes: PackedByteArray) -> void:
	if incoming.has(token) and not incoming[token].receiver.append(offset,bytes,Time.get_ticks_msec()):incoming.erase(token)

@rpc("authority","call_remote","reliable",6)
func receive_finish(token: String) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive_finish(token)
func _receive_finish(token: String) -> void:
	var record: Dictionary=incoming.get(token,{})
	if record.is_empty():_send_receipt(token,false);return
	incoming.erase(token)
	var result: Dictionary=record.receiver.finish(Time.get_ticks_msec())
	if result.has("error"):_send_receipt(token,false);return
	var entries: Variant=bytes_to_var(result.bytes)
	if not Archive._valid_entries(entries,int(record.capacity)*1024*1024):_send_receipt(token,false);return
	var path:=Archive.path(game.school.local_identity,record.id)
	if FileAccess.file_exists(path):
		var existing: Dictionary=Archive.load(game.school.local_identity,record.id,record.capacity)
		if existing.has("error"):_send_receipt(token,false);return
		if existing.drive.entries!=entries:
			# A failed earlier handoff can leave an unowned archive at this path.
			# Preserve it before staging the newly verified contents.
			if DirAccess.copy_absolute(path,path+".pre_handoff_"+token)!=OK:_send_receipt(token,false);return
			var replacement=Drive.new(int(record.capacity)*1024*1024);replacement.entries=entries
			if Archive.save(game.school.local_identity,record.id,record.name,record.capacity,replacement)!=OK:_send_receipt(token,false);return
	else:
		var drive=Drive.new(int(record.capacity)*1024*1024);drive.entries=entries
		if Archive.save(game.school.local_identity,record.id,record.name,record.capacity,drive)!=OK:_send_receipt(token,false);return
	# Keep a local recovery marker before acknowledging receipt. If the host
	# vanishes during commit, the staged archive remains identifiable locally.
	var profile=game.electronics.profile
	var before: Dictionary=profile.data.duplicate(true)
	if not profile.data.has("usb_received_pending"):profile.data.usb_received_pending={}
	profile.data.usb_received_pending[record.id]={"token":token,"host":str(game.electronics_trade.authority.bound_host)}
	var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
	var saved: Error=profile.save();profile.authority_submit=callback
	if saved!=OK:profile.data=before;_send_receipt(token,false);return
	_send_receipt(token,true)

func _send_receipt(token: String,ok: bool) -> void:
	if multiplayer.is_server():_receipt(multiplayer.get_unique_id(),token,ok)
	else:receipt.rpc_id(1,token,ok)
@rpc("any_peer","call_remote","reliable",6)
func receipt(token: String,ok: bool) -> void:
	if multiplayer.is_server():_receipt(multiplayer.get_remote_sender_id(),token,ok)
func _receipt(peer: int,token: String,ok: bool) -> void:
	var record: Dictionary=pending.get(token,{})
	if record.is_empty() or record.target!=peer or record.phase!="download":return
	if not ok or not game.session.roster.has(record.source) or not world.drops.has(record.drop):_abort(token);return
	record.item_token=str(world.drops[record.drop].get("token",""))
	record.phase="claim"
	var claim: Dictionary=await world.claim_handoff(int(record.drop),token)
	if not pending.has(token) or pending[token].phase!="claim":
		if claim.get("ok",false):
			var orphan_token: String=record.item_token
			if not orphan_token.is_empty():world.ClaimAuthority.release(world,orphan_token,token)
		return
	if not claim.get("ok",false):
		var item_token: String=record.item_token
		_abort(token,not claim.get("claimed",false))
		if claim.get("claimed",false) and world.drops.has(record.drop):
			world.forget_ground(int(world.drops[record.drop].get("owner",0)),item_token)
			world.drops.erase(record.drop)
			world._fill_tables()
			world._publish()
		world._notice(peer,str(claim.get("error","Shared item claim failed.")))
		return
	var result: Dictionary=game.electronics_trade.authority.ledger.commit_usb_handoff(record.source,record.target,record.id,token,record.item_token)
	if not result.get("ok",false):
		_abort(token)
		return
	record.phase="claim_commit"
	record.committed=result
	record.claim_busy=false
	_complete_claim(token)

func _complete_claim(token: String) -> void:
	var record: Dictionary=pending.get(token,{})
	if record.is_empty() or record.phase!="claim_commit" or record.claim_busy:return
	var item_token: String=record.item_token
	if item_token.is_empty():return
	record.claim_busy=true
	var confirmed: Dictionary=await world.ClaimAuthority.commit(world,item_token,token)
	if not pending.has(token) or pending[token].phase!="claim_commit":return
	if not confirmed.get("ok",false):record.claim_busy=false;return
	game.electronics_trade.authority.ledger.clear_lost_found_receipt(item_token,token)
	var result: Dictionary=record.committed
	pending.erase(token)
	if game.session.roster.has(record.source):game.electronics_trade.authority.send_snapshot(record.source,result.source)
	if game.session.roster.has(record.target):game.electronics_trade.authority.send_snapshot(record.target,result.target)
	world.forget_ground(record.source,item_token)
	world.drops.erase(record.drop);world._fill_tables();world._publish()
	if game.session.roster.has(record.target):world._notice(record.target,"USB drive recovered.")

@rpc("any_peer","call_remote","reliable",6)
func abort_request(token: String) -> void:
	if multiplayer.is_server() and pending.has(token) and pending[token].source==multiplayer.get_remote_sender_id():_abort(token)
func _abort(token: String,notify_target := true) -> void:
	var record: Dictionary=pending.get(token,{})
	if record.is_empty():return
	if record.phase=="claim_commit":return
	if record.phase=="claim":
		var item_token: String=record.item_token
		if not item_token.is_empty():world.ClaimAuthority.release(world,item_token,token)
	pending.erase(token)
	var ledger=game.electronics_trade.authority.ledger
	var owner: String=str(ledger.bindings.get(record.source,""))
	if not owner.is_empty():
		var next: Dictionary=ledger.state.duplicate(true)
		var profile: Dictionary=next.accounts[owner].profile
		var item: Dictionary=profile.dorm.get("usb_drives",{}).get(record.id,{})
		if item.get("location","")=="handoff" and profile.get("usb_handoff_pending",{}).get(record.id,"")==token:
			item.location="lost";profile.usb_handoff_pending.erase(record.id);profile.dorm.revision+=1;next.accounts[owner].revision+=1
			if ledger.persist(next) and game.session.roster.has(record.source):game.electronics_trade.authority.send_snapshot(record.source,ledger.snapshot(record.source))
	if game.session.roster.has(record.source):
		if record.source==multiplayer.get_unique_id():_restore_source(token,record.id)
		else:restore_source.rpc_id(record.source,token,record.id)
	if notify_target and game.session.roster.has(record.target):world._notice(record.target,"USB transfer was interrupted; the original remains in lost and found.")
	if game.session.roster.has(record.target):
		if record.target==multiplayer.get_unique_id():_cancel_received(token,record.id)
		else:cancel_received.rpc_id(record.target,token,record.id)
@rpc("authority","call_remote","reliable",6)
func cancel_received(token: String,id: String) -> void:
	if multiplayer.get_remote_sender_id()==1:_cancel_received(token,id)
func _cancel_received(token: String,id: String) -> void:
	var profile=game.electronics.profile
	if profile.data.get("usb_received_pending",{}).get(id,{}).get("token","")!=token:return
	var before: Dictionary=profile.data.duplicate(true)
	profile.data.usb_received_pending.erase(id)
	var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
	if profile.save()!=OK:profile.data=before
	profile.authority_submit=callback
@rpc("authority","call_remote","reliable",6)
func restore_source(token: String,id: String) -> void:
	if multiplayer.get_remote_sender_id()==1:_restore_source(token,id)
func _restore_source(token: String,id: String) -> void:
	var profile=game.electronics.profile
	if profile.data.get("usb_handoff_pending",{}).get(id,"")!=token:return
	var before: Dictionary=profile.data.duplicate(true)
	var item: Dictionary=profile.data.get("dorm",{}).get("usb_drives",{}).get(id,{})
	if item.get("location","")!="handoff":return
	item.location="lost";profile.data.usb_handoff_pending.erase(id)
	var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
	if profile.save()!=OK:profile.data=before
	profile.authority_submit=callback

func _prune() -> void:
	for token in incoming.keys():
		if Time.get_ticks_msec()-int(incoming[token].receiver.last_activity_ms)>Chunks.TIMEOUT_MS:incoming.erase(token)
	if not multiplayer.is_server():return
	for token in pending.keys():
		var record: Dictionary=pending[token]
		if record.phase=="claim_commit":_complete_claim(str(token));continue
		if not game.session.roster.has(record.source) or not game.session.roster.has(record.target) or not world.drops.has(record.drop) or Time.get_ticks_msec()-int(record.started)>Chunks.TIMEOUT_MS:_abort(token)
