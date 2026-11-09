extends Node
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Router=preload("res://scripts/campus/dorms/interactions/personal_station_router.gd")
const CabinetUI=preload("res://scripts/ui/design_system/widgets.gd")
const CabinetTheme=preload("res://scripts/ui/design_system/theme.gd")
var game: Node
var hall: Node3D
var router: Node
var snapshot := {}
var epoch := 0
var sequence := 0
var leases := {}
var occupants := {}
var open_doors := {}
var sequences := {}
var clock := 0.0
var ledger_id := 0
var directory: Window
var operation_window: PanelContainer
var cabinet_layer: CanvasLayer
var cabinet_scroll: ScrollContainer
var cabinet_revision := -1
var computer_stations := {}
var observed_local_room := ""
var interiors := {}
var interior_versions := {}
var decorate: Control
var decorate_room := ""
var preview: MeshInstance3D
var directory_pages := {}
func build(owner_game: Node) -> void:
	game=owner_game
	hall=preload("res://scripts/campus/dorms/world/dorm_hall.gd").new();game.campus.add_child(hall);hall.build(game.session.MAX_PLAYERS)
	router=Router.new();add_child(router);router.configure(game,self)
	if game.has_method("install_dorm_rest"):game.install_dorm_rest(self)
	game.session.restarted.connect(_restart)
	game.session.leaving.connect(_restart)
	game.session.roster_changed.connect(_reconcile)
	game.electronics_trade.authority.profile_ready.connect(func(_peer: int):_reconcile())
	game.electronics_trade.authority.operation_result.connect(_operation_result)
	hall.door_motion_finished.connect(func():_sync_interiors(snapshot))
	_restart()
func _ledger():
	return game.electronics_trade.authority.ledger
func _restart() -> void:
	epoch+=1;sequence=0;snapshot={};leases.clear();occupants.clear();sequences.clear();open_doors.clear()
	hall.apply_open_doors(open_doors)
	for adapter in interiors.values():adapter.queue_free()
	interiors.clear();interior_versions.clear()
	_dismiss_storage()
	for bay in hall.door_targets:hall.set_door_title(bay,"Dorm")
	_reconcile()
func authenticated_identity(peer: int) -> String:
	if not game.session.roster.has(peer):return ""
	if not multiplayer.is_server():
		return str(snapshot.get("identities",{}).get(peer,""))
	if game.session.online:return str(_ledger().bindings.get(peer,""))
	return game.school.local_identity if peer==1 else ""
func _profile(identity: String) -> Dictionary:
	if game.session.online:return _ledger().state.accounts.get(identity,{}).get("profile",{})
	return game.electronics.profile.data if identity==game.school.local_identity else {}
func owner_identity(room: String) -> String:
	var identity := room.trim_prefix("dorm_")
	if not multiplayer.is_server():return identity if Dorm.identity_ok(identity) and (snapshot.get("directory",{}).has(room) or room in leases.values()) else ""
	return identity if Dorm.identity_ok(identity) and _profile(identity).get("dorm",{}).get("room_id")==room else ""
func is_owner(identity: String,room: String) -> bool:
	return not identity.is_empty() and owner_identity(room)==identity
func can_enter(identity: String,room: String) -> bool:
	if not multiplayer.is_server():return identity in snapshot.get("access",{}).get(room,[])
	var owner := owner_identity(room)
	if owner.is_empty() or not Dorm.identity_ok(identity):return false
	if Dorm.may_enter(_profile(owner).get("dorm",{}),owner,identity):return true
	if open_doors.has(_bay_for(room)):return true
	for peer in occupants:
		if occupants[peer] == room and authenticated_identity(int(peer)) == identity:return true
	return false
func room_for_peer(peer: int) -> String:
	var identity := authenticated_identity(peer)
	if not multiplayer.is_server():return "dorm_"+identity if not identity.is_empty() else ""
	return str(_profile(identity).get("dorm",{}).get("room_id","")) if not identity.is_empty() else ""
func is_in_own_room(peer: int, point: Vector3) -> bool:
	var room := room_for_peer(peer)
	if room.is_empty(): return false
	var bay := _bay_for(room)
	for contract in hall.room_contracts:
		if contract.dorm_id == bay:
			return AABB(contract.bounds_min,contract.bounds_max-contract.bounds_min).has_point(point + Vector3.UP * .12)
	return false

func valid_desk_surface(peer: int, point: Vector3) -> bool:
	var identity := authenticated_identity(peer)
	for room_id in interiors:
		if not can_enter(identity,room_id):continue
		var desk: Node3D = interiors[room_id].room.targets.get("study_desk")
		if not is_instance_valid(desk) or not desk.visible:continue
		var local := desk.to_local(point)
		if absf(local.x)<1.175 and absf(local.z)<.55 and absf(local.y-.065)<.03:
			return true
	return false

func assignment_revision() -> int:return int(snapshot.get("revision",0))
func locate_room(peer: int) -> Dictionary:
	var room := room_for_peer(peer)
	var entry: Dictionary = snapshot.get("directory", {}).get(room, {})
	var number := str(entry.get("number", _profile(authenticated_identity(peer)).get("dorm", {}).get("number", "")))
	return {"room_id":room,"number":number,"entrance":_bay_for(room),"directory":Vector3(13,0,69)}
