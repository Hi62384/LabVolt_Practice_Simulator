extends Node
signal operation_result(operation: String,result: Dictionary)
signal profile_ready(peer: int)
# This adapter is created by the existing trade node, at the same stable RPC path.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
var ledger=Ledger.new()
var game: Node
var host := ""
var bound := false
var inventory_conflict := false
var healthy := false
var clock := 0.0
var pending := []
var world_requests := []
var last_send := {}
var bound_host := ""
var active_store := ""
func build(owner_game: Node,host_id: String) -> void:
	game=owner_game;host=host_id
	game.electronics.profile.craft_reservations=local_craft_reservations
	game.electronics.profile.purchase_hotbar_limit=func():
		game.hotbar._sync_dorm_items()
		var dorm: Dictionary = game.electronics.profile.data.get("dorm",{})
		return mini(6,dorm.get("carry_items",[]).size()+dorm.get("carried_components",[]).size()+game.hotbar.slots.count({}))
	game.session.restarted.connect(reset)
	if game.session.has_signal("leaving"):game.session.connect("leaving",checkpoint_world)
func ensure_host_store() -> bool:
	if not game.session.online or not multiplayer.is_server():return false
	var identity: String=game.characters.selected if game.characters.selected!="" else "__default__"
	var location := "user://inventory_authority_"+identity.sha256_text().left(24)
	if active_store==location:return healthy
	active_store=location;ledger=Ledger.new();healthy=ledger.open(location)==OK
	if not healthy:game.ui.log_message("Host inventory store is corrupt; restore its saved generations before hosting inventory interactions.");return false
	if not ledger.state.has("host"):
		var next: Dictionary=ledger.state.duplicate(true);next.host=Crypto.new().generate_random_bytes(16).hex_encode()
		healthy=ledger.persist(next)
	if healthy:host=str(ledger.state.host);healthy=ledger.reset_world()
	return healthy
func reset() -> void:
	game.electronics.clear_bundle_reveals()
	game.cosmetic_appearances.clear()
	bound=false;inventory_conflict=false;pending.clear();world_requests.clear();last_send.clear();ledger.bindings.clear();bound_host=""
	game.electronics.profile.authority_submit=Callable()
	game.electronics.profile.authority_revision=-1
	if multiplayer.is_server() and healthy:healthy=ledger.reset_world()
func submit(op: String,args: Array,request_id: String = "") -> void:
	var metadata: Dictionary=args[0] if op=="metadata" and args.size()==1 and args[0] is Dictionary else {}
	if not game.session.online:
		if not metadata.is_empty() and game.electronics.has_method("kit_names_submission_failed"):game.electronics.kit_names_submission_failed(metadata,"Inventory session is offline")
		return
	if pending.size()>=64:
		game.ui.log_message("Inventory request queue is full")
		if not metadata.is_empty() and game.electronics.has_method("kit_names_submission_failed"):game.electronics.kit_names_submission_failed(metadata,"Inventory request queue is full")
		return
	if op=="metadata" and args.size()==1 and args[0] is Dictionary:
		args=args.duplicate(true);args[0].erase("authority_credentials")
	var id := request_id if not request_id.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	pending.append({"id":id,"op":op,"args":args.duplicate(true)})
	if not metadata.is_empty() and game.electronics.has_method("kit_names_submitted"):game.electronics.kit_names_submitted(str(pending.back().id),args[0])
	if op in ["buy","buy_configured"] and is_instance_valid(game.electronics.shop_adapter):game.electronics.shop_adapter.submitted(str(pending.back().id),op)
	flush()
func flush() -> void:
	if not bound or pending.is_empty():return
	if multiplayer.is_server():execute(1,pending[0])
	else:request_operation.rpc_id(1,pending[0])
