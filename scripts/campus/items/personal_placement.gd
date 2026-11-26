extends Node3D

const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Phones=preload("res://scripts/campus/phones/phone_tiers.gd")
const Configuration=preload("res://scripts/campus/items/equipment_configuration.gd")
const Handset=preload("res://scripts/campus/phones/phone_handset.gd")
const EquipmentFinish=preload("res://scripts/campus/items/equipment_finish.gd")
var game: Node
var placed: Dictionary={}
var models: Dictionary={}

func build(owner: Node) -> void:
	game=owner
	game.session.leaving.connect(_clear)
	game.session.restarted.connect(_clear)
	game.session.roster_changed.connect(_prune)
	call_deferred("_bind_inventory")

func _bind_inventory() -> void:
	game.electronics_trade.authority.profile_ready.connect(func(_peer):_publish())

func is_placed(peer: int,key: String) -> bool:
	return placed.has(key_for(peer,key))

func key_for(peer: int,key: String) -> String:
	return "%d:%s"%[peer,key]

func place_selected(surface: Dictionary) -> bool:
	var slot: int=game.hotbar.active
	if slot not in range(game.hotbar.slots.size()):return false
	var item: Dictionary=game.hotbar.slots[slot]
	var key:=str(item.get("dorm_item",""))
	if item.get("kind","")=="component":
		key="part:%s:%s:%d"%[item.type,item.instance,item.ordinal]
	if key.is_empty() or key.begins_with("kit:") or key.begins_with("laptop:"):return false
	if surface.is_empty():
		game.ui.log_message("Aim at a clear table or floor.")
		return true
	var yaw: float=game.player.global_rotation.y
	if multiplayer.is_server():_place(multiplayer.get_unique_id(),key,surface.position,yaw)
	else:_place_request.rpc_id(1,key,surface.position,yaw)
	return true

@rpc("any_peer","call_remote","reliable")
func _place_request(key: String, point: Vector3, yaw: float) -> void:
	if multiplayer.is_server():_place(multiplayer.get_remote_sender_id(),key,point,yaw)

func _place(peer: int,key: String,point: Vector3,yaw: float) -> void:
	if not game.session.roster.has(peer) or key.length()>160 or placed.size()>=48 or is_placed(peer,key) or not point.is_finite() or not is_finite(yaw):return
	var actor: Vector3=_actor(peer)
	if actor.distance_to(point)>3.0:return
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	if identity.is_empty():return
	var profile: Dictionary=game.dorm_interactions._profile(identity)
	var dorm: Dictionary=profile.get("dorm",{})
	var label:=_carried_label(peer,key,dorm)
	if label.is_empty():return
	var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.04,point-Vector3.UP*.06,5)
	var hit: Dictionary=game.portable_laptops._placement_hit(ray)
	if hit.is_empty() or hit.normal.y<.8 or hit.collider.get_meta("role","") in ["portable_laptop","discarded_item","placed_personal_item"]:
		game.discarded_items._notice(peer,"Aim at a clear table or floor.")
		return
	var resting: Vector3=hit.position
	if placed.values().any(func(item):return resting.distance_squared_to(item.position)<.01):
		game.discarded_items._notice(peer,"There is already an item in that spot.")
		return
	var visual:=key
	if key.begins_with("part:"):visual="component:"+key.get_slice(":",1)
	elif key.begins_with("bag:"):visual="bag_"+str(dorm.get("backpacks",{}).get(key.trim_prefix("bag:"),{}).get("size","backpack_small"))
	elif Dorm.is_notebook(key):visual="notebook"
	elif Dorm.is_calculator(key):visual=Dorm.Keypad.model_for(key)
	placed[key_for(peer,key)]={"key":key,"peer":peer,"position":resting,"yaw":yaw,"label":label,"visual":visual}
	if key.begins_with("phone:"):
		var appearance:=Configuration.phone_appearance(dorm.smartphones[key.trim_prefix("phone:")])
		if not appearance.is_empty():placed[key_for(peer,key)].appearance=appearance
	elif key.begins_with("usb:"):
		var configuration: Dictionary=dorm.usb_drives[key.trim_prefix("usb:")].get("configuration",{})
		if not configuration.is_empty():placed[key_for(peer,key)].configuration=configuration
	elif Dorm.is_notebook(key) or Dorm.is_calculator(key):
		var configuration:=Dorm.supply_configuration(dorm,key)
		if not configuration.is_empty():placed[key_for(peer,key)].configuration=configuration
	elif key.begins_with("bag:"):
		var configuration: Dictionary=dorm.backpacks[key.trim_prefix("bag:")].get("configuration",{})
		if not configuration.is_empty():placed[key_for(peer,key)].configuration=configuration
	_sync_models()
	_publish()