func _bay_for(room: String) -> String:
	for bay in leases:
		if leases[bay]==room:return str(bay)
	return ""
func _lease(room: String) -> String:
	var existing := _bay_for(room)
	if not existing.is_empty():return existing
	for contract in hall.room_contracts:
		var bay: String=contract.dorm_id
		if not leases.has(bay):
			leases[bay]=room;return bay
	for contract in hall.room_contracts:
		var bay: String=contract.dorm_id
		if not occupants.values().has(leases[bay]):
			open_doors.erase(bay)
			leases[bay]=room
			return bay
	return ""
func _reconcile() -> void:
	if not is_instance_valid(game) or not multiplayer.is_server():return
	for peer in occupants.keys():
		if authenticated_identity(int(peer)).is_empty() or not can_enter(authenticated_identity(int(peer)),occupants[peer]):occupants.erase(peer)
	var desired := []
	for peer in game.session.roster:
		var room := room_for_peer(int(peer))
		if not room.is_empty():desired.append(room)
	for bay in leases.keys():
		if leases[bay] not in desired and leases[bay] not in occupants.values():
			leases.erase(bay)
			open_doors.erase(bay)
	for peer in game.session.roster:
		var room := room_for_peer(int(peer))
		if not room.is_empty():_lease(room)
	_publish()
func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	_bind_computers()
	if is_instance_valid(operation_window) and operation_window.visible:
		var revision := int(game.electronics.profile.data.get("dorm",{}).get("revision",-1))
		if revision!=cabinet_revision:
			_refresh_storage.call_deferred()
	if is_instance_valid(decorate) and decorate.visible:
		var own := room_for_peer(multiplayer.get_unique_id())
		if own!=decorate_room or not interiors.has(own):decorate.close_room()
	if not multiplayer.is_server():return
	clock+=delta
	if clock<.25:return
	clock=0
	if ledger_id!=_ledger().get_instance_id():ledger_id=_ledger().get_instance_id();_reconcile()
	# Offline profile readiness has no inventory enrollment signal.
	var local_room := room_for_peer(1)
	if observed_local_room!=local_room:observed_local_room=local_room;_reconcile()
	for peer in occupants.keys():
		var room: String=occupants[peer];var bay := _bay_for(room)
		var pos: Vector3=game.player.global_position if int(peer)==1 else game.session.poses.get(peer,{}).get("position",Vector3.INF)
		for contract in hall.room_contracts:
			if contract.dorm_id==bay and not AABB(contract.bounds_min,contract.bounds_max-contract.bounds_min).grow(.5).has_point(pos):occupants.erase(peer)
	# Open doors permit entry. Visitors already inside may leave after a door closes.
	for peer in game.session.roster:
		var pos: Vector3=game.player.global_position if int(peer)==1 else game.session.poses.get(peer,{}).get("position",Vector3.INF)
		for contract in hall.room_contracts:
			if not AABB(contract.bounds_min,contract.bounds_max-contract.bounds_min).has_point(pos):continue
			var room := str(leases.get(contract.dorm_id,""))
			if not can_enter(authenticated_identity(int(peer)),room):
				var outside: Vector3=contract.door+Vector3(1 if contract.side=="west" else -1,0,0)
				if int(peer)==1:_arrive(outside)
				else:_arrive.rpc_id(int(peer),outside)
			else:occupants[peer]=room
	_publish()
func _publish() -> void:
	var rooms := []
	for bay in leases:
		var owner := owner_identity(leases[bay])
		if not owner.is_empty():rooms.append({"bay":bay,"room":Dorm.public_room(_profile(owner))})
	var listing := {};var identities := {};var access := {}
	if game.session.online:
		for account in _ledger().state.accounts.values():
			var d: Dictionary=account.profile.get("dorm",{})
			if not d.is_empty():listing[d.room_id]={"number":d.number,"policy":d.policy}
	else:
		var d: Dictionary=game.electronics.profile.data.get("dorm",{})
		if not d.is_empty():listing[d.room_id]={"number":d.number,"policy":d.policy}
	for peer in game.session.roster:
		var identity := authenticated_identity(int(peer))
		if not identity.is_empty():identities[peer]=identity
	for room in listing:
		access[room]=[]
		for identity in identities.values():
			if can_enter(identity,room):access[room].append(identity)
	var data := {"schema":2,"epoch":epoch,"revision":int(snapshot.get("revision",0))+1,"rooms":rooms,"directory":listing,"identities":identities,"access":access,"occupants":occupants.duplicate(true),"open_doors":open_doors.duplicate()}
	_receive(_directory_page(data,1))
	for peer in game.session.connected_peers():_receive.rpc_id(int(peer),_directory_page(data,int(peer)))
func _directory_page(data: Dictionary,peer: int) -> Dictionary:
	var next := data.duplicate(true)
	var ids: Array=data.directory.keys();ids.sort()
	var pages := maxi(1,ceili(float(ids.size())/32.0))
	var page := clampi(int(directory_pages.get(peer,0)),0,pages-1)
	next.directory={};next.access={};next.directory_page=page;next.directory_pages=pages
	var visible: Array=leases.values().duplicate()
	for index in range(page*32,mini((page+1)*32,ids.size())):
		var room: String=ids[index];next.directory[room]=data.directory[room];visible.append(room)
	var own := room_for_peer(peer)
	if data.directory.has(own):next.directory[own]=data.directory[own];visible.append(own)
	var identity := authenticated_identity(peer)
	if peer != 1:
		for entry in next.rooms:
			if identity not in data.access.get(entry.room.room_id, []):entry.room.erase("customization")
	for room in visible:
		if data.access.has(room):next.access[room]=data.access[room]
	return next