func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	if not game.session.online:
		game.electronics.profile.authority_submit=Callable();return
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
	if multiplayer.is_server():ensure_host_store()
	game.electronics.profile.authority_submit=submit
	if bound and pending.is_empty() and not world_requests.is_empty():
		var request: Dictionary=world_requests.pop_front()
		if request.get("kind")=="kit":
			if multiplayer.is_server():game.kit_world.apply(1,request.action)
			else:game.kit_world.command.rpc_id(1,request.action)
		else:game.dc_lab.request(request.index,request.action)
	clock+=delta
	if clock<1:return
	clock=0
	if multiplayer.is_server():
		ledger.creative=game.school.mode=="Creative Freeplay"
		for peer in ledger.bindings.keys():
			if not game.session.roster.has(peer):
				if game.dc_lab.benches.any(func(station):return station.board_owner==peer):continue
				if not ledger.account(peer).deployment.is_empty() and not ledger.recall(peer):continue
				ledger.unbind(peer)
		if healthy and not ledger.creative:
			for peer in ledger.bindings:
				var identity: String=ledger.bindings[peer]
				for id in game.school.archive.get(identity,{}):
					if ledger.account(peer).profile.reward_ids.has(id):continue
					var record: Dictionary=game.school.archive[identity][id]
					if not (record.get("score") is float or record.get("score") is int):continue
					var result: Dictionary=ledger.award(peer,str(id),float(record.score),int(record.get("difficulty",0)),bool(record.get("lesson",false)))
					send_snapshot(peer,result)
	if not bound and not inventory_conflict:
		if multiplayer.is_server():hello(1)
		elif multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:request_hello.rpc_id(1)
	else:flush()
@rpc("any_peer","call_remote","reliable",6)
func request_hello() -> void:
	if multiplayer.is_server():hello(multiplayer.get_remote_sender_id())
func hello(peer: int) -> void:
	if not ensure_host_store():return
	if not healthy or not game.session.roster.has(peer) or not game.school.identities.has(peer):return
	if peer==1:challenge(host)
	else:challenge.rpc_id(peer,host)
@rpc("authority","call_remote","reliable",6)
func challenge(host_id: String) -> void:
	if host_id.length()>96 or bound:return
	var p=game.electronics.profile
	if not p.data.get("pending_trade",{}).is_empty():return # Legacy journal recovery runs first.
	var credentials: Dictionary=p.data.get("authority_credentials",{}).duplicate(true)
	if not credentials.has(host_id):
		credentials[host_id]=Crypto.new().generate_random_bytes(32).hex_encode()
		p.data.authority_credentials=credentials
		var callback: Callable=p.authority_submit;p.authority_submit=Callable()
		var error: Error=p.save();p.authority_submit=callback
		if error!=OK:game.ui.log_message("Could not save reconnect credential");return
	bound_host=host_id
	var initial: Dictionary=p.data.duplicate(true);initial.erase("authority_credentials")
	if multiplayer.is_server():enroll(1,credentials[host_id],initial)
	else:register_profile.rpc_id(1,credentials[host_id],initial)
@rpc("any_peer","call_remote","reliable",6)
func register_profile(secret: String,initial: Dictionary) -> void:
	if multiplayer.is_server():enroll(multiplayer.get_remote_sender_id(),secret,initial)
func enroll(peer: int,secret: String,initial: Dictionary) -> void:
	if not healthy or not game.session.roster.has(peer) or not game.school.identities.has(peer):return
	var already_bound: bool=ledger.bindings.has(peer)
	var result: Dictionary=ledger.bind(peer,str(game.school.identities[peer]),secret,initial)
	send_snapshot(peer,result)
	if result.get("ok",false):
		if not already_bound:game.dc_lab.restore_carried_pcbs(peer)
		profile_ready.emit(peer)
@rpc("any_peer","call_remote","reliable",6)
func request_operation(action: Dictionary) -> void:
	if multiplayer.is_server():execute(multiplayer.get_remote_sender_id(),action)
