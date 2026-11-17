extends Node3D
## Ownership stays in the player's
## hotbar while placed so a session restart cannot destroy the purchase.
var game: Node
var placed := {}
var held_visual: Node3D

func build(owner_game: Node) -> void:
	game=owner_game
	held_visual=Node3D.new()
	game.camera.add_child(held_visual)
	held_visual.position=Vector3(.3,-.35,-.65)
	game.ac_laptops._closed_laptop(held_visual)
	held_visual.hide()
	game.session.leaving.connect(_reset)
	game.session.restarted.connect(_reset)
	game.session.roster_changed.connect(_roster_changed)
	call_deferred("_bind_inventory")

func _bind_inventory() -> void:
	game.electronics_trade.authority.profile_ready.connect(_profile_ready)

func selected_id() -> String:
	var active: int=game.hotbar.active
	if active not in range(game.hotbar.slots.size()):return ""
	var slot: Dictionary=game.hotbar.slots[active]
	return str(slot.get("id","")) if slot.get("kind","")=="portable_laptop" else ""

func _process(_delta: float) -> void:
	var id:=selected_id()
	held_visual.visible=not id.is_empty() and not placed.has(id) and game.player.enabled and game.front.in_game

func place_selected() -> bool:
	var id:=selected_id()
	if id.is_empty():return false
	if placed.has(id):game.ui.log_message("Pick up the laptop before placing it again.");return true
	var query:=PhysicsRayQueryParameters3D.create(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3.0,5)
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	var point: Variant=null
	if hit.has("position") and hit.get("normal",Vector3.ZERO).y>.9:point=hit.position
	else:point=game.school.ground_drop_position(game.player.global_position, multiplayer.get_unique_id())
	if point==null:game.ui.log_message("No clear flat surface to place the laptop.");return true
	if game.session.online and not multiplayer.is_server():_place_request.rpc_id(1,id,point,game.player.global_rotation.y)
	elif not _place_for(multiplayer.get_unique_id(),id,point,game.player.global_rotation.y):game.ui.log_message("The laptop could not be placed.")
	return true

func place(id: String,point: Vector3,yaw: float) -> bool:
	return _place_for(multiplayer.get_unique_id(),id,point,yaw)

@rpc("any_peer","call_remote","reliable")
func _place_request(id: String,point: Vector3,yaw: float) -> void:
	if multiplayer.is_server():_place_for(multiplayer.get_remote_sender_id(),id,point,yaw)

func _place_for(peer: int,id: String,point: Vector3,yaw: float) -> bool:
	if not multiplayer.is_server() or not game.session.roster.has(peer) or placed.has(id) or not point.is_finite() or not is_finite(yaw):return false
	var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not position.is_finite() or point.distance_to(position)>3.2:return false
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	var dorm: Dictionary=game.dorm_interactions._profile(identity).get("dorm",{})
	var item: Dictionary=dorm.get("portable_laptops",{}).get(id,{})
	if item.get("location","")!="hotbar" or "laptop:"+id not in dorm.get("carry_items",[]):return false
	if game.session.online:
		var surface:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.12,point-Vector3.UP*.2,5))
		if surface.is_empty() or surface.normal.y<.9:return false
		point=surface.position
	var station:=id
	if not game.computers.register_portable(station,point,str(dorm.owner),str(item.tier)):return false
	_spawn(id,point,yaw,peer,identity,str(item.tier),false)
	_publish()
	return true

func _spawn(id: String,point: Vector3,yaw: float,owner_peer: int,owner: String,tier: String,opened: bool) -> void:
	var station:=id
	var model:=Node3D.new();model.position=point;model.rotation.y=yaw;add_child(model)
	game.ac_laptops._build_laptop(model,-1)
	for body in model.find_children("*","StaticBody3D",true,false):
		if body.get_meta("role","")=="ac_laptop":body.set_meta("role","portable_laptop")
		elif body.get_meta("role","")=="ac_laptop_usb":body.set_meta("role","public_computer_usb")
		body.set_meta("station",station);body.set_meta("portable_id",id)
	var power:=StaticBody3D.new();power.position=Vector3(-.18,.075,.09);power.collision_layer=4;power.collision_mask=0
	power.set_meta("role","public_computer_power");power.set_meta("station",station);power.set_meta("portable_id",id);model.add_child(power)
	var shape:=BoxShape3D.new();shape.size=Vector3(.065,.05,.065)
	var hit:=CollisionShape3D.new();hit.shape=shape;power.add_child(hit)
	game.ac_laptops._box(power,Vector3.ZERO,Vector3(.035,.012,.035),Color("8dd8be"))
	placed[id]={"model":model,"station":station,"open":opened,"peer":owner_peer,"owner":owner,"tier":tier,"position":point,"yaw":yaw}
	model.get_node("Lid").rotation.x=0 if opened else PI/2

