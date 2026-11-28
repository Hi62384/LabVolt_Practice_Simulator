extends Node3D

const CableMesh=preload("res://scripts/cable_mesh.gd")
const Room := "charging_room"
const Configuration = preload("res://scripts/campus/items/equipment_configuration.gd")
const BankInventory = preload("res://scripts/campus/items/power_bank_inventory.gd")
const PHONE_RUNTIME := {"basic":1200.0,"standard":1950.0,"premium":2900.0}
const LAPTOP_RUNTIME := {"basic":900.0,"standard":1500.0,"premium":2300.0}
const RECHARGE_TIME := {"basic":120.0,"standard":82.0,"premium":55.0}
const WALL_REACH:=3.0
const BANK_HELD_REACH:=1.75

var game: Node
var sockets: Array[Vector3] = []
var held_cables: Dictionary={}
var links: Dictionary={}
var bank_links: Dictionary={}
var bank_sources: Dictionary={}
var cable_models: Dictionary={}
var held_plug: Node3D
var cable_material:=CableMesh.jacket_material(Color("24373d"))
var moving_cable_mesh:=CylinderMesh.new()
var moving_cable_material:=ShaderMaterial.new()
var ticks_until_save:=10
var devices := {}
var own_charge := {}
var own_connected := {}
var last_phone_note := {}
var bank_modes := {}
var banks := preload("res://scripts/campus/items/power_bank_charging.gd").new()

func build(owner: Node) -> void:
	game=owner
	moving_cable_mesh.height=1.0
	moving_cable_mesh.top_radius=.006
	moving_cable_mesh.bottom_radius=.009
	moving_cable_mesh.radial_segments=8
	moving_cable_mesh.rings=14
	moving_cable_material.shader=preload("res://scripts/campus/items/held_charging_cable.gdshader")
	game.session.roster_changed.connect(_prune_cables)
	held_plug=game.campus.box(game.camera,Vector3(.24,-.205,-.47),Vector3(.035,.024,.075),"4b6c76",false)
	held_plug.rotation=Vector3(.25,.2,.2)
	game.campus.box(held_plug,Vector3(0,0,-.57),Vector3(.58,.46,.35),"b8c7ca",false)
	held_plug.hide()
	banks.game=game
	banks.charging=self
	var decor:=Node3D.new()
	decor.name="ChargingStations"
	game.campus.room_roots[Room].add_child(decor)
	game.campus.register_content(Room,decor)
	for index in 4:
		var position:=Vector3(22.4+float(index)*3.4,0,66.2)
		game.campus.box(decor,position+Vector3.UP*.76,Vector3(2.55,.1,1.26),"607e89")
		decor.get_child(-1).set_meta("role","table")
		for side in [-1,1]:
			game.campus.box(decor,position+Vector3(float(side)*1.08,.35,0),Vector3(.12,.72,1.05),"293d49")
		var pad: Node3D=game.campus.box(decor,position+Vector3(0,.813,-.16),Vector3(1.45,.018,.71),"325c63")
		decor.get_child(-1).set_meta("role","table")
		pad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var point:=position+Vector3(0,.93,.40)
		sockets.append(point)
		_draw_cable(index)
		game.campus.box(decor,point,Vector3(.23,.22,.1),"174352",false)
		game.campus.box(decor,point+Vector3(0,.065,-.054),Vector3(.11,.023,.013),"7de6bb",false)
		var target:=StaticBody3D.new()
		target.position=point
		target.collision_layer=4
		target.collision_mask=0
		target.set_meta("role","device_charger")
		target.set_meta("charger",index)
		var hit:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=Vector3(.34,.26,.16)
		hit.shape=shape
		target.add_child(hit)
		decor.add_child(target)
		game.campus.sign_text(decor,"CHARGER %d"%(index+1),position+Vector3(0,1.34,.53),0,22)
	game.campus.sign_text(decor,"DEVICE CHARGING",Vector3(25.5,2.8,67.84),PI,52)
	var clock:=Timer.new()
	clock.wait_time=1.0
	clock.timeout.connect(_tick)
	add_child(clock)
	clock.start()
	game.session.leaving.connect(_clear)
	game.session.restarted.connect(_clear)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(game):_save_charge()