func execute(peer: int,action: Dictionary) -> void:
	if not healthy or not game.session.roster.has(peer) or var_to_bytes(action).size()>1048576:return
	var id := str(action.get("id",""))
	var now := Time.get_ticks_msec()
	if now-int(last_send.get(peer,-100))<20:return
	last_send[peer]=now
	var result: Dictionary
	if not action.get("args") is Array:result=ledger.failure("Invalid operation arguments")
	else:
		ledger.creative = game.school.mode == "Creative Freeplay"
		var live_boards := {}
		if action.get("op") == "ic_upgrade":
			for slot in game.dc_lab.benches.size():
				if game.dc_lab.benches[slot].board_owner==peer:live_boards[slot]=game.dc_lab.benches[slot].board
		var position: Vector3 = game.player.global_position if peer == 1 else game.session.poses.get(peer, {}).get("position", Vector3.ZERO)
		if action.get("op") == "sell_component" and not game.shop_room.near_component_counter(position):
			result = ledger.failure("Visit the Component Counter to sell")
		elif action.get("op") == "remove_kit_board_components" and not game.shop_room.near_kit_builder(position):
			result = ledger.failure("Visit the Components Counter to remove breadboard components.")
		elif action.get("op") == "dorm" and action.args.size() == 1 and action.args[0] is Dictionary and game.kit_world.blocks_dorm_transfer(peer, action.args[0]):
			result = ledger.failure("Pick up and stow the kit before transferring it")
		else:
			result=ledger.transact(peer,id,str(action.get("op","")),action.args,{},live_boards)
		for slot in result.get("upgraded_boards",{}):
			game.dc_lab.upgrade_deployed_circuit(slot,result.upgraded_boards[slot])
		result.erase("upgraded_boards")
	result.request_id=id
	send_snapshot(peer,result)
func send_snapshot(peer: int,result: Dictionary) -> void:
	if peer==1:receive_snapshot(result)
	elif game.session.roster.has(peer):receive_snapshot.rpc_id(peer,result)
	if result.get("ok",false):_publish_cosmetic_appearances()

func _publish_cosmetic_appearances() -> void:
	if not multiplayer.is_server():return
	var cosmetics = preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not cosmetics.load_catalog():return
	var packet := {}
	for peer in ledger.bindings:
		if not game.session.roster.has(peer):continue
		var profile: Dictionary=ledger.account(peer).get("profile",{})
		if not profile.get("avatar_cosmetics") is Dictionary:continue
		var resolved: Dictionary=preload("res://scripts/avatar_cosmetics/core/avatar_core.gd").resolve(cosmetics.catalog,profile.avatar_cosmetics,profile.get("owned_cosmetics",[]))
		if resolved.errors.is_empty():packet[str(peer)]=resolved.state
	_receive_cosmetic_appearances(packet)
	for peer in game.session.connected_peers():_receive_cosmetic_appearances.rpc_id(int(peer),packet)

@rpc("authority","call_remote","reliable",6)
func _receive_cosmetic_appearances(packet: Dictionary) -> void:
	if var_to_bytes(packet).size()>65536 or packet.size()>8:return
	var cosmetics = preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
	if not cosmetics.load_catalog():return
	var next := {}
	for key in packet:
		var peer := int(str(key))
		if not game.session.roster.has(peer) or not packet[key] is Dictionary:continue
		var resolved: Dictionary=preload("res://scripts/avatar_cosmetics/core/avatar_core.gd").resolve(cosmetics.catalog,packet[key],cosmetics.catalog.keys())
		if resolved.errors.is_empty():next[peer]=resolved.state
	var previous: Dictionary=game.cosmetic_appearances
	game.cosmetic_appearances=next
	for peer in game.avatars:
		if previous.get(peer,{})!=next.get(peer,{}):game._set_avatar_model(int(peer),game.avatars[peer])
