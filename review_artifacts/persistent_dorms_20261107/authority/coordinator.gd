extends Node
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Router=preload("res://scripts/campus/dorms/interactions/personal_station_router.gd")
var game: Node
var hall: Node3D
var router: Node
var snapshot := {}
var epoch := 0
var sequence := 0
var leases := {}
var occupants := {}
var sequences := {}
var clock := 0.0
var ledger_id := 0
var directory: Window
var operation_window: Window
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
	for room in hall.room_contracts:
		for kind in ["kit_workshop","loadout","notes"]:
			var target := StaticBody3D.new();target.collision_layer=4;target.collision_mask=0
			target.position=room.workshop_anchor+Vector3(0,1,0) if kind=="kit_workshop" else room.loadout_notes_anchor+Vector3(0,1,-.35 if kind=="notes" else .35)
			var collision := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(.6,.6,.6);collision.shape=shape;target.add_child(collision);hall.add_child(target)
			target.set_meta("physical_bay",str(room.dorm_id))
			router.register_station(target,str(room.dorm_id),kind)
	game.session.restarted.connect(_restart)
	game.session.leaving.connect(_restart)
	game.session.roster_changed.connect(_reconcile)
	game.electronics_trade.authority.profile_ready.connect(func(_peer: int):_reconcile())
	game.electronics_trade.authority.operation_result.connect(_operation_result)
	var target := StaticBody3D.new();target.collision_layer=4;target.position=Vector3(13,1,69)
	var shape := BoxShape3D.new();shape.size=Vector3(1,1,.3)
	var collision := CollisionShape3D.new();collision.shape=shape;target.add_child(collision);hall.add_child(target);target.set_meta("role","dorm_directory")
	var label := Label3D.new();label.text="Dorm directory · Locate my room";label.position=Vector3(13,2,69);hall.add_child(label)
	_restart()
	if game.has_method("install_dorm_rest"):game.install_dorm_rest(self)
func _ledger():
	return game.electronics_trade.authority.ledger
func _restart() -> void:
	epoch+=1;sequence=0;snapshot={};leases.clear();occupants.clear();sequences.clear()
	for adapter in interiors.values():adapter.queue_free()
	interiors.clear();interior_versions.clear()
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
	return not owner.is_empty() and Dorm.may_enter(_profile(owner).get("dorm",{}),owner,identity)
func room_for_peer(peer: int) -> String:
	var identity := authenticated_identity(peer)
	if not multiplayer.is_server():return "dorm_"+identity if not identity.is_empty() else ""
	return str(_profile(identity).get("dorm",{}).get("room_id","")) if not identity.is_empty() else ""
func assignment_revision() -> int:return int(snapshot.get("revision",0))
func locate_room(peer: int) -> Dictionary:
	var room := room_for_peer(peer)
	return {"room_id":room,"number":_profile(authenticated_identity(peer)).get("dorm",{}).get("number",""),"entrance":_bay_for(room),"directory":Vector3(13,0,69)}
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
		if not occupants.values().has(leases[bay]):leases[bay]=room;return bay
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
		if leases[bay] not in desired and leases[bay] not in occupants.values():leases.erase(bay)
	for peer in game.session.roster:
		var room := room_for_peer(int(peer))
		if not room.is_empty():_lease(room)
	_publish()
func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	_bind_computers()
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
	# A physically open door cannot confer access. Recheck authorization against
	# host poses, including tailgating and policy changes while visitors are inside.
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
	var data := {"schema":2,"epoch":epoch,"revision":int(snapshot.get("revision",0))+1,"rooms":rooms,"directory":listing,"identities":identities,"access":access,"occupants":occupants.duplicate(true)}
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
		if hall.door_targets.has(entry.bay):hall.door_targets[entry.bay].set_meta("label","Enter "+str(entry.room.number))
	for target in hall.get_children():
		if target.has_meta("physical_bay"):
			var bay: String=target.get_meta("physical_bay")
			router.register_station(target,str(leases.get(bay,"")),str(target.get_meta("station_kind","")))
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
	if target.get_meta("role","")=="dorm_directory":_show_directory();return true
	if target.get_meta("role","")!="dorm_door":return false
	var room: String=str(leases.get(str(target.get_meta("dorm_id","")),""))
	sequence+=1
	var action := {"op":"enter","room":room,"epoch":snapshot.get("epoch",-1),"sequence":sequence}
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
	var bay := _bay_for(room)
	if not hall.door_targets.has(bay) or pos.distance_to(hall.door_targets[bay].global_position)>3:return
	occupants[peer]=room
	for contract in hall.room_contracts:
		if contract.dorm_id==bay:
			var inside := AABB(contract.bounds_min,contract.bounds_max-contract.bounds_min).has_point(pos)
			var destination: Vector3=contract.door+Vector3(1 if contract.side=="west" else -1,0,0) if inside else contract.entry_anchor
			if inside:occupants.erase(peer)
			if peer==1:_arrive(destination)
			else:_arrive.rpc_id(peer,destination)