@rpc("authority","call_remote","reliable",7)
func _receive(data: Dictionary) -> void:
	if data.get("schema")!=2 or var_to_bytes(data).size()>262144:return
	var page_changed: bool=data.get("directory_page",0)!=snapshot.get("directory_page",0)
	snapshot=data.duplicate(true)
	leases.clear()
	for entry in data.get("rooms",[]):
		leases[entry.bay]=entry.room.room_id
	hall.apply_open_doors(data.get("open_doors", {}))
	for bay in hall.door_targets:
		var room_id := str(leases.get(bay,""))
		var title := "Dorm"
		if not game.session.online and room_id != "" and room_id == room_for_peer(multiplayer.get_unique_id()):
			title = "Your dorm"
		elif game.session.online and room_id != "":
			for peer in data.get("identities",{}):
				if "dorm_"+str(data.identities[peer]) == room_id:
					title = str(game.session.roster.get(peer,{}).get("name","Student"))
					break
		hall.set_door_title(bay,title)
	router.assignment_changed()
	_sync_interiors(data)
	if page_changed and is_instance_valid(directory) and directory.visible:_show_directory.call_deferred()
func interact(target: Node) -> bool:
	if is_instance_valid(target) and target.get_meta("role","")=="dorm_decorate":
		_open_decorate(str(target.get_meta("room_id","")));return true
	for adapter in interiors.values():
		if adapter.interact(target,authenticated_identity(multiplayer.get_unique_id())):return true
	if router.interact(target):return true
	if not is_instance_valid(target):return false
	if target.get_meta("role","")!="dorm_door":return false
	var room: String=str(leases.get(str(target.get_meta("dorm_id","")),""))
	sequence+=1
	var action := {"op":"toggle_door","room":room,"epoch":snapshot.get("epoch",-1),"sequence":sequence}
	if multiplayer.is_server():_request_for(multiplayer.get_unique_id(),action)
	else:_request.rpc_id(1,action)
	return true
@rpc("any_peer","call_remote","reliable",7)
func _request(action: Dictionary) -> void:
	if multiplayer.is_server():_request_for(multiplayer.get_remote_sender_id(),action)
func _request_for(peer: int,action: Dictionary) -> void:
	var identity := authenticated_identity(peer)
	if identity.is_empty() or var_to_bytes(action).size()>1024 or action.get("epoch")!=epoch or not action.get("sequence") is int or action.sequence<=int(sequences.get(peer,0)):return
	sequences[peer]=action.sequence
	if action.get("op")=="page":
		var position: Vector3=game.player.global_position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.INF)
		if position.distance_to(Vector3(13,0,69))>4 or not action.get("page") is int:return
		directory_pages[peer]=maxi(0,int(action.page));_publish();return
	var room := str(action.get("room",""))
	if not can_enter(identity,room):return
	var pos: Vector3=game.player.global_position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if action.get("op")=="locate":
		if pos.distance_to(Vector3(13,0,69))>4:return
		var bay := _lease(room)
		if bay.is_empty():return
		_publish();return
	if action.get("op") != "toggle_door":return
	var owner := owner_identity(room)
	if owner.is_empty() or not Dorm.may_enter(_profile(owner).get("dorm",{}), owner, identity):return
	var bay := _bay_for(room)
	for contract in hall.room_contracts:
		if contract.dorm_id != bay:continue
		var center: Vector3 = contract.door
		if pos.distance_to(center + Vector3.UP) > 3.0:return
		var swing_center := center + Vector3(-.65 if contract.side == "west" else .65, 1.05, -.18)
		var sweep := AABB(swing_center - Vector3(.94, 1.25, .94), Vector3(1.88, 2.5, 1.88))
		for other in game.session.roster:
			var other_pos: Vector3 = game.player.global_position if int(other) == 1 else game.session.poses.get(other,{}).get("position", Vector3.INF)
			if sweep.has_point(other_pos):return
		if open_doors.has(bay):
			open_doors.erase(bay)
		else:
			open_doors[bay] = true
		_publish()
		break
@rpc("authority","call_remote","reliable",7)
func _arrive(point: Vector3) -> void:
	game.player.global_position=point+Vector3(0,.15,0)