func _clear() -> void:
	_save_charge()
	held_plug.hide()
	held_cables.clear()
	links.clear()
	bank_links.clear()
	bank_sources.clear()
	for slot in cable_models.keys():
		if slot is String:
			cable_models[slot].queue_free()
			cable_models.erase(slot)
	_sync_hotbar()
	for slot in sockets.size():_draw_cable(slot)
	devices.clear()
	own_charge.clear()
	own_connected.clear()
	last_phone_note.clear()
	banks.clear()
	bank_modes.clear()

func bank_percent(key: String) -> int:
	return int(banks.meter[key]) if banks.meter.has(key) else banks.percent(key)

func bank_label(key: String) -> String:
	var mode: String=bank_modes.get(key,"")
	return "Power bank %d%%"%bank_percent(key)+(" · "+mode if not mode.is_empty() else "")

func toggle_bank(key: String) -> void:
	if multiplayer.is_server():_use_bank(multiplayer.get_unique_id(),key)
	else:_power_bank_request.rpc_id(1,key)

@rpc("any_peer","call_remote","reliable")
func _power_bank_request(key: String) -> void:
	if multiplayer.is_server():_use_bank(multiplayer.get_remote_sender_id(),key)

func _use_bank(peer: int,key: String) -> void:
	for slot in bank_sources:
		if bank_sources[slot].key==key and bank_sources[slot].peer==peer and not bank_links.has(slot):
			_grab(peer,slot)
			return

func disconnect_placement(peer: int,key: String) -> void:
	if str(held_cables.get(peer,"")).begins_with(key+"#"):held_cables.erase(peer)
	for source in bank_links.keys():
		var link: Dictionary=bank_links[source]
		if link.peer==peer and (link.key==key or str(source).begins_with(key+"#")):bank_links.erase(source)
	if BankInventory.valid_key(key):banks.disconnect_bank(peer,key)
	elif key.begins_with("phone:") or key.begins_with("laptop:"):banks.disconnect_target(key)
	for slot in links.keys():
		if links[slot].peer==peer and links[slot].key==key:_unlink(slot)
	_sync_cables()

func publish_bank(key: String,level: int,mode: String) -> void:
	_receive_bank(key,level,mode)
	if game.session.online:_power_bank_state.rpc(key,level,mode)

@rpc("authority","call_remote","reliable")
func _power_bank_state(key: String,level: int,mode: String) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive_bank(key,level,mode)

func _receive_bank(key: String,level: int,mode: String) -> void:
	banks.meter[key]=level
	bank_modes[key]=mode
	game.personal_placement.update_bank_charge(key,level)

func percent(kind: String,id: String) -> int:
	var key:=kind+":"+id
	if own_charge.has(key):return int(own_charge[key])
	if not is_instance_valid(game.electronics) or not is_instance_valid(game.electronics.profile):return 100
	var item:=_owned_device(game.electronics.profile.data,kind,id)
	return roundi(100.0*float(item.get("charge",1.0)))

func label(kind: String,id: String) -> String:
	return "Battery %d%%"%percent(kind,id)+(" · Charging" if own_connected.get(kind+":"+id,false) else "")

func can_power_laptop(peer: int,id: String,tier: String) -> bool:
	var record:=_device(peer,"laptop",id,tier)
	_report("laptop:"+id,record)
	return float(record.charge)>0.0

func use_phone(id: String) -> void:
	if not game.session.online or multiplayer.is_server():_note_phone(multiplayer.get_unique_id(),id)
	else:_phone_active.rpc_id(1,id)

@rpc("any_peer","call_remote","unreliable")
func _phone_active(id: String) -> void:
	if multiplayer.is_server():_note_phone(multiplayer.get_remote_sender_id(),id)