@rpc("authority","call_remote","reliable",6)
func receive_snapshot(result: Dictionary) -> void:
	var id := str(result.get("request_id",""))
	var previous_profile: Dictionary=game.electronics.profile.data
	if result.get("ok",false):
		var error: Error = game.electronics.profile.accept_authority(result)
		if error == ERR_BUSY:
			inventory_conflict = true
			game.ui.log_message("Inventory mismatch with host. Your saved inventory was kept; inventory actions are paused.")
			return
		if error != OK:return # Keep retrying on local save failure.
		game.electronics.profile.set_meta("economy_display",result.get("economy",{}).duplicate(true))
		if game.electronics.profile.reconciliation_backup!="":
			game.ui.log_message("Host inventory restored. Previous local progress retained at "+game.electronics.profile.reconciliation_backup)
			game.electronics.profile.reconciliation_backup=""
		bound=true
	elif not result.get("error","").is_empty():game.ui.log_message(str(result.error))
	if game.electronics.has_method("kit_names_result"):game.electronics.kit_names_result(id,bool(result.get("ok",false)),result.get("profile",{}) if result.get("profile",{}) is Dictionary else {},str(result.get("error","Host rejected metadata")))
	var operation := ""
	if not pending.is_empty() and pending[0].id==id:
		operation=str(pending[0].get("op",""))
		if str(pending[0].get("op","")) in ["buy","buy_configured"] and is_instance_valid(game.electronics.shop_adapter):game.electronics.shop_adapter.received(id,result)
		operation_result.emit(str(pending[0].get("op","")),result)
		pending.pop_front()
	if result.get("message","")!="":game.ui.log_message(str(result.message))
	if result.get("ok",false) and game.front.in_game and operation in ["avatar_cosmetic","cosmetic_purchase"]:
		var profile: RefCounted = game.electronics.profile
		if previous_profile.get("avatar_cosmetics",{}) != profile.data.get("avatar_cosmetics",{}):
			game.characters.notify_appearance_saved(profile)
	if game.electronics.active and result.get("ok",false):
		var editor = game.electronics
		if editor.current_page=="design" and is_instance_valid(editor.workspace) and editor.workspace.is_inside_tree():
			var profile: Dictionary=editor.profile.data
			if previous_profile.get("blueprints",{})!=profile.get("blueprints",{}):
				editor.workspace.get_meta("host_adapter").refresh_maker_catalog()
		else:editor.open(editor.current_page,editor.bench)
	if operation in ["bundle", "box"] and result.get("ok", false):
		game.electronics.show_bundle_receipt(result.get("bundle_receipt", {}))
	if operation=="sell_component" and game.electronics.active and game.electronics.current_page=="counter":
		game.electronics.status.text=str(result.get("message",result.get("error","Sale unavailable")))
		game.electronics.status.show()
	if operation=="remove_kit_board_components" and game.electronics.active and game.electronics.current_page=="kits":
		game.electronics.status.text=str(result.get("message",result.get("error","")))
func request_world(index: int,action: Dictionary) -> void:
	if not game.session.online:game.dc_lab.request(index,action);return
	if world_requests.size()<16:world_requests.append({"index":index,"action":action.duplicate(true)})
func request_kit(action: Dictionary) -> void:
	if world_requests.size()<16:world_requests.append({"kind":"kit","action":action.duplicate(true)})
func deployment(peer: int,slot: int,design: Dictionary) -> String:
	ledger.creative=game.school.mode=="Creative Freeplay"
	if not healthy:return "Host inventory store is unavailable"
	return ledger.deploy(peer,slot,design)

func checkout_pcb(peer: int, slot: int, id: String, preferred_instance := "") -> Dictionary:
	if game.session.online and not healthy:
		return {"ok":false,"error":"Host inventory store is unavailable"}
	var profile: Dictionary = ledger.account(peer).get("profile", {}) if game.session.online else game.electronics.profile.data
	var dorm := preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
	var reserved := int(dorm.stock_used(profile,ledger.account(peer).get("deployment",{}) if game.session.online else {}).get(id,0))
	var unavailable: Array = dorm.packed_instance_ids(profile,"")
	for index in game.dc_lab.benches.size():
		var station = game.dc_lab.benches[index]
		if index == slot or station.board_owner != peer:continue
		unavailable.append_array(station.board.get("instance_ids",{}).values())
		if not game.session.online:
			for part in station.board.get("parts",[]):
				if str(part.type) == id:reserved += 1
	if int(profile.get("inventory", {}).get(id, 0)) <= reserved:
		return {"ok":false,"error":"No available copy of this PCB"}
	var design := preload("res://scripts/breadboard_model.gd").standalone(id, profile.get("blueprints", {}))
	if design.is_empty(): return {"ok":false,"error":"PCB blueprint is unavailable"}
	if not preferred_instance.is_empty():design.instance_ids={str(design.parts[0].id):preferred_instance}
	design = preload("res://scripts/inventory_authority/component_persistence.gd").materialize(profile, design, unavailable)
	design.authority_kit_id = ""
	if game.session.online:
		var error: String = ledger.deploy(peer, slot, design, true)
		if not error.is_empty(): return {"ok":false,"error":error}
	return {"ok":true,"design":design}

