extends Node3D
const EquipmentFinish=preload("res://scripts/campus/items/equipment_finish.gd")
const EquipmentConfig=preload("res://scripts/campus/items/equipment_configuration.gd")
## Ownership stays in the player's
## hotbar while placed so a session restart cannot destroy the purchase.
const WorkstationDisplay=preload("res://scripts/campus/presentation/decor/computer_rooms/computer_station.gd")
const BASE_BOTTOM:=.0125
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

func place_selected(landing: Dictionary={}) -> bool:
	var id:=selected_id()
	if id.is_empty():return false
	if placed.has(id):game.ui.log_message("Pick up the laptop before placing it again.");return true
	var point: Variant=landing.get("position")
	if point==null:
		var query:=PhysicsRayQueryParameters3D.create(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3.0,5)
		var hit:=_placement_hit(query)
		point=hit.position if hit.has("position") and hit.get("normal",Vector3.ZERO).y>.9 else game.school.ground_drop_position(game.player.global_position,multiplayer.get_unique_id())
	if point==null:game.ui.log_message("No clear flat surface to place the laptop.");return true
	if game.session.online and not multiplayer.is_server():_place_request.rpc_id(1,id,point,game.player.global_rotation.y)
	elif not _place_for(multiplayer.get_unique_id(),id,point,game.player.global_rotation.y):game.ui.log_message("The laptop could not be placed.")
	return true

func _placement_hit(query: PhysicsRayQueryParameters3D) -> Dictionary:
	var space:=get_world_3d().direct_space_state
	var excluded:=query.exclude
	# Seat hitboxes can extend above and in front of the visible seat.
	for index in 12:
		var hit:=space.intersect_ray(query)
		if hit.is_empty():return {}
		var collider: CollisionObject3D=hit.collider
		if collider.get_meta("role","") not in ["chair","facility_seat"] and collider not in game.chairs:
			return hit
		excluded.append(hit.rid)
		query.exclude=excluded
	return {}

func place(id: String,point: Vector3,yaw: float) -> bool:
	return _place_for(multiplayer.get_unique_id(),id,point,yaw)

@rpc("any_peer","call_remote","reliable")
func _place_request(id: String,point: Vector3,yaw: float) -> void:
	if multiplayer.is_server():_place_for(multiplayer.get_remote_sender_id(),id,point,yaw)

func _place_for(peer: int,id: String,point: Vector3,yaw: float) -> bool:
	if not multiplayer.is_server() or not game.session.roster.has(peer) or placed.has(id) or not point.is_finite() or not is_finite(yaw):return false
	var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not position.is_finite() or (point.distance_to(position)>3.2 and not game.school.is_throw_landing(peer,point)):return false
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	var dorm: Dictionary=game.dorm_interactions._profile(identity).get("dorm",{})
	var item: Dictionary=dorm.get("portable_laptops",{}).get(id,{})
	if item.get("location","")!="hotbar" or "laptop:"+id not in dorm.get("carry_items",[]):return false
	if game.session.online:
		var surface:=_placement_hit(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.04,point-Vector3.UP*.04,5))
		if surface.is_empty() or surface.normal.y<.9:return false
		point=surface.position
	var station:=id
	var configuration: Dictionary=item.get("configuration",{})
	if not game.computers.register_portable(station,point,str(dorm.owner),str(item.tier),configuration):return false
	_spawn(id,point,yaw,peer,identity,str(item.tier),false,configuration)
	_publish()
	return true