func _note_phone(peer: int,id: String) -> void:
	if id.length()!=32 or not id.is_valid_hex_number() or not game.session.roster.has(peer):return
	var now:=Time.get_ticks_msec()
	if now-int(last_phone_note.get(peer,-1000))<850:return
	last_phone_note[peer]=now
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	var dorm: Dictionary=game.dorm_interactions._profile(identity).get("dorm",{})
	var item: Dictionary=dorm.get("smartphones",{}).get(id,{})
	if item.get("location")!="hotbar" or "phone:"+id not in dorm.get("carry_items",[]) or str(dorm.get("teacher_phone_custody",{}).get("id",""))==id:return
	var tier:=str(item.get("tier",""))
	if PHONE_RUNTIME.has(tier):_phone_device(peer,id,item).active_until=now+3200

func add_port(parent: Node3D,key: String,peer: int,point: Vector3,port_size: Vector3) -> void:
	var port:=StaticBody3D.new()
	port.position=point
	port.collision_layer=4
	port.collision_mask=0
	port.set_meta("role","charging_port")
	port.set_meta("charge_key",key)
	port.set_meta("charge_owner",peer)
	parent.add_child(port)
	parent.set_meta("charging_port",port)
	var hit:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=port_size
	hit.shape=shape
	port.add_child(hit)
	var rim:=Vector3(.012,.027,.026) if port_size.x<port_size.z else Vector3(.032,.018,.012)
	game.campus.box(port,Vector3.ZERO,rim,"19292f",false)

func interact(target: Object) -> bool:
	if not is_instance_valid(target):return false
	var role: String=target.get_meta("role","")
	if role=="device_charger":
		var slot:=int(target.get_meta("charger",-1))
		if multiplayer.is_server():_grab(multiplayer.get_unique_id(),slot)
		else:_charge_request.rpc_id(1,slot)
		return true
	if role=="bank_charger":
		var slot:=str(target.get_meta("charger",""))
		if multiplayer.is_server():_grab(multiplayer.get_unique_id(),slot)
		else:_bank_lead_request.rpc_id(1,slot)
		return true
	if role=="charging_port":
		var key:=str(target.get_meta("charge_key",""))
		if multiplayer.is_server():_plug(multiplayer.get_unique_id(),key)
		else:_plug_request.rpc_id(1,key)
		return true
	return false

func port_hint(target: Object,key_name: String) -> String:
	var peer:=multiplayer.get_unique_id()
	var key: String=target.get_meta("charge_key","")
	if int(target.get_meta("charge_owner",0))!=peer:return "Charging port"
	for link in links.values()+bank_links.values():
		if link.peer==peer and link.key==key:return "%s · Unplug charging cable"%key_name
	return "%s · Plug in charging cable"%key_name if held_cables.has(peer) else "Charging port · Pick up a cable from the charger"

func charger_hint(slot: Variant,key_name: String) -> String:
	var peer:=multiplayer.get_unique_id()
	var connected: Dictionary=bank_links if slot is String else links
	if connected.has(slot):return "%s · Unplug charging cable"%key_name if connected[slot].peer==peer else "Charger in use"
	if is_same(held_cables.get(peer),slot):return "%s · Return cable"%key_name
	return "%s · Pick up charging cable"%key_name

@rpc("any_peer","call_remote","reliable")
func _charge_request(slot: int) -> void:
	if multiplayer.is_server():_grab(multiplayer.get_remote_sender_id(),slot)

@rpc("any_peer","call_remote","reliable")
func _plug_request(key: String) -> void:
	if multiplayer.is_server():_plug(multiplayer.get_remote_sender_id(),key)

func _grab(peer: int,slot: Variant) -> void:
	var anchor:=source_position(slot)
	if not anchor.is_finite() or not game.session.roster.has(peer) or game.personal_placement._actor(peer).distance_to(anchor)>2.8:return
	if slot is String and int(bank_sources[slot].peer)!=peer:return
	var connected: Dictionary=bank_links if slot is String else links
	if connected.has(slot):
		if connected[slot].peer==peer:
			if slot is String:_unlink_bank(slot)
			else:_unlink(slot)
		else:game.discarded_items._notice(peer,"This charger is in use.")
		return
	if is_same(held_cables.get(peer),slot):
		held_cables.erase(peer)
	elif slot not in held_cables.values():
		if held_cables.has(peer):return
		if peer==multiplayer.get_unique_id() and not game.hotbar.slots.has({}):
			game.ui.log_message("Free a hotbar slot before picking up the cable.")
			return
		held_cables[peer]=slot
		game.discarded_items._notice(peer,"Aim at your device's charging port to plug in the cable.")
	else:
		game.discarded_items._notice(peer,"Someone is holding this cable.")
		return
	_sync_cables()