func _show_directory() -> void:
	if is_instance_valid(directory):directory.queue_free()
	directory=Window.new();directory.title="Profile · My dorm";directory.size=Vector2i(580,400);add_child(directory)
	var box := VBoxContainer.new();directory.add_child(box)
	var assignment := locate_room(multiplayer.get_unique_id())
	var mine := Label.new()
	mine.text = "My dorm entrance · " + str(assignment.entrance).to_upper() if not str(assignment.entrance).is_empty() else "Waiting for profile enrollment…"
	mine.tooltip_text = str(assignment.number)
	box.add_child(mine)
	var page_label := Label.new();page_label.text="Directory page %d / %d"%[int(snapshot.get("directory_page",0))+1,int(snapshot.get("directory_pages",1))];box.add_child(page_label)
	for direction in [-1,1]:
		var button := Button.new();button.text="Previous page" if direction<0 else "Next page";box.add_child(button)
		button.pressed.connect(func():
			sequence+=1
			var action := {"op":"page","page":int(snapshot.get("directory_page",0))+direction,"epoch":snapshot.get("epoch",-1),"sequence":sequence}
			if multiplayer.is_server():_request_for(multiplayer.get_unique_id(),action)
			else:_request.rpc_id(1,action)
			_show_directory.call_deferred())
	for policy in ["Private","Invited","Open"]:
		var button := Button.new();button.text="Access: "+policy;box.add_child(button)
		button.pressed.connect(func():submit_intent(Crypto.new().generate_random_bytes(16).hex_encode(),{"op":"policy","revision":int(game.electronics.profile.data.get("dorm",{}).get("revision",-1)),"value":policy}))
	var invitations := LineEdit.new();invitations.placeholder_text="Invited student IDs, separated by commas";box.add_child(invitations)
	var save_invites := Button.new();save_invites.text="Save invitations";box.add_child(save_invites)
	save_invites.pressed.connect(func():
		var ids := []
		for id in invitations.text.split(",",false):ids.append(id.strip_edges().trim_prefix("D-").trim_prefix("dorm_"))
		submit_intent(Crypto.new().generate_random_bytes(16).hex_encode(),{"op":"invite","revision":int(game.electronics.profile.data.get("dorm",{}).get("revision",-1)),"value":ids}))
	for room in snapshot.get("directory",{}):
		var entry: Dictionary=snapshot.directory[room]
		var bay := _bay_for(room)
		var button := Button.new()
		button.text = ("%s · " % bay.to_upper() if not bay.is_empty() else "") + str(entry.number).left(12) + " · " + str(entry.policy)
		button.tooltip_text = str(entry.number)
		box.add_child(button)
		button.pressed.connect(func():
			sequence+=1
			var action := {"op":"locate","room":room,"epoch":snapshot.get("epoch",-1),"sequence":sequence}
			if multiplayer.is_server():_request_for(multiplayer.get_unique_id(),action)
			else:_request.rpc_id(1,action))
	directory.close_requested.connect(func():directory.hide();game.capture())
	game.release_mouse();directory.popup_centered()

func submit_intent(operation_id: String,intent: Dictionary) -> Dictionary:
	# Local UI adapter only. Multiplayer mutation is still authenticated by the
	# inventory RPC's sender and ledger binding; no payload identity is accepted.
	if game.session.online:
		game.electronics_trade.authority.submit_dorm(operation_id,intent)
		return {"ok":false,"pending":true}
	var profile=game.electronics.profile
	var digest := var_to_bytes(intent).hex_encode().sha256_text()
	var receipts: Dictionary=profile.data.get("dorm_receipts",{})
	if receipts.has(operation_id):return {"ok":receipts[operation_id]==digest,"error":"Operation ID conflict" if receipts[operation_id]!=digest else ""}
	if operation_id.is_empty() or operation_id.length()>96 or receipts.size()>=256:return {"ok":false,"error":"Offline receipt limit"}
	var reservations: Dictionary=game.electronics_trade.authority.local_craft_reservations()
	for type in profile.data.get("dorm",{}).get("storage",{}):reservations.counts[type]=int(reservations.counts.get(type,0))-int(profile.data.dorm.storage[type])
	for id in profile.data.get("dorm",{}).get("instances",[]):reservations.instance_ids.erase(id)
	if game.kit_world.blocks_dorm_transfer(multiplayer.get_unique_id(),intent):return {"ok":false,"error":"Pick up and stow the kit before transferring it"}
	var applied: Dictionary=Dorm.apply_intent(profile.data,game.school.local_identity,intent,reservations)
	if not applied.ok:return applied
	var before: Dictionary=profile.data
	profile.data=applied.profile
	profile.data.dorm_receipts=receipts.duplicate(true);profile.data.dorm_receipts[operation_id]=digest
	if profile.save()!=OK:profile.data=before;return {"ok":false,"error":"Save failed; unchanged"}
	_reconcile()
	if is_instance_valid(operation_window) and operation_window.visible:_refresh_storage.call_deferred()
	return {"ok":true,"state":profile.data.dorm.customization,"revision":profile.data.dorm.revision}

func storage_transfer(identity: String,room: String,operation_id: String,item: String,quantity: int,into_storage: bool,instances: Array=[]) -> Dictionary:
	if identity!=authenticated_identity(multiplayer.get_unique_id()) or not is_owner(identity,room):return {"ok":false,"error":"Owner required"}
	if quantity<=0:return {"ok":false,"error":"Invalid quantity"}
	var d: Dictionary=game.electronics.profile.data.get("dorm",{})
	return submit_intent(operation_id,{"op":"storage","revision":int(d.get("revision",-1)),"item":item,"delta":quantity if into_storage else -quantity,"instances":instances})

func move_world_supply(peer: int, item: String, into_hotbar: bool) -> Dictionary:
	if not multiplayer.is_server():return {"ok":false,"error":"Host required"}
	var identity := authenticated_identity(peer)
	if identity.is_empty():return {"ok":false,"error":"Profile unavailable"}
	var applied := Dorm.move_world_supply(_profile(identity),item,into_hotbar)
	if not applied.ok:return applied
	return _commit_world_inventory(peer,identity,applied.profile)