func _spawn(id: String,point: Vector3,yaw: float,owner_peer: int,owner: String,tier: String,opened: bool,configuration: Dictionary={}) -> void:
	var station:=id
	var model:=WorkstationDisplay.new()
	model.set_meta("portable",true)
	model.position=point-Vector3.UP*BASE_BOTTOM
	model.rotation.y=yaw
	add_child(model)
	game.ac_laptops._build_laptop(model,-1)
	EquipmentFinish.apply_finish(model,EquipmentConfig.LAPTOP,configuration)
	EquipmentFinish.set_backlight_power(model,false)
	model.set_meta("display_scale",EquipmentConfig.value(EquipmentConfig.LAPTOP,configuration,"hardware","display",1.0))
	for body in model.find_children("*","StaticBody3D",true,false):
		if body.get_meta("role","")=="ac_laptop":
			body.set_meta("role","portable_laptop")
			body.set_meta("label","Laptop")
			if body.get_parent()==model:
				var shape: BoxShape3D=body.get_child(0).shape
				shape.size.y=.055
		elif body.get_meta("role","")=="ac_laptop_usb":
			body.set_meta("role","public_computer_usb")
			body.set_meta("label","Connect or remove USB drive")
			var usb_hit: CollisionShape3D=body.get_child(0)
			var usb_shape: BoxShape3D=usb_hit.shape
			usb_shape.size.x=.100
			usb_hit.position.x=.025
			game.computer_room_adapter.mount_usb_visual(body,station,Vector3(.015,0,0),PI*.5)
		body.set_meta("station",station);body.set_meta("portable_id",id)
	var power: StaticBody3D=game.ac_laptops._target(model,"public_computer_power",-1,Vector3(-.177,.067,.109),Vector3(.050,.025,.044))
	power.set_meta("station",station)
	power.set_meta("portable_id",id)
	power.set_meta("label","Turn on laptop")
	model.set_meta("power_target",power)
	game.device_charging.add_port(model,"laptop:"+id,owner_peer,Vector3(-.232,.031,.009),Vector3(.041,.046,.069))
	game.ac_laptops._box(power,Vector3(0,-.008,0),Vector3(.037,.008,.028),Color("24353e"))
	model.power_led=game.ac_laptops._box(power,Vector3(0,-.003,0),Vector3(.016,.002,.005),Color("1a252b"))
	var led_material:=StandardMaterial3D.new()
	led_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	model.power_led.material_override=led_material

	var quad:=QuadMesh.new()
	quad.size=Vector2(.380,.184)
	model.screen=MeshInstance3D.new()
	model.screen.mesh=quad
	model.screen.position=Vector3(0,.13,.020)
	model.screen.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var display_material:=StandardMaterial3D.new()
	display_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	model.screen.material_override=display_material
	model.get_node("Lid").add_child(model.screen)
	placed[id]={"model":model,"station":station,"open":opened,"peer":owner_peer,"owner":owner,"tier":tier,"position":point,"yaw":yaw,"configuration":configuration}
	_set_lid(placed[id],opened)
	if game.computers.stations.has(id):
		game.computers.stations[id].speaker_position=model.to_global(Vector3(0,.064,.07))
		game.computers.stations[id].preview_position=model.screen.global_position
	game.computer_room_adapter.mount_portable_display(id,model)

func _set_lid(entry: Dictionary, opened: bool) -> void:
	entry.open=opened
	entry.model.get_node("Lid").rotation.x=0 if opened else PI/2
	var power: StaticBody3D=entry.model.get_meta("power_target")
	power.visible=opened
	power.collision_layer=4 if opened else 0

func interact(target: Object,right: bool,interact_key := false) -> bool:
	if not is_instance_valid(target):return false
	var id:=str(target.get_meta("portable_id",""))
	if not placed.has(id):return false
	var role:=str(target.get_meta("role",""))
	if role in ["public_computer_usb","public_computer_power"]:
		if not right:game.computer_room_adapter.interact(target)
		return true
	if role!="portable_laptop":return false
	var entry: Dictionary=placed[id]
	if right or interact_key:
		if entry.open:game.computers.request({"op":"enter","station":entry.station})
		else:_request_change(id,"open")
	elif entry.open:_request_change(id,"close")
	else:_request_change(id,"pickup")
	return true

func hint(target: Object, key: String) -> String:
	var id:=str(target.get_meta("portable_id",""))
	var entry: Dictionary=placed.get(id,{})
	if entry.is_empty():return ""
	if entry.open:
		if not game.computer_room_adapter.power_states.get(entry.station,false):
			return "Click laptop power button to turn it on  •  Left-click: close lid"
		return "%s / Right-click: use laptop  •  Left-click: close lid"%key
	return "%s / Right-click: open laptop  •  Left-click: pick up"%key

func _request_change(id: String,op: String) -> void:
	if op=="pickup" and not game.hotbar.slots.has({}):
		game.ui.log_message("Free a hotbar slot first.")
		return
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
	_set_lid(entry,op=="open")
	_publish();return true

func pickup(id: String) -> bool:
	if not placed.has(id):return false
	var entry: Dictionary=placed[id]
	if entry.open:return false
	if not game.computers.unregister_portable(entry.station):
		game.computers._error(entry.peer,"Remove the USB drive before picking up the laptop.");return false
	game.device_charging.disconnect_placement(entry.peer,"laptop:"+entry.station)
	entry.model.queue_free();placed.erase(id)
	if int(entry.peer)==multiplayer.get_unique_id():game.hotbar._sync_dorm_items()
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
		state[id]={"position":entry.position,"yaw":entry.yaw,"peer":entry.peer,"owner":entry.owner,"tier":entry.tier,"open":entry.open,"configuration":entry.get("configuration",{})}
	_receive.rpc(state)

@rpc("authority","call_remote","reliable")
func _receive(state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()!=1 or state.size()>64:return
	for id in placed.keys():
		if not state.has(id):placed[id].model.queue_free();placed.erase(id)
	for id in state:
		var entry: Dictionary=state[id]
		if not placed.has(id):_spawn(id,entry.position,entry.yaw,entry.peer,entry.owner,entry.tier,entry.open,entry.get("configuration",{}))
		else:_set_lid(placed[id],entry.open)

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