@rpc("any_peer","call_remote","reliable")
func _bank_lead_request(slot: String) -> void:
	if multiplayer.is_server() and slot.length()<=68:_grab(multiplayer.get_remote_sender_id(),slot)

func holding_cable() -> bool:
	return held_cables.has(multiplayer.get_unique_id())

func release_cable() -> void:
	if not holding_cable():return
	if multiplayer.is_server():_release(multiplayer.get_unique_id())
	else:_release_request.rpc_id(1)

@rpc("any_peer","call_remote","reliable")
func _release_request() -> void:
	if multiplayer.is_server():_release(multiplayer.get_remote_sender_id())

func _release(peer: int) -> void:
	if not held_cables.erase(peer):return
	_sync_cables()

func _plug(peer: int,key: String) -> void:
	if not game.session.roster.has(peer) or key.length()>60:return
	var port:=_port(peer,key)
	if not is_instance_valid(port) or game.personal_placement._actor(peer).distance_to(port.global_position)>2.8:return
	for slot in links.keys():
		if links[slot].peer==peer and links[slot].key==key:
			_unlink(slot)
			return
	for source in bank_links.keys():
		if bank_links[source].peer==peer and bank_links[source].key==key:
			_unlink_bank(source)
			return
	var source: Variant=held_cables.get(peer,-1)
	if source is String:
		var record: Dictionary=bank_sources.get(source,{})
		if int(record.get("peer",0))!=peer or not banks.connect_output(peer,str(record.key),key):return
		held_cables.erase(peer)
		bank_links[source]={"peer":peer,"key":key,"point":port.global_position}
		_sync_cables()
		return
	var slot:=int(source)
	if slot<0:return
	var laptop:=key.begins_with("laptop:")
	var id:=key.get_slice(":",1)
	var entry: Dictionary=game.portable_laptops.placed.get(id,{}) if laptop else game.personal_placement.placed.get(game.personal_placement.key_for(peer,key),{})
	if entry.get("peer",0)!=peer or not _on_bay(entry.position,slot) or port.global_position.distance_to(sockets[slot])>1.55:
		game.discarded_items._notice(peer,"Place this device on the same charging bench as the cable.")
		return
	if banks.target_connected(key):
		game.discarded_items._notice(peer,"Disconnect the power bank first.")
		return
	if BankInventory.valid_key(key):
		if not banks.on_socket(peer,key,slot):return
	else:
		var record: Dictionary
		if laptop:record=_device(peer,"laptop",id,str(entry.tier))
		elif key.begins_with("phone:"):record=banks._target_device(peer,key)
		if record.is_empty() or int(record.socket)>=0:return
		record.socket=slot
		_report(key,record)
	held_cables.erase(peer)
	links[slot]={"peer":peer,"key":key,"point":port.global_position}
	_sync_cables()

func _port(peer: int,key: String) -> Node3D:
	var model: Node3D
	if key.begins_with("laptop:"):
		var entry: Dictionary=game.portable_laptops.placed.get(key.get_slice(":",1),{})
		if entry.get("peer",0)==peer:model=entry.get("model")
	else:model=game.personal_placement.models.get(game.personal_placement.key_for(peer,key))
	return model.get_meta("charging_port",null) if is_instance_valid(model) and model.has_meta("charging_port") else null

func _unlink(slot: int) -> void:
	var link: Dictionary=links[slot]
	var key: String=link.key
	if BankInventory.valid_key(key):banks.disconnect_bank(link.peer,key)
	elif devices.has(key):
		devices[key].socket=-1
		_report(key,devices[key])
	links.erase(slot)
	_sync_cables()

func _unlink_bank(source: String) -> void:
	var target: String=bank_links[source].key
	bank_links.erase(source)
	banks.disconnect_target(target)
	_sync_cables()