func save_carried_pcbs(peer: int, items: Array) -> bool:
	if game.session.online:
		var account: Dictionary=ledger.account(peer)
		if not healthy or account.is_empty():return false
		if account.profile.get("carried_pcbs",[])==items:return true
		var next: Dictionary=ledger.state.duplicate(true)
		var updated: Dictionary=next.accounts[ledger.bindings[peer]]
		updated.profile.carried_pcbs=items
		updated.revision+=1
		if not ledger.persist(next):return false
		if game.session.roster.has(peer):send_snapshot(peer,ledger.snapshot(peer))
		return true
	var profile: RefCounted=game.electronics.profile
	if profile.data.get("carried_pcbs",[])==items:return true
	var previous: Dictionary=profile.data
	profile.data=previous.duplicate()
	profile.data.carried_pcbs=items
	if profile.save()==OK:return true
	profile.data=previous
	return false
func recall(peer: int,slot: int = -1) -> bool:return healthy and ledger.recall(peer,slot)

func transfer_cabinet_board(peer: int, slot: int, design: Dictionary) -> Dictionary:
	if game.session.online:
		if not healthy:return {"ok":false,"error":"Host inventory store is unavailable"}
		var result := ledger.transfer_cabinet_board(peer,slot,design)
		if result.ok:send_snapshot(peer,ledger.snapshot(peer))
		return result
	var profile = game.electronics.profile
	var counts := {}
	if game.school.mode!="Creative Freeplay" or design.get("authority_kit_id","existing_kit")=="":
		for part in design.get("parts",[]):counts[part.type]=int(counts.get(part.type,0))+1
	var result: Dictionary = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd").move_board(profile.data,design,counts)
	if not result.ok:return result
	var previous: Dictionary = profile.data
	profile.data=result.profile
	if profile.save()!=OK:
		profile.data=previous
		return {"ok":false,"error":"Cabinet save failed"}
	return {"ok":true,"design":result.board.get("design",{})}

func materialize(peer: int,design: Dictionary,slot: int = -1) -> Dictionary:
	if not preload("res://scripts/inventory_authority/validation.gd").board(design):return {}
	if game.session.online:
		ledger.creative=game.school.mode=="Creative Freeplay"
		return ledger.materialize(peer,design,slot)
	var p=game.electronics.profile
	var before: Dictionary=p.data.duplicate(true)
	var dorm := preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
	var unavailable: Array=dorm.packed_instance_ids(p.data,str(design.get("authority_kit_id",p.data.equipped)))
	unavailable.append_array(p.data.get("dorm",{}).get("instances",[]))
	for index in game.dc_lab.benches.size():
		var station=game.dc_lab.benches[index]
		if index!=slot and station.board_owner==peer:unavailable.append_array(station.board.get("instance_ids",{}).values())
	if game.school.mode!="Creative Freeplay" and preload("res://scripts/physical_resistors.gd").ensure(p.data,design,unavailable):
		if p.save()!=OK:p.data=before;return {}
	var result: Dictionary=preload("res://scripts/inventory_authority/component_persistence.gd").materialize(p.data,design,unavailable)
	result.authority_kit_id=str(design.get("authority_kit_id",p.data.equipped))
	if game.school.mode=="Creative Freeplay":
		result.component_runtime=p.data.kits[p.data.equipped].board.get("component_runtime",{}).duplicate(true);result.instance_ids={}
	return result
func capture_components(peer: int,board: Dictionary,states: Dictionary,slot: int = -1) -> String:
	if not game.session.online:return capture_local(board,states)
	if not healthy:return "Host inventory store is unavailable"
	ledger.creative=game.school.mode=="Creative Freeplay"
	var revision_before: int=ledger.account(peer).get("revision",-1)
	var error: String=ledger.capture_components(peer,board,states,slot)
	if error=="" and int(ledger.account(peer).get("revision",-1))!=revision_before:send_snapshot(peer,ledger.snapshot(peer))
	return error

