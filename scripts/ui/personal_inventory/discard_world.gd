extends Node3D

const Transfer = preload("res://scripts/ui/personal_inventory/discard_transfer.gd")
const Lifetime := 120000
const WARNING_MS := 15000
const PERSONAL_LIMIT := 12
const CABLE_KINDS := ["wire", "dc_wire", "ac_usb", "charging_cable"]
const PERSONAL_ITEM_KINDS := ["supply", "component", "kit", "bag", "laptop"]
const Store = preload("res://scripts/inventory_authority/store.gd")
const PcbPreview = preload("res://scripts/campus/lost_found/pcb_preview.gd")
const ClaimAuthority = preload("res://scripts/campus/lost_found/claim_authority.gd")
var local_store = Store.new()
var store_identity := ""
var session_loaded := false
var import_retrying := false
var import_retry_epoch := 0
var forget_retrying := {}
var imported_peers := {}
var import_waiting := {}
var request_clock := 0.0
var pending_import := {}
var host_pending_import := {}
var import_clock := 0.0
var import_cursor := 0
var queued_entries := {}
var checking_imports := {}
var game: Node
var drops := {}
var claim_pending := {}
var claimed_tokens := {}
var pending_commits := {}
var recovering_claim := false
var claim_recovery_cursor := 0
var commit_clock := 0.0
var views := {}
var next_id := 1
var clock_offset := 0
var usb_handoffs: Node

func build(owner_game: Node) -> void:
	game=owner_game
	usb_handoffs=preload("res://scripts/campus/computers/usb_handoff.gd").new()
	usb_handoffs.name="UsbHandoffs";add_child(usb_handoffs);usb_handoffs.build(self)
	game.session.restarted.connect(func():drops.clear();claim_pending.clear();claimed_tokens.clear();pending_commits.clear();imported_peers.clear();import_waiting.clear();pending_import.clear();host_pending_import.clear();import_cursor=0;queued_entries.clear();checking_imports.clear();session_loaded=false;import_retrying=false;import_retry_epoch+=1;forget_retrying.clear();_publish())
	game.session.roster_changed.connect(_roster_changed)
	game.session.leaving.connect(_leaving)
	game.electronics_trade.authority.profile_ready.connect(_profile_ready)

func discard(source: Dictionary) -> void:
	var point: Vector3 = game.player.global_position-game.player.global_basis.z
	if multiplayer.is_server():_discard(multiplayer.get_unique_id(),source,point)
	else:request_drop.rpc_id(1,source,point)

@rpc("any_peer","call_remote","reliable")
func request_drop(source: Dictionary,point: Vector3) -> void:
	if multiplayer.is_server():_discard(multiplayer.get_remote_sender_id(),source,point)

func _discard(peer: int,source: Dictionary,point: Vector3,allow_held_kit := false) -> void:
	if not game.session.roster.has(peer) or var_to_bytes(source).size()>1024 or not source.get("item") is Dictionary:return
	var item: Dictionary = source.item
	var cable: bool = item.get("kind") in ["wire","dc_wire"]
	if not cable and not can_track_personal(peer):return
	if drops.size()>=96:_notice(peer,"Too many discarded items are on the ground.");return
	var floor_point: Variant = _drop_position(peer,point)
	if floor_point==null:_notice(peer,"Face a clear spot on the floor to discard the item.");return
	var dorm = game.dorm_interactions
	var identity: String = dorm.authenticated_identity(peer)
	var profile: Dictionary = dorm._profile(identity)
	if not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():
		_notice(peer,"Inventory is unavailable.");return
	if item.get("kind")=="usb":
		_discard_usb(peer,identity,profile,source,floor_point)
		return
	var carry_key:=str(item.get("id","")) if item.get("kind")=="supply" else "%s:%s"%[item.get("kind",""),item.get("id","")]
	if game.personal_placement.is_placed(peer,carry_key) or (item.get("kind")=="laptop" and game.portable_laptops.placed.has(item.get("id",""))):
		_notice(peer,"Pick up the item before discarding it.")
		return
	var parcel: Dictionary
	var label: String
	if item.get("kind")=="paper":
		var paper_id := int(item.get("id",0))
		var paper: Dictionary = game.school.papers.get(paper_id,{})
		if int(paper.get("owner",0))!=peer or not (paper.get("held",false) or paper.get("stowed",false)) or not Transfer.Dorm.paper_supply(paper).is_empty():
			_notice(peer,"This document is no longer in your hotbar.");return
		if game.school._class_assessment(paper):_notice(peer,"Class assessments cannot be discarded.");return
		parcel={"item":item,"paper":paper}
		label="Worksheet"
		game.school.papers.erase(paper_id)
		game.school.broadcast()
	elif item.get("kind") in ["wire","dc_wire"]:
		parcel=_take_wire(peer,item)
		if parcel.is_empty():_notice(peer,"Disconnect the cable before discarding it.");return
		label=["Red cable","Blue cable","Yellow cable","Black cable"][int(parcel.color)]
	elif item.get("kind")=="food":
		var result := _move_food(peer,str(item.get("id","")))
		if not result.ok:_notice(peer,str(result.error));return
		parcel={"food":result.order}
		label=str(game.campus_services.facilities.controller.host.menu[result.order.item].name)
	elif item.get("kind")=="board":
		var result := _take_pcb(peer,int(item.get("id",-1)),identity)
		if not result.ok:_notice(peer,str(result.error));return
		parcel=result.parcel
		label=_title(parcel,profile)
	else:
		var deployment: Dictionary = dorm._ledger().account(peer).get("deployment",{}) if game.session.online else {}
		var result := Transfer.take(profile,source,deployment)
		if not result.ok:_notice(peer,str(result.error));return
		parcel=result.parcel
		var kit: Dictionary = game.kit_world.kits.get(peer,{})
		for id in parcel.kits:
			if game.kit_world.is_placed(peer,id):_notice(peer,"Pick up the kit before discarding it.");return
		if not kit.is_empty() and not kit.get("stowed",false) and parcel.kits.has(kit.get("id","")) and not (allow_held_kit and kit.get("held",false) and not kit.get("open",false)):
			_notice(peer,"Stow the kit and return its breadboard first.");return
		for station in game.dc_lab.benches:
			if station.board_owner==peer and parcel.kits.has(station.board.get("authority_kit_id","")):
				_notice(peer,"Return the breadboard to its kit first.");return
		if var_to_bytes(parcel).size()>1048576:_notice(peer,"This item is too large to discard.");return
		var saved: Dictionary = dorm._commit_world_inventory(peer,identity,result.profile)
		if not saved.ok:_notice(peer,str(saved.error));return
		label=_title(parcel,profile)
		if parcel.kits.has(kit.get("id","")):
			game.kit_world.kits.erase(peer)
			game.kit_world.sync()
		if source.location in ["hotbar","back"] and item.get("kind") in ["supply","bag"]:
			var supply := str(item.id) if item.kind=="supply" else "bag:"+str(item.id)
			for id in game.school.papers.keys():
				var paper: Dictionary = game.school.papers[id]
				if paper.owner==peer and Transfer.Dorm.paper_supply(paper)==supply and not paper.get("supply_released",false):game.school.papers.erase(id)
			game.school.broadcast()
	var token := "" if cable else track_ground(peer,parcel,label)
	drops[next_id]={"position":floor_point,"expires":Time.get_ticks_msec()+Lifetime,"label":label,"parcel":parcel,"owner":peer,"token":token}
	next_id+=1
	_publish()
	_notice(peer,"Discarded "+label+".",true)