func _carried_label(peer: int,key: String,dorm: Dictionary) -> String:
	if key.begins_with("part:"):
		var part:=key.split(":")
		if part.size()!=4 or not part[3].is_valid_int() or int(part[3])<1:return ""
		var matching: int=dorm.get("carried_components",[]).count({"type":part[1],"instance":part[2]})
		return "Component" if matching>=int(part[3]) else ""
	if key not in dorm.get("carry_items",[]):return ""
	if key.begins_with("usb:"):
		return str(dorm.get("usb_drives",{}).get(key.trim_prefix("usb:"),{}).get("name","")).left(64)
	if key.begins_with("phone:"):
		var id:=key.trim_prefix("phone:")
		if id==game.smartphones.handed_phone_id and peer==multiplayer.get_unique_id():return ""
		if id==str(dorm.get("teacher_phone_custody",{}).get("id","")):return ""
		return str(Phones.TIERS.get(dorm.get("smartphones",{}).get(id,{}).get("tier",""),{}).get("name","Phone"))
	if key.begins_with("bag:"):return "Backpack"
	return Dorm.supply_title(key) if Dorm.is_supply(key) else ""

func interact(target: Object, use: bool) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","")!="placed_personal_item":return false
	var id:=str(target.get_meta("placement_id",""))
	var entry: Dictionary=placed.get(id,{})
	if entry.get("peer",0)!=multiplayer.get_unique_id() or _actor(multiplayer.get_unique_id()).distance_to(entry.position)>3.0:return true
	if use and str(entry.key).begins_with("phone:"):
		game.smartphones.open_placed(str(entry.key).trim_prefix("phone:"))
		return true
	if not game.hotbar.slots.has({}):
		game.ui.log_message("Free a hotbar slot first.")
		return true
	if multiplayer.is_server():_pickup(multiplayer.get_unique_id(),id)
	else:_pickup_request.rpc_id(1,id)
	return true

func hint(target: Object,interact_key: String) -> String:
	var entry: Dictionary=placed.get(str(target.get_meta("placement_id","")),{})
	if entry.is_empty():return ""
	if int(entry.peer)!=multiplayer.get_unique_id():return str(entry.label)
	if str(entry.key).begins_with("phone:"):return "%s / Right-click: use phone  •  Left-click: pick up"%interact_key
	return "%s / Click: pick up %s"%[interact_key,entry.label]

@rpc("any_peer","call_remote","reliable")
func _pickup_request(id: String) -> void:
	if multiplayer.is_server():_pickup(multiplayer.get_remote_sender_id(),id)

func _pickup(peer: int,id: String) -> void:
	var entry: Dictionary=placed.get(id,{})
	if entry.get("peer",0)!=peer or _actor(peer).distance_to(entry.position)>3.0:return
	placed.erase(id)
	_sync_models()
	_publish()

func _actor(peer: int) -> Vector3:
	return game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)

func _publish() -> void:
	if multiplayer.is_server() and game.session.online:_receive.rpc(placed)

@rpc("authority","call_remote","reliable")
func _receive(state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()!=1:return
	placed=state
	_sync_models()

func _sync_models() -> void:
	for id in models.keys():
		if placed.has(id):continue
		models[id].queue_free()
		models.erase(id)
	for id in placed:
		if not models.has(id):models[id]=_build_model(id,placed[id])
	game.hotbar._sync_dorm_items()
	game.smartphones.update_placed_speaker()

func _build_model(id: String, entry: Dictionary) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.collision_layer=4
	body.collision_mask=0
	body.position=entry.position
	body.rotation.y=entry.yaw
	body.set_meta("role","placed_personal_item")
	body.set_meta("placement_id",id)
	body.set_meta("label",entry.label)
	add_child(body)
	var hit:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(.15,.055,.24)
	hit.shape=shape
	hit.position.y=.026
	body.add_child(hit)
	var key: String=entry.key
	if key.begins_with("phone:"):
		var handset:=Node3D.new()
		handset.position.y=.007
		handset.rotation.x=-PI/2
		body.add_child(handset)
		var screen:=Handset.build(handset)
		Handset.apply_appearance(handset,entry.get("appearance",{}))
		if entry.peer==multiplayer.get_unique_id() and game.smartphones.is_powered(key.trim_prefix("phone:")):
			game.smartphones._paint_screen(screen,game.smartphones.idle_preview())
		body.set_meta("phone_screen",screen)
	elif key.begins_with("usb:"):
		shape.size=Vector3(.16,.05,.08)
		var usb: Node3D=game.computer_room_adapter._build_usb_visual(body,Vector3(-.04,.013,0))
		EquipmentFinish.apply_finish(usb,Configuration.USB,entry.get("configuration",{}))
	else:
		if Dorm.is_notebook(key):
			shape.size=preload("res://scripts/campus/items/notebook_model.gd").dimensions(entry.get("configuration",{}))
			hit.position.y=shape.size.y*.5
		elif key.begins_with("bag:"):
			shape.size=Dorm.Backpacks.dimensions(str(entry.visual).trim_prefix("bag_"))
			hit.position.y=shape.size.y*.5
		elif Dorm.is_calculator(key):
			shape.size=Configuration.value(Configuration.CALCULATOR,entry.get("configuration",{}),"hardware","size",Vector3(.135,.05,.215))
			hit.position.y=shape.size.y*.5
		game.discarded_items._add_item_visual(body,str(entry.visual),entry)
	return body

func _prune() -> void:
	if not multiplayer.is_server():return
	var changed:=false
	for id in placed.keys():
		if game.session.roster.has(placed[id].peer):continue
		placed.erase(id)
		changed=true
	if changed:
		_sync_models()
		_publish()

func _clear() -> void:
	for body in models.values():body.queue_free()
	models.clear()
	placed.clear()