func checkpoint_world() -> void:
	var transport=multiplayer.multiplayer_peer
	if transport!=null and transport.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:return
	if not multiplayer.is_server() or not game.dc_lab.has_method("checkpoint_inventory"):return
	var error: String=game.dc_lab.checkpoint_inventory()
	if error!="":game.ui.log_message(error)
	if game.front.in_game:game.dc_lab.checkpoint_carried_pcbs()
func capture_local(board: Dictionary,states: Dictionary) -> String:
	var Persistent=preload("res://scripts/inventory_authority/component_persistence.gd")
	var p=game.electronics.profile;var before: Dictionary=p.data.duplicate(true);var copy := board.duplicate(true)
	if game.school.mode=="Creative Freeplay" and board.get("authority_kit_id", "existing_kit") != "":
		copy.component_runtime=Persistent.capture(states);copy.instance_ids={}
		if not Persistent.valid(copy.component_runtime):return "Nonvolatile component state exceeds persistence limits"
	else:
		var error: String=Persistent.retain(p.data,copy,states)
		if error!="":p.data=before;return error
	var saved := copy.duplicate(true)
	if game.school.mode!="Creative Freeplay":saved.component_runtime={}
	var kit := str(board.get("authority_kit_id",""))
	if p.data.kits.has(kit):
		p.data.kits[kit].board=saved
	if not preload("res://scripts/electronics_profile.gd").same(before,p.data) and p.save()!=OK:p.data=before;return "Local component save failed"
	board.instance_ids=copy.instance_ids;board.component_runtime=copy.component_runtime
	return ""

# Offline crafting reads the current world at the gesture, not a frame-old cache.
# Online requests use the ledger account's host-owned deployment instead.
func local_craft_reservations() -> Dictionary:
	var result := {"counts":{},"instance_ids":[]}
	if game.session.online or not is_instance_valid(game.dc_lab):return result
	for station in game.dc_lab.benches:
		if station.board_owner!=1 or station.board.is_empty():continue
		for part in station.board.get("parts",[]):result.counts[part.type]=int(result.counts.get(part.type,0))+1
		for instance in station.board.get("instance_ids",{}).values():
			if instance not in result.instance_ids:result.instance_ids.append(instance)
	var dorm: Dictionary=game.electronics.profile.data.get("dorm",{})
	for type in dorm.get("storage",{}):result.counts[type]=int(result.counts.get(type,0))+int(dorm.storage[type])
	result.instance_ids.append_array(dorm.get("instances",[]))
	return result

func submit_dorm(operation_id: String,intent: Dictionary) -> void:
	if not game.session.online or operation_id.is_empty() or operation_id.length()>96 or pending.size()>=64:return
	var action := {"id":operation_id,"op":"dorm","args":[intent.duplicate(true)]}
	for waiting in pending:
		if waiting.id==operation_id:return
	pending.append(action);flush()
func local_storage_error(design: Dictionary,slot: int = -1) -> String:
	if game.school.mode=="Creative Freeplay":return ""
	var profile: Dictionary=game.electronics.profile.data
	var stored: Dictionary=profile.get("dorm",{}).get("storage",{}).duplicate()
	for index in game.dc_lab.benches.size():
		var station=game.dc_lab.benches[index]
		if index==slot or station.board_owner!=1:continue
		for part in station.board.get("parts",[]):stored[part.type]=int(stored.get(part.type,0))+1
	var counts := {}
	for part in design.get("parts",[]):counts[part.type]=int(counts.get(part.type,0))+1
	for type in counts:
		if int(counts[type])+int(stored.get(type,0))>int(profile.inventory.get(type,0)):return "Retrieve stored components before deploying"
	for id in design.get("instance_ids",{}).values():
		if id in profile.get("dorm",{}).get("instances",[]):return "Retrieve stored instance before deploying"
	return ""