@rpc("authority","call_remote","reliable",7)
func _arrive(point: Vector3) -> void:
	game.player.global_position=point+Vector3(0,.15,0)
func _show_directory() -> void:
	if is_instance_valid(directory):directory.queue_free()
	directory=Window.new();directory.title="Profile · My dorm";directory.size=Vector2i(580,400);add_child(directory)
	var box := VBoxContainer.new();directory.add_child(box)
	var mine := Label.new();mine.text="My room: "+str(game.electronics.profile.data.get("dorm",{}).get("number","Waiting for profile enrollment"));box.add_child(mine)
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
		var button := Button.new();button.text=str(entry.number)+" · "+_bay_for(room);box.add_child(button)
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
	var applied: Dictionary=Dorm.apply_intent(profile.data,game.school.local_identity,intent,reservations)
	if not applied.ok:return applied
	var before: Dictionary=profile.data
	profile.data=applied.profile
	profile.data.dorm_receipts=receipts.duplicate(true);profile.data.dorm_receipts[operation_id]=digest
	if profile.save()!=OK:profile.data=before;return {"ok":false,"error":"Save failed; unchanged"}
	_reconcile()
	if is_instance_valid(operation_window) and operation_window.visible:_open_storage.call_deferred()
	return {"ok":true,"state":profile.data.dorm.customization,"revision":profile.data.dorm.revision}

func storage_transfer(identity: String,room: String,operation_id: String,item: String,quantity: int,into_storage: bool,instances: Array=[]) -> Dictionary:
	if identity!=authenticated_identity(multiplayer.get_unique_id()) or not is_owner(identity,room):return {"ok":false,"error":"Owner required"}
	if quantity<=0:return {"ok":false,"error":"Invalid quantity"}
	var d: Dictionary=game.electronics.profile.data.get("dorm",{})
	return submit_intent(operation_id,{"op":"storage","revision":int(d.get("revision",-1)),"item":item,"delta":quantity if into_storage else -quantity,"instances":instances})

func _bind_computers() -> void:
	if not is_instance_valid(game.get("computers")):return
	for contract in hall.room_contracts:
		var bay: String=contract.dorm_id
		var station := "personal_"+bay
		if not computer_stations.has(bay):
			var outward := -1.0 if contract.side=="west" else 1.0
			var point: Vector3=contract.center+Vector3(-outward*1.65,0,-.95)
			var chair: int=game.chairs.size();game._add_chair(point)
			game.chairs[chair].set_physics_process(false)
			_hide_chair_visuals(game.chairs[chair])
			if not game.computers.register_station(station,chair,point+Vector3(0,0,-1.6)):continue
			computer_stations[bay]=station
		var room := str(leases.get(bay,""))
		var owner := ""
		if interiors.has(room):
			var furnished: Node3D=interiors[room].room
			if furnished.targets.has("computer") and furnished.targets.computer.visible:
				owner=owner_identity(room)
				game.computers.stations[station].anchor=furnished.targets.computer.global_position
			if furnished.targets.has("study_chair") and furnished.targets.study_chair.visible:
				var index: int=game.computers.stations[station].chair
				if game.chairs[index].occupant==0:game.chairs[index].global_position=furnished.targets.study_chair.global_position-Vector3(0,.55,0)
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
	for room in interiors.keys():
		if room not in active and not _resting_in(room):
			_unregister_bed(room);interiors[room].queue_free();interiors.erase(room);interior_versions.erase(room)
	for entry in data.get("rooms",[]):
		var room: String=entry.room.room_id
		if room not in active:continue
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
			var allowed: Array=data.get("access",{}).get(room,[])
			if allowed.is_empty():adapter.queue_free();continue
			if not adapter.enter(contract,entry.room,str(allowed[0])):adapter.queue_free();continue
			interiors[room]=adapter;interior_versions[room]=version
			if multiplayer.is_server() and is_instance_valid(game.get("dorm_rest")) and adapter.room.targets.has("bed"):
				var bed: Node3D=adapter.room.targets.bed
				var anchor: Transform3D=bed.global_transform;anchor.origin+=anchor.basis*Vector3(0,.16,.85)
				game.dorm_rest.state.register_bed(room,anchor)
			var target := StaticBody3D.new();target.collision_layer=4;target.position=contract.center+Vector3(0,1,2)
			var collision := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(.4,.4,.4);collision.shape=shape;target.add_child(collision);adapter.room.add_child(target)
			target.set_meta("role","dorm_decorate");target.set_meta("room_id",room);target.set_meta("label","Decorate my room")