func _prune_cables() -> void:
	if not multiplayer.is_server():return
	_save_charge()
	for peer in held_cables.keys():
		if not game.session.roster.has(peer):held_cables.erase(peer)
	for slot in links.keys():
		if not game.session.roster.has(links[slot].peer):_unlink(slot)
	for slot in bank_links.keys():
		if not game.session.roster.has(bank_links[slot].peer):_unlink_bank(slot)
	_sync_cables()

func _sync_cables() -> void:
	_receive_cables(held_cables,links,bank_links)
	if game.session.online:_receive_cables.rpc(held_cables,links,bank_links)

@rpc("authority","call_remote","reliable")
func _receive_cables(holders: Dictionary,connections: Dictionary,outputs: Dictionary={}) -> void:
	held_cables=holders
	links=connections
	bank_links=outputs
	held_plug.visible=holding_cable()
	_sync_hotbar()
	for slot in sockets.size():_draw_cable(slot)
	for slot in bank_sources:_draw_cable(slot)

func _sync_hotbar() -> void:
	var hotbar: Node=game.hotbar
	if not is_instance_valid(hotbar):return
	var item:={"kind":"charging_cable"}
	var index: int=hotbar.slots.find(item)
	if holding_cable():
		if index<0:
			index=hotbar.add_item(item)
			if index<0:
				release_cable.call_deferred()
				return
			hotbar.active=index
	elif index>=0:
		hotbar.slots[index]={}
		if hotbar.active==index:hotbar.active=-1

func refresh_bank_cables() -> void:
	for slot in bank_sources:
		if is_instance_valid(cable_models.get(slot)):cable_models[slot].free()
		cable_models.erase(slot)
	bank_sources.clear()
	for id in game.personal_placement.placed:
		var entry: Dictionary=game.personal_placement.placed[id]
		if not BankInventory.valid_key(entry.key) or not game.personal_placement.models.has(id):continue
		var model: Node3D=game.personal_placement.models[id]
		var options: Dictionary=entry.get("configuration",{})
		var count: int=Configuration.value(Configuration.POWER_BANK,options,"hardware","ports",1)
		var size: Vector3=preload("res://scripts/campus/items/power_bank_model.gd").dimensions(options)
		for port in count:
			var slot: String="%s#%d"%[entry.key,port]
			var point:=model.to_global(Vector3((float(port)-float(count-1)*.5)*.024,size.y*.62,-size.z*.5-.006))
			bank_sources[slot]={"key":entry.key,"peer":entry.peer,"point":point,"outward":-model.global_basis.z.normalized()}
			_draw_cable(slot)

func source_position(slot: Variant) -> Vector3:
	if slot is String:return bank_sources.get(slot,{}).get("point",Vector3.INF)
	return sockets[slot]+Vector3(0,-.062,-.058) if slot is int and slot in range(sockets.size()) else Vector3.INF

func tether() -> Dictionary:
	if not holding_cable():return {}
	var source: Variant=held_cables[multiplayer.get_unique_id()]
	var anchor:=source_position(source)
	if not anchor.is_finite():return {}
	return {"anchor":anchor,"grip":_grip(),"reach":BANK_HELD_REACH if source is String else WALL_REACH}

func _draw_cable(slot: Variant) -> void:
	if is_instance_valid(cable_models.get(slot)):cable_models[slot].free()
	var station: Node3D=self if slot is String else game.campus.room_roots[Room].get_node("ChargingStations")
	var cable:=MeshInstance3D.new()
	cable_models[slot]=cable
	cable.material_override=cable_material
	cable.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	station.add_child(cable)
	var socket:=source_position(slot)
	if slot in held_cables.values():
		cable.mesh=moving_cable_mesh
		cable.material_override=moving_cable_material.duplicate()
		cable.custom_aabb=AABB(Vector3(-.25,-.75,-.25),Vector3(.5,1.5,.5))
		_update_held_lead(slot)
		return
	var connected: Dictionary=bank_links if slot is String else links
	if connected.has(slot):
		var end: Vector3=connected[slot].point
		var clearance: Array[AABB]=[]
		if slot is int:clearance.append(AABB(sockets[slot]+Vector3(-1.28,-.14,-1.03),Vector3(2.56,.032,1.25)))
		cable.mesh=CableMesh.held_geometry(socket,end,Basis.IDENTITY,true,.006,clearance)
		_usb_end(cable,end,(end-socket).normalized(),false)
		return
	var inward: Vector3=-bank_sources[slot].outward if slot is String else Vector3.BACK
	_usb_end(cable,socket,inward,true,slot)