func _discard_usb(peer: int,identity: String,profile: Dictionary,source: Dictionary,point: Vector3) -> void:
	var id:=str(source.item.get("id",""))
	var next:=profile.duplicate(true)
	var dorm: Dictionary=next.dorm
	var drive: Dictionary=dorm.get("usb_drives",{}).get(id,{})
	var key:="usb:"+id
	if source.get("location")!="hotbar" or drive.get("location")!="hotbar" or key not in dorm.get("carry_items",[]) or game.personal_placement.is_placed(peer,key):
		_notice(peer,"The USB drive must be in your hotbar.")
		return
	dorm.carry_items.erase(key)
	drive.location="lost"
	dorm.revision+=1
	var saved: Dictionary=game.dorm_interactions._commit_world_inventory(peer,identity,next)
	if not saved.ok:
		_notice(peer,str(saved.error))
		return
	var label: String=drive.name
	var parcel: Dictionary={"usb":{"id":id,"owner":identity,"name":label,"capacity_mb":int(drive.capacity_mb)}}
	if peer==multiplayer.get_unique_id():cache_ground(id,parcel,label)
	else:cache_ground.rpc_id(peer,id,parcel,label)
	drops[next_id]={"position":point,"expires":Time.get_ticks_msec()+Lifetime,"label":label,"parcel":parcel,"owner":peer,"token":id}
	next_id+=1
	_publish()
	_notice(peer,"Discarded "+label+".",true)

func _drop_position(peer: int,point: Vector3) -> Variant:
	var feet: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	for candidate in [point,feet+Vector3(.4,0,0),feet+Vector3(-.4,0,0),feet+Vector3(0,0,.4),feet+Vector3(0,0,-.4)]:
		var floor_point: Variant=game.school.ground_drop_position(candidate,peer)
		if floor_point==null:continue
		if drops.values().any(func(drop):return drop.position.distance_squared_to(floor_point)<.0625):continue
		return floor_point
	return null

func interact(target: Node) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","")!="discarded_item":return false
	var id := int(target.get_meta("discard_id"))
	game.hotbar._sync_dorm_items()
	var slots: int = game.hotbar.slots.count({})
	if multiplayer.is_server():_pickup(multiplayer.get_unique_id(),id,slots)
	else:request_pickup.rpc_id(1,id,slots)
	return true

@rpc("any_peer","call_remote","reliable")
func request_pickup(id: int,slots: int) -> void:
	if multiplayer.is_server():_pickup(multiplayer.get_remote_sender_id(),id,slots)

func _pickup(peer: int,id: int,slots: int) -> void:
	if not game.session.roster.has(peer) or not drops.has(id):return
	var drop: Dictionary = drops[id]
	if (int(drop.expires)>0 and Time.get_ticks_msec()>=int(drop.expires)) or not game.school._near(peer,drop.position):return
	var parcel: Dictionary = drop.parcel
	var token:=str(drop.get("token",""))
	if parcel.has("usb") and peer!=int(drop.get("owner",0)):
		usb_handoffs.start(peer,id,slots)
		return
	var holder: String=""
	if game.session.online and not parcel.has("wire"):
		if token.is_empty() or claim_pending.has(token) or claimed_tokens.has(token):return
		claim_pending[token]=true
		holder=Crypto.new().generate_random_bytes(16).hex_encode()
		var epoch:=import_retry_epoch
		var reservation: Dictionary=await ClaimAuthority.reserve(self,token,holder)
		if epoch!=import_retry_epoch:
			if reservation.get("ok",false):ClaimAuthority.release(self,token,holder)
			return
		if not reservation.get("ok",false):
			claim_pending.erase(token)
			_notice(peer,str(reservation.get("error","Item pickup is unavailable.")))
			if reservation.get("claimed",false) and drops.get(id,{}).get("token","")==token:
				forget_ground(int(drop.get("owner",0)),token)
				drops.erase(id)
				_fill_tables()
				_publish()
			return
		if not drops.has(id) or str(drops[id].get("token",""))!=token:
			ClaimAuthority.release(self,token,holder)
			claim_pending.erase(token)
			return
		# Paper awards live only in this session. Leave the receipt
		# unawarded on disk so a fresh host can release an unconfirmed pickup.
		if not _begin_claim_receipt(token,holder):
			ClaimAuthority.release(self,token,holder)
			claim_pending.erase(token)
			_notice(peer,"Could not save the lost-and-found claim.")
			return
		var prepared: Dictionary=await ClaimAuthority.prepare(self,token,holder)
		if epoch!=import_retry_epoch or not prepared.get("ok",false) or not game.session.roster.has(peer) or drops.get(id,{}).get("token","")!=token or not game.school._near(peer,drop.position):
			# Delivery has not started, so releasing is safe even after a lost response.
			ClaimAuthority.release(self,token,holder)
			if epoch==import_retry_epoch:
				claim_pending.erase(token)
				if not prepared.get("ok",false):_notice(peer,str(prepared.get("error","Could not prepare the claim.")))
			return
	if not _deliver_drop(peer,slots,drop,token if not holder.is_empty() else "",holder):
		if not holder.is_empty():
			ClaimAuthority.release(self,token,holder)
			claim_pending.erase(token)
		return
	if not holder.is_empty():
		claimed_tokens[token]=id
		pending_commits[token]={"id":id,"holder":holder,"owner":int(drop.get("owner",0)),"busy":true}
		var committed: Dictionary=await ClaimAuthority.commit(self,token,holder)
		if pending_commits.get(token,{}).get("holder","")!=holder:return
		claim_pending.erase(token)
		if not committed.get("ok",false):
			if pending_commits.has(token):pending_commits[token].busy=false
			_notice(peer,"Item delivery needs claim confirmation; please wait.")
			return
		game.electronics_trade.authority.ledger.clear_lost_found_receipt(token,holder)
	_finalized_claim(token,id,int(drop.get("owner",0)))

func _finalized_claim(token: String,id: int,owner: int) -> void:
	pending_commits.erase(token)
	forget_ground(owner,token)
	drops.erase(id)
	claimed_tokens.erase(token)
	_fill_tables()
	_publish()

func _retry_commit(token: String) -> void:
	if not pending_commits.has(token) or pending_commits[token].busy:return
	var record: Dictionary=pending_commits[token]
	record.busy=true
	var result: Dictionary=await ClaimAuthority.commit(self,token,str(record.holder))
	if pending_commits.get(token,{}).get("holder","")!=record.holder:return
	if result.get("ok",false):
		game.electronics_trade.authority.ledger.clear_lost_found_receipt(token,str(record.holder))
		_finalized_claim(token,int(record.id),int(record.owner))
	else:record.busy=false