func move_world_backpack(peer: int, bag: String, into_hotbar: bool, point := Vector3.ZERO) -> Dictionary:
	if not multiplayer.is_server():return {"ok":false,"error":"Host required"}
	var identity := authenticated_identity(peer)
	if identity.is_empty():return {"ok":false,"error":"Profile unavailable"}
	var profile: Dictionary=_profile(identity).duplicate(true)
	if not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():return {"ok":false,"error":"Inventory unavailable"}
	var error := Dorm.Backpacks.move(profile.dorm,{"op":"bag_move","bag":bag,"destination":"hotbar" if into_hotbar else "ground","position":point},Dorm.CALCULATORS,true)
	if not error.is_empty():return {"ok":false,"error":error}
	profile.dorm.revision=int(profile.dorm.revision)+1
	if not Dorm.valid(profile.dorm,profile.inventory,profile.get("component_instances",{})):return {"ok":false,"error":"Invalid backpack transfer"}
	return _commit_world_inventory(peer,identity,profile)

func _commit_world_inventory(peer: int, identity: String, updated: Dictionary, deployment: Variant = null) -> Dictionary:
	if game.session.online:
		var ledger: RefCounted=_ledger()
		var next: Dictionary=ledger.state.duplicate(true)
		next.accounts[identity].profile=updated
		if deployment is Dictionary:next.accounts[identity].deployment=deployment
		next.accounts[identity].revision+=1
		if not ledger.persist(next):return {"ok":false,"error":"Could not save supply transfer"}
		game.electronics_trade.authority.send_snapshot(peer,ledger.snapshot(peer))
	else:
		var profile: RefCounted=game.electronics.profile
		var previous: Dictionary=profile.data
		profile.data=updated
		if profile.save()!=OK:
			profile.data=previous
			return {"ok":false,"error":"Could not save supply transfer"}
	return {"ok":true}

func _bind_computers() -> void:
	if not is_instance_valid(game.get("computers")):return
	for contract in hall.room_contracts:
		var bay: String=contract.dorm_id
		var station := "personal_"+bay
		if not computer_stations.has(bay):
			var outward := -1.0 if contract.side=="west" else 1.0
			var point: Vector3=contract.center+Vector3(-outward*1.65,0,-.95)
			var chair: int=game.chairs.size();game._add_chair(point)
			game.chairs[chair].fixed_seat=true
			game.chairs[chair].set_physics_process(false)
			_hide_chair_visuals(game.chairs[chair])
			# The streamed furnishing owns the visible chair's collision and prompt.
			game.chairs[chair].collision_layer=0
			for child in game.chairs[chair].get_children():
				if child is StaticBody3D:child.collision_layer=0
			if not game.computers.register_station(station,chair,point+Vector3(0,0,-1.6)):continue
			computer_stations[bay]=station
		var room := str(leases.get(bay,""))
		var owner := ""
		if interiors.has(room):
			var furnished: Node3D=interiors[room].room
			var has_seat: bool=furnished.targets.has("study_chair") and furnished.targets.study_chair.visible
			if has_seat and furnished.targets.has("computer") and furnished.targets.computer.visible:
				owner=owner_identity(room)
				game.computers.stations[station].anchor=furnished.targets.computer.global_position
			if has_seat:
				var index: int=game.computers.stations[station].chair
				var anchor: Vector3=furnished.targets.study_chair.global_position-Vector3(0,.55,0)
				if game.chairs[index].occupant==0 and game.chairs[index].global_position!=anchor:
					game.chairs[index].global_position=anchor
				game.chairs[index].fixed_yaw=furnished.targets.study_chair.global_rotation.y
		game.computers.set_private_owner(station,owner)

func request_personal_computer(room: String) -> bool:
	var identity := authenticated_identity(multiplayer.get_unique_id())
	if not is_owner(identity,room):return false
	var bay := _bay_for(room)
	if not computer_stations.has(bay):return false
	game.computers.request({"op":"enter","station":computer_stations[bay]})
	return true