func _usb_end(parent: Node3D,point: Vector3,direction: Vector3,parked: bool,slot: Variant=-1) -> void:
	var plug:=Node3D.new()
	parent.add_child(plug)
	plug.position=point
	plug.rotation.y=atan2(direction.x,direction.z)
	game.campus.box(plug,Vector3(0,0,-.022),Vector3(.029,.018,.040),"394a54",false)
	game.campus.box(plug,Vector3(0,0,.004),Vector3(.019,.008,.020),"bdc6c8",false)
	if not parked:return
	var target:=StaticBody3D.new()
	target.position.z=-.034
	target.collision_layer=4
	target.collision_mask=0
	target.set_meta("role","bank_charger" if slot is String else "device_charger")
	target.set_meta("charger",slot)
	plug.add_child(target)
	var hit:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(.024,.052,.06) if slot is String else Vector3(.10,.083,.11)
	hit.shape=shape
	target.add_child(hit)

func _process(_delta: float) -> void:
	if held_cables.is_empty() or not game.front.in_game:return
	for slot in held_cables.values():
		if cable_models.has(slot):_update_held_lead(slot)

func _grip() -> Vector3:
	return held_plug.to_global(Vector3(0,0,.5))

func _update_held_lead(slot: Variant) -> void:
	var holder:=int(held_cables.find_key(slot))
	var cable: MeshInstance3D=cable_models[slot]
	var local:=holder==multiplayer.get_unique_id()
	var grip: Vector3=_grip() if local else game.held_item_position(holder,game.personal_placement._actor(holder)+Vector3.UP)
	var start:=source_position(slot)
	if not grip.is_finite() or not start.is_finite():return
	var distance:=maxf(grip.distance_to(start),.001)
	var direction: Vector3=(grip-start)/distance
	if not direction.is_normalized():return
	var rotation:=Basis(Quaternion(Vector3.UP,direction))
	var basis:=rotation.scaled_local(Vector3(1,distance,1))
	cable.global_transform=Transform3D(basis,(start+grip)*.5)
	(cable.material_override as ShaderMaterial).set_shader_parameter("bend",basis.inverse()*Vector3.DOWN*minf(.10,distance*.14))

func _on_bay(point: Vector3,slot: int) -> bool:
	return absf(point.y-.81)<.14 and absf(point.x-sockets[slot].x)<1.2 and absf(point.z-(sockets[slot].z-.40))<.61

func _device(peer: int,kind: String,id: String,tier: String) -> Dictionary:
	var key:=kind+":"+id
	if not devices.has(key):
		var identity: String=game.dorm_interactions.authenticated_identity(peer)
		var saved: Dictionary=_owned_device(game.dorm_interactions._profile(identity),kind,id)
		var charge:=float(saved.get("charge",1.0))
		devices[key]={"peer":peer,"identity":identity,"id":id,"kind":kind,"tier":tier,"charge":charge,"saved":charge,"socket":-1,"active_until":0,"reported":100}
	var record: Dictionary=devices[key]
	record.peer=peer
	if kind=="laptop":
		var configuration: Dictionary=game.computers.stations.get(id,{}).get("configuration",{})
		record.runtime_seconds=Configuration.value(Configuration.LAPTOP,configuration,"hardware","battery",LAPTOP_RUNTIME.get(tier,900.0))
		record.recharge_seconds=Configuration.value(Configuration.LAPTOP,configuration,"hardware","charging",RECHARGE_TIME.get(tier,120.0))
	return record