func _recover_claim_receipt() -> void:
	if recovering_claim or not game.session.online:return
	var ledger: RefCounted=game.electronics_trade.authority.ledger
	var receipts: Dictionary=ledger.state.get("lost_found_claims",{})
	var tokens := receipts.keys()
	for i in tokens.size():
		claim_recovery_cursor %= tokens.size()
		var token: String=tokens[claim_recovery_cursor]
		claim_recovery_cursor+=1
		if pending_commits.has(token) or claim_pending.has(token):continue
		var receipt: Dictionary=receipts[token]
		var holder: String=receipt.holder
		recovering_claim=true
		var result: Dictionary
		if receipt.awarded:
			result=await ClaimAuthority.commit(self,token,holder)
		else:
			result=await ClaimAuthority.release(self,token,holder)
		if result.get("ok",false) or (not receipt.awarded and (result.get("missing",false) or result.get("claimed",false))):
			ledger.clear_lost_found_receipt(token,holder)
		recovering_claim=false
		return

func _begin_claim_receipt(token: String,holder: String) -> bool:
	return game.electronics_trade.authority.ledger.begin_lost_found_receipt(token,holder)

func _deliver_drop(peer: int,slots: int,drop: Dictionary,claim_token := "",claim_holder := "") -> bool:
	var parcel: Dictionary=drop.parcel
	if parcel.has("usb"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return false
		var identity: String=game.dorm_interactions.authenticated_identity(peer)
		var profile: Dictionary=game.dorm_interactions._profile(identity).duplicate(true)
		var usb: Dictionary=parcel.usb
		var d: Dictionary=profile.get("dorm",{})
		var item: Dictionary=d.get("usb_drives",{}).get(str(usb.id),{})
		if identity!=usb.owner or item.get("location","")!="lost" or int(item.get("capacity_mb",0))!=int(usb.capacity_mb):_notice(peer,"USB ownership could not be verified.");return false
		if d.get("carry_items",[]).size()+d.get("carried_components",[]).size()>=6:_notice(peer,"Free a hotbar slot first.");return false
		d.carry_items=d.get("carry_items",[])+["usb:"+str(usb.id)];item.location="hotbar";d.revision+=1
		var saved: Dictionary=game.dorm_interactions._commit_world_inventory(peer,identity,profile,null,claim_token,claim_holder)
		if not saved.ok:_notice(peer,str(saved.error));return false
	elif parcel.has("paper"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return false
		if not game.dc_lab._can_hold_lead(peer):_notice(peer,"Put down the item you are holding first.");return false
		var paper: Dictionary = parcel.paper
		paper=paper.duplicate(true)
		paper.id=game.school.next_id
		game.school.next_id+=1
		paper.owner=peer
		paper.held=true
		paper.stowed=false
		game.school.papers[paper.id]=paper
		game.school.broadcast()
	elif parcel.has("wire"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return false
		if not _give_wire(peer,parcel):_notice(peer,"This cable cannot fit in your hotbar.");return false
	elif parcel.has("food"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return false
		var result := _move_food(peer,"",parcel.food,claim_token,claim_holder)
		if not result.ok:_notice(peer,str(result.error));return false
	elif parcel.has("pcb"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return false
		var result := _give_pcb(peer,parcel,claim_token,claim_holder)
		if not result.ok:_notice(peer,str(result.error));return false
	else:
		var dorm = game.dorm_interactions
		var identity: String = dorm.authenticated_identity(peer)
		var profile: Dictionary = dorm._profile(identity)
		if not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():
			_notice(peer,"Inventory is unavailable.");return false
		var d: Dictionary = profile.dorm
		var limit := mini(6,d.get("carry_items",[]).size()+d.get("carried_components",[]).size()+clampi(slots,0,6))
		var result := Transfer.give(profile,parcel,limit)
		if not result.ok:_notice(peer,str(result.error));return false
		var saved: Dictionary = dorm._commit_world_inventory(peer,identity,result.profile,null,claim_token,claim_holder)
		if not saved.ok:_notice(peer,str(saved.error));return false
	return true

func claim_handoff(drop_id: int,holder: String) -> Dictionary:
	var drop: Dictionary=drops.get(drop_id,{})
	var token:=str(drop.get("token",""))
	if token.is_empty() or claim_pending.has(token):return {"ok":false,"error":"Item claim is already in progress."}
	if claimed_tokens.has(token):return {"ok":false,"error":"Item pickup is already in progress."}
	claim_pending[token]=true
	var epoch:=import_retry_epoch
	var result: Dictionary=await ClaimAuthority.reserve(self,token,holder)
	if result.get("ok",false) and epoch==import_retry_epoch and drops.get(drop_id,{}).get("token","")==token:
		if _begin_claim_receipt(token,holder):
			result=await ClaimAuthority.prepare(self,token,holder)
		else:
			ClaimAuthority.release(self,token,holder)
			result={"ok":false,"error":"Could not save the lost-and-found claim."}
	if epoch==import_retry_epoch:claim_pending.erase(token)
	if epoch!=import_retry_epoch:
		ClaimAuthority.release(self,token,holder)
		return {"ok":false,"error":"Game session changed."}
	if drops.get(drop_id,{}).get("token","")!=token:
		ClaimAuthority.release(self,token,holder)
		return {"ok":false,"error":"The item is no longer available."}
	return result

func _take_wire(peer: int,item: Dictionary) -> Dictionary:
	var index := int(item.get("station",-1))
	var color := int(item.get("color",-1))
	if color not in range(4):return {}
	var dc: bool = item.kind=="dc_wire"
	if dc:
		var lab = game.dc_lab
		var key := Vector2i(index,color)
		var stowed: Dictionary = lab.stowed_leads.get(peer,{})
		if stowed.erase(key):
			lab.publish_stowed_leads(peer)
		else:
			if lab.carried_leads.get(peer,-1)!=color or lab.carried_lead_stations.get(peer,-1)!=index or lab.pending_endpoints.has(peer):return {}
			lab.carried_leads.erase(peer)
			lab.carried_lead_stations.erase(peer)
			lab._reply_hotbar_lead(peer,true)
	else:
		if index not in range(game.session.labs.size()):return {}
		var lab = game.session.labs[index]
		var stowed: Array = lab.stored_cables.get(peer,[])
		if color in stowed:stowed.erase(color)
		else:
			var cable: Dictionary=lab.holding(peer)
			if cable.is_empty() or cable.color!=color or cable.a!="" or cable.b!="":return {}
			lab.cables.erase(cable)
		lab.revision+=1
		game.session.broadcast()
	return {"wire":true,"dc":dc,"station":index,"color":color}

func _give_wire(peer: int,parcel: Dictionary) -> bool:
	var index := int(parcel.station)
	var color := int(parcel.color)
	if parcel.dc:
		var lab = game.dc_lab
		var key := Vector2i(index,color)
		var stowed: Dictionary = lab.stowed_leads.get(peer,{})
		if stowed.has(key) or (lab.carried_lead_stations.get(peer,-1)==index and lab.carried_leads.get(peer,-1)==color):return false
		stowed[key]=true
		lab.stowed_leads[peer]=stowed
		lab.publish_stowed_leads(peer)
	else:
		if index not in range(game.session.labs.size()):return false
		var lab = game.session.labs[index]
		var stowed: Array = lab.stored_cables.get(peer,[])
		if stowed.size()>=6 or color in stowed or lab.holding(peer).get("color",-1)==color:return false
		stowed.append(color)
		lab.stored_cables[peer]=stowed
		lab.revision+=1
		game.session.broadcast()
	return true

func _take_pcb(peer: int,slot: int,identity: String) -> Dictionary:
	var lab = game.dc_lab
	if slot not in range(lab.benches.size()):return Transfer.Dorm.fail("Board unavailable.")
	var station = lab.benches[slot]
	if station.board_owner!=peer or not (station.board_held or station.board_stowed):
		return Transfer.Dorm.fail("Board is no longer in your hotbar.")
	if not station.board.get("standalone",false):return Transfer.Dorm.fail("Return this breadboard to its kit before discarding the kit.")
	if station.board.get("authority_kit_id","existing_kit")!="":return Transfer.Dorm.fail("This PCB belongs to a kit.")
	var error: String=lab.capture_nonvolatile(peer,slot)
	if not error.is_empty():return Transfer.Dorm.fail(error)
	var dorm = game.dorm_interactions
	var profile: Dictionary=dorm._profile(identity).duplicate(true)
	var deployment: Dictionary={}
	if game.session.online:
		var ledger = dorm._ledger()
		var slots: Dictionary=ledger.deployment_slots(ledger.account(peer).get("deployment",{}))
		slots.erase(str(slot))
		deployment=ledger.summarize_slots(slots)
	var part: Dictionary=station.board.parts[0]
	var board: Dictionary=station.board.duplicate(true)
	var type := str(part.type)
	var instance := str(station.board.get("instance_ids",{}).get(part.id,""))
	var d: Dictionary=profile.dorm
	d.storage[type]=int(d.storage.get(type,0))+1
	if not instance.is_empty():d.instances.append(instance)
	d.carried_components=d.get("carried_components",[])+[{"type":type,"instance":instance}]
	var result := Transfer.take(profile,{"location":"hotbar","item":{"kind":"component","type":type,"instance":instance}},deployment)
	if not result.ok:return result
	var saved: Dictionary=dorm._commit_world_inventory(peer,identity,result.profile,deployment)
	if not saved.ok:return saved
	lab.remove_board_links(slot)
	station.apply({"op":"recall"})
	lab.broadcast()
	result.parcel.pcb=board
	return result

func _give_pcb(peer: int,parcel: Dictionary,claim_token := "",claim_holder := "") -> Dictionary:
	var dorm=game.dorm_interactions
	var identity: String=dorm.authenticated_identity(peer)
	var profile: Dictionary=dorm._profile(identity)
	if not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():return Transfer.Dorm.fail("Inventory is unavailable.")
	var lab=game.dc_lab
	var slot: int=lab._portable_slot()
	if slot<0:return Transfer.Dorm.fail("All portable board slots are in use.")
	var design: Dictionary=parcel.pcb
	var error := Transfer.Board.validate(design,{},true)
	if not error.is_empty():return Transfer.Dorm.fail(error)
	var restored := Transfer.give(profile,parcel,6)
	if not restored.ok:return restored
	if restored.destination!="hotbar":return Transfer.Dorm.fail("Free a hotbar slot for the PCB first.")
	var next: Dictionary=restored.profile
	var d: Dictionary=next.dorm
	var item: Dictionary=parcel.item
	d.carried_components.erase({"type":item.type,"instance":item.instance})
	d.storage[item.type]-=1
	if d.storage[item.type]==0:d.storage.erase(item.type)
	if not str(item.instance).is_empty():d.instances.erase(item.instance)
	var deployment: Dictionary={}
	if game.session.online:
		var ledger=dorm._ledger()
		var slots: Dictionary=ledger.deployment_slots(ledger.account(peer).get("deployment",{}))
		slots[str(slot)]={"slot":slot,"counts":{item.type:1},"kit":"","instance_ids":design.get("instance_ids",{}).values()}
		deployment=ledger.summarize_slots(slots)
	var saved: Dictionary=dorm._commit_world_inventory(peer,identity,next,deployment,claim_token,claim_holder)
	if not saved.ok:return saved
	var station=lab.benches[slot]
	station.apply({"op":"board","design":design})
	station.board_owner=peer
	station.board_stowed=true
	lab.broadcast()
	return {"ok":true}

func _move_food(peer: int,id: String,incoming: Dictionary = {},claim_token := "",claim_holder := "") -> Dictionary:
	var facilities = game.campus_services.facilities
	var controller = facilities.controller
	var host = controller.host
	var context: Dictionary = host.trusted(peer)
	var profile: Dictionary = host.profile(context) if not context.is_empty() else {}
	if profile.is_empty():return Transfer.Dorm.fail("Food inventory is unavailable.")
	var order := incoming
	if incoming.is_empty():
		order=profile.orders.get(id,{})
		if order.is_empty() or order.station!="":return Transfer.Dorm.fail("This food is no longer in your hotbar.")
		profile.orders.erase(id)
	else:
		if profile.orders.size()>=24 or host.carried_order_count(profile.orders)>=6:return Transfer.Dorm.fail("No room for this order.")
		var key := -1
		while profile.orders.has(str(key)):key-=1
		profile.orders[str(key)]=order.duplicate(true)
	profile.revision+=1
	var saved: bool
	if game.session.online:
		saved=facilities.adapter.commit(str(context.identity),0,profile,true,claim_token,claim_holder)
	else:
		saved=facilities.adapter.commit(str(context.identity),0,profile,true)
	if not saved:return Transfer.Dorm.fail("Could not save food transfer.")
	controller._deliver(peer,{"ok":true,"state":host.private_state(peer)})
	return {"ok":true,"order":order}

func _title(parcel: Dictionary,profile: Dictionary) -> String:
	var item: Dictionary=parcel.item
	match item.kind:
		"kit":return str(parcel.kits[item.id].name)
		"bag":return str(Transfer.Dorm.Backpacks.SIZES[parcel.bags[item.id].size].name)
		"supply":return Transfer.Dorm.supply_title(str(item.id))
		"laptop":return str(Transfer.Laptops.TIERS[parcel.laptop.tier].name)
	var catalog := Transfer.Board.catalog({"definitions":profile.get("blueprints",{}),"parts":[item]})
	return str(catalog.get(item.get("type",""),{}).get("name","Component"))

func _notice(peer: int,message: String,refresh := false) -> void:
	if peer==multiplayer.get_unique_id():notice(message,refresh)
	else:notice.rpc_id(peer,message,refresh)

@rpc("authority","call_remote","reliable")
func notice(message: String,refresh: bool) -> void:
	game.ui.log_message(message)
	if refresh:await get_tree().create_timer(.15).timeout
	if not game.electronics.active or game.electronics.current_page!="inventory":return
	if refresh:game.electronics.open("inventory")
	game.electronics.status.text=message
	game.electronics.status.show()

func _publish() -> void:
	if not multiplayer.is_server() or not game.session.online:return
	var public := _public_drops()
	for peer in game.session.connected_peers():sync_drops.rpc_id(peer,public,Time.get_ticks_msec())

func _public_drops() -> Dictionary:
	var public := {}
	for id in drops:
		var drop: Dictionary=drops[id]
		public[id]={"position":drop.position,"expires":drop.expires,"label":drop.label,"visual":_visual_kind(drop)}
		if public[id].visual=="notebook":
			var configuration := _notebook_configuration(drop)
			if not configuration.is_empty():public[id].configuration=configuration
		if public[id].visual.begins_with("calculator"):
			var configuration := _calculator_configuration(drop)
			if not configuration.is_empty():public[id].configuration=configuration
		if public[id].visual.begins_with("bag_"):
			var configuration := _backpack_configuration(drop)
			if not configuration.is_empty():public[id].configuration=configuration
		if public[id].visual.begins_with("kit_"):
			var configuration := _kit_configuration(drop)
			if not configuration.is_empty():public[id].configuration=configuration
		if public[id].visual=="laptop":
			var configuration: Dictionary=drop.get("parcel",{}).get("laptop",{}).get("configuration",{})
			if not configuration.is_empty():public[id].configuration=configuration
		if public[id].visual=="power_bank":public[id].bank=_power_bank(drop)
		if public[id].visual=="pcb":
			if not drop.has("pcb_preview"):drop.pcb_preview=PcbPreview.describe(drop.get("parcel",{}).get("pcb",{}))
			if not drop.pcb_preview.is_empty():public[id].pcb_preview=drop.pcb_preview
	return public

func _notebook_configuration(drop: Dictionary) -> Dictionary:
	var parcel: Dictionary=drop.get("parcel",{})
	return drop.get("configuration",parcel.get("notebook_options",{}).get(parcel.get("item",{}).get("id",""),{}))

func _backpack_configuration(drop: Dictionary) -> Dictionary:
	var parcel: Dictionary=drop.get("parcel",{})
	return drop.get("configuration",parcel.get("bags",{}).get(parcel.get("item",{}).get("id",""),{}).get("configuration",{}))

func _calculator_configuration(drop: Dictionary) -> Dictionary:
	var parcel: Dictionary=drop.get("parcel",{})
	return drop.get("configuration",parcel.get("calculator_options",{}).get(parcel.get("item",{}).get("id",""),{}))

func _kit_configuration(drop: Dictionary) -> Dictionary:
	var parcel: Dictionary=drop.get("parcel",{})
	return drop.get("configuration",parcel.get("kits",{}).get(parcel.get("item",{}).get("id",""),{}).get("configuration",{}))

func _power_bank(drop: Dictionary) -> Dictionary:
	var parcel: Dictionary=drop.get("parcel",{})
	return drop.get("bank",parcel.get("power_banks",{}).get(parcel.get("item",{}).get("id",""),{}))

@rpc("authority","call_remote","reliable")
func sync_drops(public: Dictionary,server_ticks: int) -> void:
	drops=public
	clock_offset=server_ticks-Time.get_ticks_msec()

func pickup_hint(id: int, key: String) -> String:
	var drop: Dictionary=drops.get(id,{})
	if drop.is_empty():return ""
	var hint := "%s\n%s — Pick up" % [drop.label,key]
	if int(drop.expires)>0:
		var seconds := maxi(0,ceili((int(drop.expires)-Time.get_ticks_msec()-clock_offset)/1000.0))
		hint+="\nGround pickup expires in %d:%02d" % [floori(seconds/60.0),seconds%60]
	return hint

func _pickup_pending(id: int, drop: Dictionary) -> bool:
	var token := str(drop.get("token",""))
	if claim_pending.has(token) or pending_commits.has(token):return true
	for transfer in usb_handoffs.pending.values():
		if int(transfer.get("drop",-1))==id:return true
	return false

func _process(_delta: float) -> void:
	if not is_instance_valid(game):return
	if multiplayer.is_server() and game.session.online:
		commit_clock+=_delta
		if commit_clock>=3.0:
			commit_clock=0.0
			for token in pending_commits.keys():_retry_commit(str(token))
			_recover_claim_receipt()
	if multiplayer.is_server() and game.session.online and not import_waiting.is_empty():
		request_clock+=_delta
		if request_clock>=3.0:
			request_clock=0.0
			for peer in import_waiting:
				if game.session.roster.has(peer):request_lost.rpc_id(int(peer))
	if not host_pending_import.is_empty() or (game.session.online and not pending_import.is_empty()):
		import_clock+=_delta
		if import_clock>=2.0:
			import_clock=0.0
			if multiplayer.is_server():
				for token in host_pending_import.keys().slice(0,4):_import_entry(multiplayer.get_unique_id(),str(token),host_pending_import[token])
			else:_send_pending_import()
	if not session_loaded and game.front.in_game and not game.session.online:
		_import_local(1)
	var now := Time.get_ticks_msec()+clock_offset
	var changed := false
	if multiplayer.is_server():
		for id in drops.keys():
			var drop: Dictionary=drops[id]
			if int(drop.expires)<=0 or now<int(drop.expires) or _pickup_pending(id,drop):continue
			var owner := int(drop.owner)
			var token := str(drop.token)
			if not token.is_empty() and not _is_cable_parcel(drop.parcel) and game.session.roster.has(owner):
				queued_entries["%d:%s" % [owner,token]]={"owner":owner,"token":token,"entry":{"label":drop.label,"parcel":drop.parcel}}
			drops.erase(id)
			changed=true
	if changed:
		_fill_tables()
		_publish()
	for id in views.keys():
		if not drops.has(id):
			views[id].queue_free()
			views.erase(id)
	for id in drops:
		var drop: Dictionary=drops[id]
		if not views.has(id):views[id]=_make_view(id,drop)
		var root: StaticBody3D=views[id]
		var seconds := maxi(0,ceili((int(drop.expires)-now)/1000.0))
		var permanent := int(drop.expires)==0
		root.visible=permanent or seconds>0
		root.collision_layer=4 if root.visible else 0
		var ring := root.get_node_or_null("DiscardRing") as MeshInstance3D
		if ring!=null:
			var material := ring.material_override as StandardMaterial3D
			material.albedo_color=Color("bc8556") if int(drop.expires)-now<=WARNING_MS else Color("6c9a8b")

func _visual_kind(drop: Dictionary) -> String:
	if drop.has("visual"):return str(drop.visual)
	var parcel: Dictionary=drop.get("parcel",{})
	if parcel.has("usb"):return "usb"
	if parcel.has("wire"):return "wire_%d" % int(parcel.get("color",0))
	if parcel.has("paper"):
		var supply := Transfer.Dorm.paper_supply(parcel.paper)
		if Transfer.Dorm.is_calculator(supply):return Transfer.Dorm.Keypad.model_for(supply)
		return supply if not supply.is_empty() else "paper"
	if parcel.has("food"):return "food_"+str(parcel.food.get("item",""))
	if parcel.has("pcb"):return "pcb"
	var item: Dictionary=parcel.get("item",{})
	var id:=str(item.get("id",""))
	match str(item.get("kind","")):
		"supply":
			if Transfer.Dorm.is_notebook(id):return "notebook"
			if Transfer.Dorm.PowerBanks.valid_key(id):return "power_bank"
			return Transfer.Dorm.Keypad.model_for(id) if Transfer.Dorm.is_calculator(id) else id
		"kit":return "kit_"+str(parcel.get("tiers",{}).get(id,"standard"))
		"bag":return "bag_"+str(parcel.get("bags",{}).get(id,{}).get("size","backpack_small"))
		"component":return "component:"+str(item.get("type",""))
	return str(item.get("kind","item"))

func _make_view(id: int,drop: Dictionary) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.collision_layer=4
	root.collision_mask=0
	root.set_meta("role","discarded_item")
	root.set_meta("discard_id",id)
	root.set_meta("label","Pick up "+str(drop.label))
	add_child(root)
	root.global_position=drop.position
	if int(drop.expires)>0:
		var ring := MeshInstance3D.new()
		ring.name="DiscardRing"
		var mesh := TorusMesh.new()
		mesh.inner_radius=.215
		mesh.outer_radius=.23
		mesh.rings=32
		mesh.ring_segments=8
		ring.mesh=mesh
		ring.position.y=.011
		ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color("6c9a8b")
		ring.material_override=material
		root.add_child(ring)
	_add_item_visual(root,_visual_kind(drop),drop)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.27,.16,.21)
	collision.shape=shape
	collision.position.y=.08
	root.add_child(collision)
	return root

func _add_item_visual(root: Node3D,kind: String,drop: Dictionary) -> void:
	var prop := Node3D.new();root.add_child(prop)
	if kind=="usb":
		game._box(prop,Vector3(0,.014,0),Vector3(.105,.022,.038),Color("315363"))
		game._box(prop,Vector3(.061,.014,0),Vector3(.025,.012,.027),Color("bdccca"))
	elif kind=="laptop":
		game.ac_laptops._closed_laptop(prop)
		var configuration: Dictionary=drop.get("configuration",drop.get("parcel",{}).get("laptop",{}).get("configuration",{}))
		preload("res://scripts/campus/items/equipment_finish.gd").apply_finish(prop,"portable_laptop",configuration)
	elif kind in ["flashlight","lab_goggles","marker"]:
		game.school_world._build_supply_prop(prop,kind)
		prop.position.y=.05
	elif kind.begins_with("calculator"):
		var options:=_calculator_configuration(drop)
		var dimensions: Vector3=Transfer.Dorm.Equipment.value("calculator",options,"hardware","size",Vector3(.135,.026,.215))
		game.school_world._build_calculator_prop(prop,dimensions,kind,options)
		prop.rotation.x=-PI/2
		prop.position.y=dimensions.y*.5+.012
	elif kind=="pencil_case":
		var toon=preload("res://scripts/toon_character.gd")
		toon.ellipsoid(prop,Vector3(0,.03,0),Vector3(.11,.027,.052),toon.material("a45652"),"Pencil case")
		game._box(prop,Vector3(0,.055,.004),Vector3(.17,.006,.011),Color("633736"))
	elif kind.begins_with("food_"):
		prop.add_child(preload("res://scripts/campus/facilities/food_visual.gd").build(kind.trim_prefix("food_")))
	elif kind.begins_with("bag_"):
		var model:=kind.trim_prefix("bag_")
		preload("res://scripts/campus/items/backpack_model.gd").build(prop,model,_backpack_configuration(drop))
		prop.position.y=Transfer.Dorm.Backpacks.dimensions(model).y*.5
	elif kind.begins_with("kit_"):
		var kit: StaticBody3D=game.kit_world._create_kit_view(0,{"id":"lost","name":str(drop.label),"tier":kind.trim_prefix("kit_"),"configuration":_kit_configuration(drop)},prop)
		kit.collision_layer=0
	elif kind=="notebook":
		preload("res://scripts/campus/items/notebook_model.gd").build(prop,_notebook_configuration(drop))
	elif kind=="power_bank":
		var bank:=_power_bank(drop)
		if Transfer.Dorm.PowerBanks.valid(bank):
			var capacity: float=Transfer.Dorm.PowerBanks.capacity(bank.configuration)
			preload("res://scripts/campus/items/power_bank_model.gd").build(prop,bank.configuration,roundi(100.0*float(bank.charge_wh)/capacity))
	elif kind=="paper":
		game._box(prop,Vector3(0,.012,0),Vector3(.23,.008,.31),Color("eee8d7"))
		for row in 5:
			game._box(prop,Vector3(-.02,.017,-.10+row*.043),Vector3(.15,.001,.004),Color("7e969a"))
	elif kind=="whiteboard":
		game._box(prop,Vector3(0,.015,0),Vector3(.30,.03,.22),Color("72858b"))
		game._box(prop,Vector3(0,.032,0),Vector3(.27,.004,.19),Color("e8eeeb"))
	elif kind.begins_with("wire_"):
		var colors: Array=game.JACKET_COLORS
		var color: Color=colors[clampi(int(kind.trim_prefix("wire_")),0,colors.size()-1)]
		prop.add_child(preload("res://scripts/cable_mesh.gd").build(Vector3(-.13,.04,0),Vector3(.13,.04,0),color))
	elif kind=="pcb":
		var preview: Dictionary=drop.get("pcb_preview",{})
		if preview.is_empty():preview=PcbPreview.describe(drop.get("parcel",{}).get("pcb",{}))
		if not PcbPreview.build(game,prop,preview):
			game._box(prop,Vector3(0,.012,0),Vector3(.23,.024,.16),Color("287258"))
			game._box(prop,Vector3(0,.032,0),Vector3(.065,.015,.055),Color("252c32"))
	elif kind.begins_with("component:"):
		var type := kind.trim_prefix("component:")
		var model: Dictionary=preload("res://scripts/electronics_catalog.gd").simulation_entry(type)
		if not model.is_empty():
			var component=preload("res://scripts/board_components_3d.gd").new();prop.add_child(component)
			var pin_positions: Array=[]
			var count: int=model.get("pins",[]).size()
			for index in count:
				var side: int=index%2
				pin_positions.append(Vector2(490.0+side*20.0,220.0+(floori(float(index)/2.0)-floori(float(count)/4.0))*6.0))
			component.build_device(game,{"id":"lost","type":type,"center":Vector2(500,220),"pins":pin_positions},model)
			for label in component.find_children("*","Label3D",true,false):label.hide()
			if component.get_child_count()==0:game._box(prop,Vector3(0,.015,0),Vector3(.07,.025,.05),Color("273a41"))
		else:game._box(prop,Vector3(0,.015,0),Vector3(.07,.025,.05),Color("273a41"))
	else:
		game._box(prop,Vector3.UP*.018,Vector3(.22,.035,.16),Color("e8e1d2"))

# The player's own checksummed store travels with their client, never the host.
func _open_store() -> bool:
	var identity: String=game.school.local_identity
	if identity.is_empty():return false
	if store_identity==identity and local_store.healthy:return true
	store_identity=identity
	local_store=Store.new()
	if local_store.open("user://lost_loot_"+identity.sha256_text().left(24))!=OK:
		game.ui.log_message("Lost and found save could not be read; existing data was preserved.")
		return false
	return true

func _save_entries(entries: Dictionary) -> bool:
	if not _open_store() or local_store.commit({"entries":entries})!=OK:
		game.ui.log_message("Could not save lost and found items on this computer.")
		return false
	return true

func _local_entries() -> Dictionary:
	if not _open_store():return {}
	var entries: Variant=local_store.value.get("entries",{})
	return entries.duplicate(true) if entries is Dictionary else {}

func track_ground(peer: int,parcel: Dictionary,label: String) -> String:
	if _is_cable_parcel(parcel):return ""
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	if peer==multiplayer.get_unique_id():cache_ground(token,parcel,label)
	else:cache_ground.rpc_id(peer,token,parcel,label)
	return token

func can_track_personal(peer: int) -> bool:
	if _personal_count(peer)<PERSONAL_LIMIT:return true
	_notice(peer,"Lost & Found is full (%d items). Pick up one of your items before discarding another." % PERSONAL_LIMIT)
	return false

func _personal_count(peer: int) -> int:
	var count:=checking_imports.values().count(peer)
	for drop in drops.values():
		if int(drop.get("owner",0))==peer and not str(drop.get("token","")).is_empty():count+=1
	for record in queued_entries.values():
		if int(record.owner)==peer:count+=1
	for paper in game.school.papers.values():
		if int(paper.get("owner",0))==peer and not str(paper.get("lost_token","")).is_empty():count+=1
	return count

static func _is_cable_parcel(parcel: Dictionary) -> bool:
	var item: Variant=parcel.get("item")
	return parcel.has("wire") or (item is Dictionary and item.get("kind") in CABLE_KINDS)

@rpc("authority","call_remote","reliable",6)
func cache_ground(token: String,parcel: Dictionary,label: String) -> void:
	if not _valid_entry(token,{"parcel":parcel,"label":label}):return
	var entries := _local_entries()
	if entries.size()>=96:return
	entries[token]={"parcel":parcel.duplicate(true),"label":label.left(80),"ground":true}
	_save_entries(entries)

func forget_ground(peer: int,token: String) -> void:
	if token.is_empty() or peer<=0:return
	if peer==multiplayer.get_unique_id():forget_local(token)
	elif game.session.roster.has(peer):forget_local.rpc_id(peer,token)

@rpc("authority","call_remote","reliable",6)
func forget_local(token: String) -> void:
	if not _forget_entry(token) and not forget_retrying.has(token):_retry_forget(token)

func _forget_entry(token: String) -> bool:
	if not _open_store():return false
	var entries := _local_entries()
	if not entries.erase(token):return true
	return _save_entries(entries)

func _retry_forget(token: String) -> void:
	forget_retrying[token]=true
	var epoch := import_retry_epoch
	for attempt in 3:
		await get_tree().create_timer(2.0).timeout
		if epoch!=import_retry_epoch:return
		if _forget_entry(token):break
	forget_retrying.erase(token)

func _leaving() -> void:
	import_retry_epoch+=1
	import_retrying=false
	pending_import.clear();host_pending_import.clear();import_clock=0.0;import_cursor=0
	for token in forget_retrying.keys():_forget_entry(str(token))
	forget_retrying.clear()
	if not session_loaded and store_identity.is_empty():return
	var entries := _local_entries()
	var changed := false
	for entry in entries.values():
		if entry is Dictionary and entry.get("ground",false):entry.ground=false;changed=true
	if changed:_save_entries(entries)
	session_loaded=false

func _profile_ready(peer: int) -> void:
	if not multiplayer.is_server() or imported_peers.has(peer):return
	if peer==multiplayer.get_unique_id():
		if _import_local(peer):imported_peers[peer]=true
		else:_retry_local_import(peer)
	else:
		import_waiting[peer]=true
		request_lost.rpc_id(peer)

@rpc("authority","call_remote","reliable",6)
func request_lost() -> void:
	if not _import_local(multiplayer.get_unique_id()):_retry_local_import(multiplayer.get_unique_id())

func _retry_local_import(peer: int) -> void:
	if import_retrying:return
	import_retrying=true
	var epoch := import_retry_epoch
	for attempt in 3:
		await get_tree().create_timer(2.0).timeout
		if epoch!=import_retry_epoch:return
		if not import_retrying or session_loaded or peer!=multiplayer.get_unique_id():break
		if _import_local(peer):
			if multiplayer.is_server():imported_peers[peer]=true
			break
	import_retrying=false

func _import_local(peer: int) -> bool:
	if session_loaded:
		if not multiplayer.is_server():_send_pending_import()
		return true
	if not _open_store():return false
	var entries := _local_entries()
	var previous: Dictionary=entries.duplicate(true)
	entries=_reconcile_local_usb_entries(entries)
	# Old ground entries came from an interrupted session. Keep personal items
	# recoverable, including any that have to wait for a slot.
	for token in entries.keys():
		var entry: Variant=entries[token]
		if not entry is Dictionary:continue
		if entry.get("parcel") is Dictionary and _is_cable_parcel(entry.parcel):
			entries.erase(token)
		else:
			entry.ground=false
	if entries!=previous and not _save_entries(entries):return false
	session_loaded=true
	if multiplayer.is_server():
		host_pending_import=entries.duplicate(true)
		_import_entries(peer,entries)
	else:
		pending_import=entries.duplicate(true)
		_send_pending_import()
	return true

func _send_pending_import() -> void:
	if not game.session.online or multiplayer.is_server():return
	var tokens:=pending_import.keys()
	if tokens.is_empty():import_complete.rpc_id(1);return
	for offset in mini(4,tokens.size()):
		var token: String=str(tokens[(import_cursor+offset)%tokens.size()])
		submit_lost.rpc_id(1,token,pending_import[token])
	import_cursor=(import_cursor+4)%tokens.size()

@rpc("any_peer","call_remote","reliable",6)
func import_complete() -> void:
	if not multiplayer.is_server():return
	var peer:=multiplayer.get_remote_sender_id()
	if import_waiting.erase(peer):imported_peers[peer]=true

func _reconcile_local_usb_entries(entries: Dictionary) -> Dictionary:
	var dorm: Dictionary=game.electronics.profile.data.get("dorm",{})
	var owner: String=str(dorm.get("owner",""))
	var drives: Dictionary=dorm.get("usb_drives",{})
	for token in entries.keys():
		var usb: Variant=entries[token].get("parcel",{}).get("usb",null) if entries[token] is Dictionary else null
		if usb is Dictionary and (usb.get("owner","")!=owner or drives.get(str(usb.get("id","")),{}).get("location","")!="lost"):entries.erase(token)
	for id in drives:
		var item: Dictionary=drives[id]
		if item.get("location","")!="lost":continue
		if not entries.has(id) and entries.size()>=96:continue
		var archive=preload("res://scripts/campus/computers/usb_archive.gd")
		if archive.load(owner,str(id),int(item.capacity_mb)).has("error"):continue
		entries[id]={"parcel":{"usb":{"id":str(id),"owner":owner,"name":str(item.name),"capacity_mb":int(item.capacity_mb)}},"label":str(item.name).left(80),"ground":false}
	return entries

@rpc("any_peer","call_remote","reliable",6)
func submit_lost(token: String,entry: Dictionary) -> void:
	if multiplayer.is_server():_import_entry(multiplayer.get_remote_sender_id(),token,entry)

@rpc("authority","call_remote","reliable",6)
func import_ack(token: String,result: String) -> void:
	if not pending_import.has(token):return
	if result=="claimed":
		if not _forget_entry(token):return
	elif result=="invalid":
		game.ui.log_message("A saved lost-and-found item could not be imported.")
	elif result!="accepted":return
	pending_import.erase(token)
	if pending_import.is_empty():import_complete.rpc_id(1)

func _valid_entry(token: String,entry: Variant) -> bool:
	if token.length()!=32 or not token.is_valid_hex_number() or not entry is Dictionary:return false
	if not entry.get("label") is String or str(entry.label).length()>80 or not entry.get("parcel") is Dictionary:return false
	var parcel: Dictionary=entry.parcel
	if _is_cable_parcel(parcel) or var_to_bytes(parcel).size()>1048576:return false
	if parcel.has("usb"):
		var usb: Variant=parcel.usb
		return usb is Dictionary and usb.get("id") is String and str(usb.id)==token and str(usb.id).length()==32 and str(usb.id).is_valid_hex_number() and Transfer.Dorm.identity_ok(usb.get("owner")) and usb.get("name") is String and preload("res://scripts/campus/computers/usb_archive.gd").valid_name(usb.name) and int(usb.get("capacity_mb",0)) in [8,32,64,150]
	if parcel.has("food"):return parcel.food is Dictionary and parcel.food.get("item") is String
	if parcel.has("paper"):return parcel.paper is Dictionary and not game.school._class_assessment(parcel.paper)
	if not parcel.get("item") is Dictionary or parcel.item.get("kind") not in PERSONAL_ITEM_KINDS:return false
	if parcel.item.get("kind")=="laptop":
		var id: String=str(parcel.item.get("id",""))
		if id.length()!=32 or not id.is_valid_hex_number() or not parcel.get("laptop") is Dictionary or not Transfer.Laptops.TIERS.has(parcel.laptop.get("tier","")):return false
		if parcel.laptop.has("configuration") and Transfer.Laptops.Config.quote(Transfer.Laptops.Config.LAPTOP,0,parcel.laptop.configuration).is_empty():return false
	for key in ["kits","tiers","bags","stock","instances","supplies","definitions","carried_stock"]:
		if not parcel.get(key) is Dictionary:return false
	return parcel.get("carried_instances") is Array and (not parcel.has("pcb") or parcel.pcb is Dictionary)

func _import_entries(peer: int,entries: Dictionary) -> void:
	if not game.session.roster.has(peer):return
	for token in entries:
		if token is String and entries[token] is Dictionary:_import_entry(peer,token,entries[token])

func _import_entry(peer: int,token: String,entry: Dictionary) -> void:
	if not game.session.roster.has(peer):return
	if not _valid_entry(token,entry):_ack_import(peer,token,"invalid");return
	if entry.parcel.has("usb") and str(entry.parcel.usb.owner)!=game.dorm_interactions.authenticated_identity(peer):_ack_import(peer,token,"invalid");return
	var key:=str(peer)+":"+token
	if checking_imports.has(key):return
	if queued_entries.has(key) or drops.values().any(func(drop):return int(drop.get("owner",0))==peer and str(drop.get("token",""))==token):
		_ack_import(peer,token,"accepted");return
	if _personal_count(peer)>=PERSONAL_LIMIT or queued_entries.size()>=96:_ack_import(peer,token,"retry");return
	checking_imports[key]=peer
	var epoch:=import_retry_epoch
	if game.session.online:
		var status: Dictionary=await ClaimAuthority.status(self,token)
		if epoch!=import_retry_epoch:return
		if not game.session.roster.has(peer):checking_imports.erase(key);return
		if not status.get("ok",false):checking_imports.erase(key);_ack_import(peer,token,"retry");return
		if status.get("claimed",false):
			checking_imports.erase(key)
			_ack_import(peer,token,"claimed")
			return
	checking_imports.erase(key)
	queued_entries[key]={"owner":peer,"token":token,"entry":entry.duplicate(true)}
	_ack_import(peer,token,"accepted")
	_fill_tables()
	_publish()

func _ack_import(peer: int,token: String,result: String) -> void:
	if peer==multiplayer.get_unique_id():
		if result=="claimed" and not _forget_entry(token):return
		if result in ["accepted","claimed","invalid"]:host_pending_import.erase(token)
	elif game.session.roster.has(peer):import_ack.rpc_id(peer,token,result)

func _fill_tables() -> void:
	for key in queued_entries.keys():
		if drops.size()>=96:break
		var record: Dictionary=queued_entries[key]
		if not game.session.roster.has(int(record.owner)):
			queued_entries.erase(key)
			continue
		var position:=_available_table_position()
		if not position.is_finite():break
		var entry: Dictionary=record.entry
		drops[next_id]={"position":position,"expires":0,"label":str(entry.label),"parcel":entry.parcel.duplicate(true),"owner":int(record.owner),"token":str(record.token)}
		next_id+=1
		queued_entries.erase(key)

func _available_table_position() -> Vector3:
	for slot in 96:
		var x := -6.65+float(slot%24)*.30
		var z := (62.35 if int(slot/48)==0 else 65.65) + (-.23 if int(slot/24)%2==0 else .23)
		var point := Vector3(x,.84,z)
		if not drops.values().any(func(drop):return drop.position.distance_squared_to(point)<.01):return point
	return Vector3.INF

func _roster_changed() -> void:
	if multiplayer.is_server():
		for peer in imported_peers.keys():
			if not game.session.roster.has(peer):imported_peers.erase(peer)
		for peer in import_waiting.keys():
			if not game.session.roster.has(peer):import_waiting.erase(peer)
		for id in drops.keys():
			if drops[id].has("owner") and not game.session.roster.has(drops[id].owner):drops.erase(id)
		for key in queued_entries.keys():
			if not game.session.roster.has(int(queued_entries[key].owner)):queued_entries.erase(key)
		_fill_tables()
		for id in game.school.floor_leads.keys():
			if not game.session.roster.has(game.school.floor_leads[id].owner):game.school.floor_leads.erase(id)
	_publish()