func _sync_interiors(data: Dictionary) -> void:
	var active: Array=data.get("occupants",{}).values()
	for bay in data.get("open_doors", {}):
		if leases.has(bay):active.append(leases[bay])
	for bay in hall.door_motion:
		if leases.has(bay) and hall.door_motion[bay].is_running() and interiors.has(leases[bay]):
			active.append(leases[bay])
	for room in interiors.keys():
		if room not in active and not _resting_in(room):
			_unregister_bed(room);interiors[room].queue_free();interiors.erase(room);interior_versions.erase(room)
	for entry in data.get("rooms",[]):
		var room: String=entry.room.room_id
		if room not in active:continue
		var allowed: Array = data.get("access", {}).get(room, [])
		var local_identity := authenticated_identity(multiplayer.get_unique_id())
		if not multiplayer.is_server() and local_identity not in allowed:
			if interiors.has(room):
				interiors[room].queue_free()
				interiors.erase(room)
				interior_versions.erase(room)
			continue
		var version := var_to_bytes(entry.room.customization).hex_encode().sha256_text()
		if interiors.has(room) and interior_versions.get(room)==version:continue
		if _resting_in(room):continue
		if interiors.has(room):_unregister_bed(room);interiors[room].queue_free();interiors.erase(room)
		for physical in hall.room_contracts:
			if physical.dorm_id!=entry.bay:continue
			var contract: Dictionary=physical.duplicate(true);contract.dorm_id=room
			var adapter=preload("res://scripts/campus/dorms/integration/room_adapter.gd").new();add_child(adapter)
			adapter.configure(game,self,game.get("computers"))
			var rest := func(_transform: Transform3D):
				if is_instance_valid(game.get("dorm_rest")):game.dorm_rest.request(room)
			var chair := func(_transform: Transform3D):_request_desk_chair(room)
			adapter.bind_personal_actions(_open_wardrobe,rest,chair,func(_room: String):_open_storage())
			# Host-derived access projection controls streaming, never full profiles.
			if allowed.is_empty():adapter.queue_free();continue
			var actor := str(allowed[0]) if multiplayer.is_server() else local_identity
			if not adapter.enter(contract,entry.room,actor):adapter.queue_free();continue
			interiors[room]=adapter;interior_versions[room]=version
			if multiplayer.is_server() and is_instance_valid(game.get("dorm_rest")) and adapter.room.targets.has("bed"):
				var bed: Node3D=adapter.room.targets.bed
				var anchor: Transform3D=bed.global_transform;anchor.origin+=anchor.basis*Vector3(0,.16,.85)
				var center: Vector3=contract.center
				var aisle := Vector3(center.x,center.y,anchor.origin.z)
				game.dorm_rest.state.register_bed(room,anchor,aisle)
			var target := StaticBody3D.new();target.collision_layer=4;target.position=contract.center+Vector3(0,1,2)
			var collision := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(.4,.4,.4);collision.shape=shape;target.add_child(collision);adapter.room.add_child(target)
			target.set_meta("role","dorm_decorate");target.set_meta("room_id",room);target.set_meta("label","Decorate my room")

func _open_wardrobe() -> void:
	var error: String=game.characters.edit(false,true)
	if not error.is_empty():game.ui.log_message(error)

func _open_storage() -> void:
	if not is_instance_valid(cabinet_layer):
		cabinet_layer=CanvasLayer.new();cabinet_layer.layer=46;add_child(cabinet_layer)
	_build_storage()
	game.release_mouse()

func _refresh_storage() -> void:
	if not is_instance_valid(operation_window) or not operation_window.is_visible_in_tree():return
	var revision := int(game.electronics.profile.data.get("dorm",{}).get("revision",-1))
	if revision!=cabinet_revision:_build_storage()