func _phone_device(peer: int,id: String,item: Dictionary) -> Dictionary:
	var record:=_device(peer,"phone",id,item.tier)
	record.runtime_seconds=Configuration.phone_value(item,"battery",PHONE_RUNTIME[item.tier])
	record.recharge_seconds=Configuration.phone_value(item,"charging",RECHARGE_TIME[item.tier])
	return record

func _owned_device(profile: Dictionary,kind: String,id: String) -> Dictionary:
	return profile.get("dorm",{}).get("smartphones" if kind=="phone" else "portable_laptops",{}).get(id,{})

func _save_charge() -> void:
	if not multiplayer.is_server() or not is_instance_valid(game.dorm_interactions):return
	var updates:={}
	for record in devices.values():
		var identity: String=record.get("identity","")
		if identity.is_empty() or is_equal_approx(float(record.charge),float(record.saved)):continue
		if not updates.has(identity):
			var profile: Dictionary=game.dorm_interactions._profile(identity)
			if profile.is_empty():continue
			updates[identity]={"profile":profile.duplicate(true),"peer":record.peer,"records":[]}
		var update: Dictionary=updates[identity]
		var item:=_owned_device(update.profile,record.kind,record.id)
		if item.is_empty():continue
		item.charge=record.charge
		update.records.append(record)
	for identity: String in updates:
		var update: Dictionary=updates[identity]
		if update.records.is_empty():continue
		update.profile.dorm.revision+=1
		if game.dorm_interactions._commit_world_inventory(update.peer,identity,update.profile).ok:
			for record in update.records:record.saved=record.charge

func _tick() -> void:
	if not multiplayer.is_server():return
	var now:=Time.get_ticks_msec()
	for key: String in devices:
		var record: Dictionary=devices[key]
		if not game.session.roster.has(record.peer):
			record.socket=-1
			continue
		var laptop: bool=record.kind=="laptop"
		var entry: Dictionary=game.portable_laptops.placed.get(record.id,{}) if laptop else game.personal_placement.placed.get(game.personal_placement.key_for(record.peer,key),{})
		var active: bool=now<int(record.active_until)
		if laptop:
			var station: Dictionary=game.computers.stations.get(record.id,{})
			active=station.has("power") and station.power.powered
		var was_connected: bool=record.socket>=0
		if was_connected and (entry.is_empty() or entry.peer!=record.peer or not _on_bay(entry.position,record.socket)):
			if links.has(record.socket):_unlink(record.socket)
			else:record.socket=-1
		if record.socket>=0:
			record.charge=minf(1.0,float(record.charge)+1.0/float(record.get("recharge_seconds",RECHARGE_TIME.get(record.tier,120.0))))
		elif active:
			var times:=LAPTOP_RUNTIME if laptop else PHONE_RUNTIME
			record.charge=maxf(0.0,float(record.charge)-1.0/float(record.get("runtime_seconds",times.get(record.tier,900.0))))
		if record.charge<=0.0 and active and laptop:game.computers._power_off(record.id)
		if record.reported!=roundi(record.charge*100.0) or was_connected!=(record.socket>=0):_report(key,record)
	banks.tick()
	var removed_output:=false
	for source in bank_links.keys():
		if not banks.target_connected(bank_links[source].key):
			bank_links.erase(source)
			removed_output=true
	if removed_output:_sync_cables()
	ticks_until_save-=1
	if ticks_until_save<=0:
		_save_charge()
		ticks_until_save=10

func _report(key: String,record: Dictionary) -> void:
	var level:=roundi(float(record.charge)*100.0)
	record.reported=level
	var connected: bool=record.socket>=0 or banks.target_connected(key)
	if record.peer==multiplayer.get_unique_id():_receive(key,level,connected)
	elif game.session.online and game.session.peer_connected_now(record.peer):_charge_state.rpc_id(record.peer,key,level,connected)

@rpc("authority","call_remote","reliable")
func _charge_state(key: String,level: int,connected: bool) -> void:
	if multiplayer.get_remote_sender_id()==1:_receive(key,level,connected)

func _receive(key: String,level: int,connected: bool) -> void:
	own_charge[key]=level
	own_connected[key]=connected
	if key.begins_with("phone:") and level<=0:
		game.smartphones.powered_on.erase(key.trim_prefix("phone:"))