func _open_wardrobe() -> void:
	var panel=game.campus_services.get("clothing_panel") if is_instance_valid(game.get("campus_services")) else null
	if not is_instance_valid(panel):return
	var profile=game.electronics.profile
	game.release_mouse();panel.show();panel.open_profile(profile.data,null,profile.get_meta("economy_display",{}))

func _open_storage() -> void:
	if is_instance_valid(operation_window):operation_window.queue_free()
	operation_window=Window.new();operation_window.title="Personal storage";operation_window.size=Vector2i(520,480);add_child(operation_window)
	var scroll := ScrollContainer.new();scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);operation_window.add_child(scroll)
	var box := VBoxContainer.new();scroll.add_child(box)
	var p: Dictionary=game.electronics.profile.data
	for type in p.get("inventory",{}):
		var row := HBoxContainer.new();box.add_child(row)
		var label := Label.new();label.text=str(type)+" · stored "+str(p.get("dorm",{}).get("storage",{}).get(type,0));row.add_child(label)
		for delta in [1,-1]:
			var button := Button.new();button.text="Store one" if delta==1 else "Retrieve one";row.add_child(button)
			button.pressed.connect(func():
				var identity := authenticated_identity(multiplayer.get_unique_id())
				var result := storage_transfer(identity,"dorm_"+identity,Crypto.new().generate_random_bytes(16).hex_encode(),str(type),1,delta==1)
				if not result.get("ok",false) and not result.get("pending",false):game.ui.log_message(str(result.get("error","Storage rejected"))))
	for instance in p.get("component_instances",{}):
		var item: Dictionary=p.component_instances[instance]
		var button := Button.new();var stored: bool=instance in p.get("dorm",{}).get("instances",[])
		button.text=("Retrieve " if stored else "Store ")+str(item.type)+" · "+str(instance);box.add_child(button)
		button.pressed.connect(func():
			var identity := authenticated_identity(multiplayer.get_unique_id())
			var result := storage_transfer(identity,"dorm_"+identity,Crypto.new().generate_random_bytes(16).hex_encode(),str(item.type),1,not stored,[instance])
			if not result.get("ok",false) and not result.get("pending",false):game.ui.log_message(str(result.get("error","Storage rejected"))))
	operation_window.close_requested.connect(func():operation_window.hide();game.capture())
	game.release_mouse();operation_window.popup_centered()

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
	if result.get("ok",false) and is_instance_valid(operation_window) and operation_window.visible:_open_storage.call_deferred()
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
	if multiplayer.is_server() and is_instance_valid(game.get("dorm_rest")):game.dorm_rest.state.beds.erase(room)
func _request_desk_chair(room: String) -> void:
	var bay := _bay_for(room)
	if computer_stations.has(bay) and is_owner(authenticated_identity(multiplayer.get_unique_id()),room):game._request_chair(int(game.computers.stations[computer_stations[bay]].chair))
func _hide_chair_visuals(node: Node) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:child.hide()
		_hide_chair_visuals(child)