func _build_storage() -> void:
	var previous_scroll := cabinet_scroll.scroll_vertical if is_instance_valid(cabinet_scroll) else 0
	for old in cabinet_layer.get_children():
		cabinet_layer.remove_child(old);old.queue_free()
	var center := CenterContainer.new();cabinet_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter=Control.MOUSE_FILTER_IGNORE
	operation_window=PanelContainer.new()
	operation_window.theme=CabinetTheme.create()
	operation_window.theme_type_variation="CardPanel"
	var viewport_size := get_viewport().get_visible_rect().size
	operation_window.custom_minimum_size=Vector2(minf(760,viewport_size.x-40),minf(610,viewport_size.y-40))
	center.add_child(operation_window)
	var contents := VBoxContainer.new();operation_window.add_child(contents)
	contents.add_theme_constant_override("separation",10)
	contents.add_child(CabinetUI.header("Dorm inventory","",close_storage))
	var p: Dictionary=game.electronics.profile.data
	cabinet_revision=int(p.get("dorm",{}).get("revision",-1))
	contents.add_child(CabinetUI.text("Equipment storage  %d / %d" % [Dorm.storage_used(p.get("dorm",{})),Dorm.CAPACITY],"MutedLabel"))
	var dorm_data: Dictionary=p.get("dorm",{})
	var bags: Dictionary=dorm_data.get("backpacks",{})
	var equipped := Dorm.Backpacks.equipped(dorm_data)
	game.hotbar._sync_dorm_items()
	var total_slots: int=game.hotbar.slots.size()
	var available_slots := 0
	for slot in game.hotbar.slots:
		if slot.is_empty():available_slots+=1
	if not equipped.is_empty():
		var bag: Dictionary=bags[equipped]
		var capacity: int=Dorm.Backpacks.SIZES[bag.size].capacity
		total_slots+=capacity
		available_slots+=capacity-bag.items.size()
	contents.add_child(CabinetUI.text("Your inventory · %d / %d slots free" % [available_slots,total_slots],"MutedLabel"))
	var panels := HBoxContainer.new()
	panels.size_flags_vertical=Control.SIZE_EXPAND_FILL
	panels.add_theme_constant_override("separation",20)
	contents.add_child(panels)
	var carried := _cabinet_column(panels,"Hotbar",false)
	panels.add_child(VSeparator.new())
	var stored := _cabinet_column(panels,"Dorm storage",true)
	for tool in Dorm.supply_counts(dorm_data):
		var item := {"kind":"calculator" if tool in Dorm.CALCULATORS else str(tool),"type":tool}
		var count := Dorm.cabinet_supply_count(dorm_data,tool)
		if tool in dorm_data.get("carry_items",[]):
			_cabinet_tile(carried,str(Dorm.TOOLS[tool]),item,"Store",_cabinet_transfer.bind({"op":"carry_item","item":tool,"carry":false},false))
		for _copy in count:
			_cabinet_tile(stored,str(Dorm.TOOLS[tool]),item,"Move to hotbar",_cabinet_transfer.bind({"op":"carry_item","item":tool,"carry":true},true))
	for id in p.get("kits",{}):
		if p.kits[id].get("workspace_only",false):continue
		if game.kit_world.is_placed(multiplayer.get_unique_id(),str(id)):continue
		var key := "kit:"+str(id)
		var item := {"kind":"kit","id":id}
		var title := str(p.kits[id].get("name","Electrical kit"))
		if key in dorm_data.get("carry_items",[]):
			_cabinet_tile(carried,title,item,"Store",_cabinet_transfer.bind({"op":"carry_item","item":key,"carry":false},false))
		elif not Dorm.Backpacks.has_kit(dorm_data,str(id)):
			_cabinet_tile(stored,title,item,"Move to hotbar",_cabinet_transfer.bind({"op":"carry_item","item":key,"carry":true},true))
	for id in bags:
		var bag: Dictionary=bags[id]
		if bag.location not in ["cabinet","hotbar"]:continue
		var take: bool=bag.location=="cabinet"
		var destination := "hotbar" if take else "cabinet"
		var title := str(Dorm.Backpacks.SIZES[bag.size].name)
		_cabinet_tile(stored if take else carried,title,{"kind":"backpack","type":bag.size},"Move to hotbar" if take else "Store",_cabinet_transfer.bind({"op":"bag_move","bag":id,"destination":destination},take))
	if not equipped.is_empty():
		var left: Control=carried.get_parent()
		var pack := _cabinet_grid(left,"Backpack")
		var entries: Array=bags[equipped].items
		for i in entries.size():
			var entry: Dictionary=entries[i]
			if entry.kind=="component":continue
			var item: Dictionary=game.hotbar._unpack_item(entry)
			if entry.kind=="bag":item.type=bags[entry.id].size
			_cabinet_tile(pack,game.hotbar.title(item),item,"Store",_cabinet_transfer.bind({"op":"bag_unpack","bag":equipped,"slot":i,"destination":"cabinet"},false))
		if pack.get_child_count()==0:pack.add_child(CabinetUI.text("No storable items","MutedLabel"))
	if not dorm_data.get("stored_board",{}).is_empty():
		_cabinet_tile(stored,"Circuit board",{"kind":"board"},"Move to hotbar",_transfer_cabinet_board)
	else:
		for board in game.dc_lab.states:
			if int(board.get("board_owner",0))==multiplayer.get_unique_id() and (board.get("board_stowed",false) or board.get("board_held",false)):
				_cabinet_tile(carried,"Circuit board",{"kind":"board"},"Store",_transfer_cabinet_board)
				break
	if carried.get_child_count()==0:carried.add_child(CabinetUI.text("No storable items","MutedLabel"))
	if stored.get_child_count()==0:stored.add_child(CabinetUI.text("Cabinet is empty","MutedLabel"))
	cabinet_scroll.set_deferred("scroll_vertical",previous_scroll)

func _cabinet_column(parent: Control, heading: String, cabinet: bool) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	if cabinet:cabinet_scroll=scroll
	var column := VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return _cabinet_grid(column,heading)

func _cabinet_grid(parent: Control, heading: String) -> GridContainer:
	parent.add_child(CabinetUI.text(heading,"SubtitleLabel"))
	var grid := GridContainer.new()
	grid.columns=3
	grid.add_theme_constant_override("h_separation",6)
	grid.add_theme_constant_override("v_separation",6)
	parent.add_child(grid)
	return grid

func _cabinet_tile(parent: Control, title: String, item: Dictionary, action: String, transfer: Callable) -> void:
	var tile := Button.new()
	tile.text=title
	game.hotbar.style_inventory_tile(tile,item)
	tile.tooltip_text+=" · "+action
	tile.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.icon=game.hotbar.portraits.texture(item,game.electronics.profile)
	if tile.icon==null:tile.icon=CabinetUI.icon("circuit" if item.kind=="board" else "inventory")
	tile.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
	tile.add_theme_constant_override("icon_max_width",44)
	tile.add_theme_font_size_override("font_size",12)
	tile.custom_minimum_size=Vector2(76,86)
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tile.pressed.connect(transfer)
	parent.add_child(tile)

func _cabinet_transfer(intent: Dictionary, needs_hotbar: bool) -> void:
	if needs_hotbar and {} not in game.hotbar.slots:
		game.ui.log_message("Free a hotbar slot first.")
		return
	if not game.hotbar.stow():return
	intent=intent.duplicate(true)
	intent.revision=int(game.electronics.profile.data.dorm.revision)
	var result := submit_intent(Crypto.new().generate_random_bytes(16).hex_encode(),intent)
	if not result.get("ok",false) and not result.get("pending",false):
		game.ui.log_message(str(result.get("error","Transfer rejected")))

func close_storage() -> bool:
	if not is_instance_valid(operation_window) or not operation_window.is_visible_in_tree():return false
	_dismiss_storage()
	game.capture()
	return true