func interact(target: Object,right: bool) -> bool:
	if not is_instance_valid(target):return false
	var id:=str(target.get_meta("portable_id",""))
	if not placed.has(id):return false
	var role:=str(target.get_meta("role",""))
	if role in ["public_computer_usb","public_computer_power"]:
		if not right:game.computer_room_adapter.interact(target)
		return true
	if role!="portable_laptop":return false
	var entry: Dictionary=placed[id]
	if right:
		if entry.open:game.computers.request({"op":"enter","station":entry.station})
		else:_request_change(id,"open")
	elif entry.open:_request_change(id,"close")
	else:_request_change(id,"pickup")
	return true

func _request_change(id: String,op: String) -> void:
	if game.session.online and not multiplayer.is_server():_change_request.rpc_id(1,id,op)
	else:_change_for(multiplayer.get_unique_id(),id,op)

@rpc("any_peer","call_remote","reliable")
func _change_request(id: String,op: String) -> void:
	if multiplayer.is_server():_change_for(multiplayer.get_remote_sender_id(),id,op)

func _change_for(peer: int,id: String,op: String) -> bool:
	if not placed.has(id) or not game.session.roster.has(peer):return false
	var entry: Dictionary=placed[id]
	if int(entry.peer)!=peer or game.dorm_interactions.authenticated_identity(peer)!=entry.owner:return false
	var pos: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not pos.is_finite() or pos.distance_to(entry.position)>3:return false
	if op=="pickup":return pickup(id)
	if op not in ["open","close"]:return false
	entry.open=op=="open";entry.model.get_node("Lid").rotation.x=0 if entry.open else PI/2
	_publish();return true

func pickup(id: String) -> bool:
	if not placed.has(id):return false
	var entry: Dictionary=placed[id]
	if not game.computers.unregister_portable(entry.station):
		game.ui.log_message("Turn off the laptop and remove its USB before picking it up.");return false
	entry.model.queue_free();placed.erase(id)
	_publish()
	return true

func blocks_dorm_transfer(peer: int,intent: Dictionary) -> bool:
	var key:=str(intent.get("item",""))
	return key.begins_with("laptop:") and placed.has(key.trim_prefix("laptop:")) and int(placed[key.trim_prefix("laptop:")].peer)==peer

func _publish() -> void:
	if not game.session.online or not multiplayer.is_server():return
	var state:={}
	for id in placed:
		var entry: Dictionary=placed[id]
		state[id]={"position":entry.position,"yaw":entry.yaw,"peer":entry.peer,"owner":entry.owner,"tier":entry.tier,"open":entry.open}
	_receive.rpc(state)

@rpc("authority","call_remote","reliable")
func _receive(state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()!=1 or state.size()>64:return
	for id in placed.keys():
		if not state.has(id):placed[id].model.queue_free();placed.erase(id)
	for id in state:
		var entry: Dictionary=state[id]
		if not placed.has(id):_spawn(id,entry.position,entry.yaw,entry.peer,entry.owner,entry.tier,entry.open)
		else:
			placed[id].open=entry.open
			placed[id].model.get_node("Lid").rotation.x=0 if entry.open else PI/2

func _profile_ready(_peer: int) -> void:
	_publish()

func _roster_changed() -> void:
	if not multiplayer.is_server():return
	call_deferred("_remove_disconnected")

func _remove_disconnected() -> void:
	if not multiplayer.is_server() or not is_instance_valid(game.electronics_trade):return
	game.computers._prune()
	for id in placed.keys():
		var entry: Dictionary=placed[id]
		if game.session.roster.has(entry.peer):continue
		if game.computers.stations.has(id):
			game.computers._power_off(id)
			if not game.computers.stations[id].power.usb.is_empty():continue
			game.computers.stations.erase(id)
		entry.model.queue_free();placed.erase(id)
	_publish()

func _reset() -> void:
	for id in placed.keys():
		var entry: Dictionary=placed[id]
		if game.computers.stations.has(entry.station):
			game.computers._power_off(entry.station)
			# Keep the station reachable if the USB recovery save failed.
			if not game.computers.stations[entry.station].power.usb.is_empty():continue
			game.computers.stations.erase(entry.station)
		entry.model.queue_free()
		placed.erase(id)