func _dismiss_storage() -> void:
	if is_instance_valid(cabinet_layer):
		cabinet_layer.hide()
		cabinet_layer.queue_free()
	cabinet_layer=null
	operation_window=null
	cabinet_scroll=null

func component_transfer(type: String, instance: String, op: String, carry := false) -> void:
	var revision := int(game.electronics.profile.data.get("dorm",{}).get("revision",-1))
	var result := submit_intent(Crypto.new().generate_random_bytes(16).hex_encode(),{"op":op,"item":type,"instance":instance,"revision":revision,"carry":carry})
	if not result.get("ok",false) and not result.get("pending",false):
		game.ui.log_message(str(result.get("error","Component transfer rejected")))

func _transfer_cabinet_board() -> void:
	var saved: Dictionary = game.electronics.profile.data.get("dorm",{}).get("stored_board",{})
	var peer := multiplayer.get_unique_id()
	if not saved.is_empty() and {} not in game.hotbar.slots:
		game.ui.log_message("Free a hotbar slot first.")
		return
	for index in game.dc_lab.states.size():
		var board: Dictionary = game.dc_lab.states[index]
		if saved.is_empty() and int(board.get("board_owner",0))==peer:
			if board.get("board_stowed",false) or board.get("board_held",false):
				game.dc_lab.request(index,{"op":"cabinet_board"})
			else:game.ui.log_message("Pick up your board before bringing it to the cabinet.")
			return
		if not saved.is_empty() and board.get("board",{}).is_empty():
			game.dc_lab.request(index,{"op":"retrieve_cabinet_board"})
			return
	game.ui.log_message("Bring an owned circuit board." if saved.is_empty() else "All DC board slots are in use.")

func _open_decorate(room: String) -> void:
	if not is_owner(authenticated_identity(multiplayer.get_unique_id()),room):return
	if not interiors.has(room):return
	if is_instance_valid(decorate):decorate.queue_free()
	var layer := CanvasLayer.new();add_child(layer)
	decorate=preload("res://scripts/campus/dorms/customization/decorate_panel.gd").new();layer.add_child(decorate);decorate_room=room
	var options: Array[Dictionary]=[]
	for id in Dorm.DEFAULTS:options.append({"id":id,"kind":id,"name":id.replace("_"," ")})
	var profile: Dictionary=game.electronics.profile.data
	for type in profile.inventory:
		if int(profile.inventory[type])>0:options.append({"id":"display:"+str(type),"kind":"display","name":"Display "+str(type)})
	decorate.open_room(profile.dorm.customization,options,"west",func(edit: Dictionary) -> Dictionary:
		var result := submit_intent(Crypto.new().generate_random_bytes(16).hex_encode(),{"op":"edit","revision":int(game.electronics.profile.data.dorm.revision),"edit":edit})
		return {} if result.get("pending",false) else result)
	decorate.closed.connect(func():
		if is_instance_valid(preview):preview.queue_free();preview=null
		layer.queue_free();game.capture())
	decorate.preview_changed.connect(_preview_changed)
	game.release_mouse()

func _operation_result(op: String,result: Dictionary) -> void:
	if op!="dorm":return
	if result.get("ok",false) and is_instance_valid(operation_window) and operation_window.visible:_refresh_storage.call_deferred()
	if is_instance_valid(decorate) and decorate.visible:
		var d: Dictionary=result.get("profile",{}).get("dorm",game.electronics.profile.data.get("dorm",{}))
		decorate.accept_result({"ok":result.get("ok",false),"error":result.get("error",""),"state":d.get("customization",{}),"revision":d.get("revision",-1)})
	if multiplayer.is_server():_publish()

func _preview_changed(item: Dictionary,valid: bool) -> void:
	if is_instance_valid(preview):preview.queue_free();preview=null
	if item.is_empty():return
	var bay := _bay_for(decorate_room)
	for contract in hall.room_contracts:
		if contract.dorm_id!=bay:continue
		preview=MeshInstance3D.new();var mesh := BoxMesh.new()
		var rect: Rect2=preload("res://scripts/campus/dorms/customization/placement_rules.gd").footprint(item)
		mesh.size=Vector3(rect.size.x,.4,rect.size.y);preview.mesh=mesh
		var material := StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(0.3,0.8,0.6,.35) if valid else Color(1,.2,.2,.35);preview.material_override=material
		preview.position=contract.center+Vector3(float(item.x)*(1 if contract.side=="west" else -1),.3,float(item.z));hall.add_child(preview)

func _resting_in(room: String) -> bool:
	if not is_instance_valid(game.get("dorm_rest")):return false
	for state in game.dorm_rest.public_states.values():
		if state.room==room:return true
	return false
func _unregister_bed(room: String) -> void:
	if multiplayer.is_server() and is_instance_valid(game.get("dorm_rest")):
		game.dorm_rest.state.beds.erase(room)
		game.dorm_rest.state.exit_aisles.erase(room)
func _request_desk_chair(room: String) -> void:
	var bay := _bay_for(room)
	if computer_stations.has(bay) and is_owner(authenticated_identity(multiplayer.get_unique_id()),room):game._request_chair(int(game.computers.stations[computer_stations[bay]].chair))
func _hide_chair_visuals(node: Node) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:child.hide()
		_hide_chair_visuals(child)

