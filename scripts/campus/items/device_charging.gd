extends Node3D

const Room := "charging_room"
const Configuration = preload("res://scripts/campus/items/equipment_configuration.gd")
const BankInventory = preload("res://scripts/campus/items/power_bank_inventory.gd")
const PHONE_RUNTIME := {"basic":1200.0,"standard":1950.0,"premium":2900.0}
const LAPTOP_RUNTIME := {"basic":900.0,"standard":1500.0,"premium":2300.0}
const RECHARGE_TIME := {"basic":120.0,"standard":82.0,"premium":55.0}

var game: Node
var sockets: Array[Vector3] = []
var devices := {}
var own_charge := {}
var own_connected := {}
var last_phone_note := {}
var bank_modes := {}
var banks := preload("res://scripts/campus/items/power_bank_charging.gd").new()

func build(owner: Node) -> void:
	game=owner
	banks.game=game
	banks.charging=self
	var decor:=Node3D.new()
	decor.name="ChargingStations"
	game.campus.room_roots[Room].add_child(decor)
	game.campus.register_content(Room,decor)
	for index in 4:
		var position:=Vector3(22.4+float(index)*3.4,0,66.2)
		game.campus.box(decor,position+Vector3.UP*.76,Vector3(2.55,.1,1.26),"607e89")
		for side in [-1,1]:
			game.campus.box(decor,position+Vector3(float(side)*1.08,.35,0),Vector3(.12,.72,1.05),"293d49")
		var pad: Node3D=game.campus.box(decor,position+Vector3(0,.813,-.16),Vector3(1.45,.018,.71),"325c63",false)
		pad.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var point:=position+Vector3(0,.93,.40)
		sockets.append(point)
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

func _clear() -> void:
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
	if multiplayer.is_server():banks.toggle(multiplayer.get_unique_id(),key)
	else:_power_bank_request.rpc_id(1,key)

@rpc("any_peer","call_remote","reliable")
func _power_bank_request(key: String) -> void:
	if multiplayer.is_server():banks.toggle(multiplayer.get_remote_sender_id(),key)

func disconnect_placement(peer: int,key: String) -> void:
	if BankInventory.valid_key(key):banks.disconnect_bank(peer,key)
	elif key.begins_with("phone:") or key.begins_with("laptop:"):banks.disconnect_target(key)

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
	return int(own_charge.get(kind+":"+id,100))

func label(kind: String,id: String) -> String:
	return "Battery %d%%"%percent(kind,id)+(" · Charging" if own_connected.get(kind+":"+id,false) else "")

func can_power_laptop(peer: int,id: String,tier: String) -> bool:
	var record:=_device(peer,"laptop",id,tier)
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

func interact(target: Object) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","")!="device_charger":return false
	var slot:=int(target.get_meta("charger",-1))
	if multiplayer.is_server():_toggle(multiplayer.get_unique_id(),slot)
	else:_charge_request.rpc_id(1,slot)
	return true

@rpc("any_peer","call_remote","reliable")
func _charge_request(slot: int) -> void:
	if multiplayer.is_server():_toggle(multiplayer.get_remote_sender_id(),slot)

func _toggle(peer: int,slot: int) -> void:
	if slot<0 or slot>=sockets.size() or not game.session.roster.has(peer):return
	var at: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if at.distance_to(sockets[slot])>2.8:return
	var bank_key:=banks.connection_on_socket(slot)
	if not bank_key.is_empty():
		if banks.connections[bank_key].peer==peer:banks.disconnect_bank(peer,bank_key)
		else:game.discarded_items._notice(peer,"This charger is in use.")
		return
	for key in devices:
		var connected: Dictionary=devices[key]
		if connected.socket!=slot:continue
		if connected.peer!=peer:
			game.discarded_items._notice(peer,"This charger is in use.")
		else:
			connected.socket=-1
			_report(key,connected)
		return
	var best_distance:=1.25
	var chosen:={}
	for item in game.portable_laptops.placed.values():
		var distance: float=item.position.distance_to(sockets[slot])
		if item.peer!=peer or not _on_bay(item.position,slot) or distance>=best_distance:continue
		if banks.target_connected("laptop:"+item.station):continue
		best_distance=distance
		chosen={"kind":"laptop","id":item.station,"tier":item.tier}
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	var dorm: Dictionary=game.dorm_interactions._profile(identity).get("dorm",{})
	for item in game.personal_placement.placed.values():
		if item.peer!=peer or not _on_bay(item.position,slot):continue
		var distance: float=item.position.distance_to(sockets[slot])
		if distance>=best_distance:continue
		if BankInventory.valid_key(item.key):
			best_distance=distance
			chosen={"kind":"power_bank","id":item.key}
			continue
		if not str(item.key).begins_with("phone:") or banks.target_connected(item.key):continue
		var id:=str(item.key).trim_prefix("phone:")
		var tier:=str(dorm.get("smartphones",{}).get(id,{}).get("tier",""))
		if not PHONE_RUNTIME.has(tier):continue
		best_distance=distance
		chosen={"kind":"phone","id":id,"tier":tier}
	if chosen.is_empty():
		game.discarded_items._notice(peer,"Place your phone, laptop or power bank on this charging bench first.")
		return
	if chosen.kind=="power_bank":
		banks.on_socket(peer,chosen.id,slot)
		return
	var record:=_device(peer,chosen.kind,chosen.id,chosen.tier) if chosen.kind=="laptop" else _phone_device(peer,chosen.id,dorm.smartphones[chosen.id])
	record.socket=slot
	_report(chosen.kind+":"+chosen.id,record)

func _on_bay(point: Vector3,slot: int) -> bool:
	return absf(point.y-.81)<.14 and absf(point.x-sockets[slot].x)<1.2 and absf(point.z-(sockets[slot].z-.40))<.61

func _device(peer: int,kind: String,id: String,tier: String) -> Dictionary:
	var key:=kind+":"+id
	var record: Dictionary=devices.get_or_add(key,{"peer":peer,"id":id,"kind":kind,"tier":tier,"charge":1.0,"socket":-1,"active_until":0,"reported":100})
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
		if was_connected and (entry.is_empty() or entry.peer!=record.peer or not _on_bay(entry.position,record.socket)):record.socket=-1
		if record.socket>=0:
			record.charge=minf(1.0,float(record.charge)+1.0/float(record.get("recharge_seconds",RECHARGE_TIME.get(record.tier,120.0))))
		elif active:
			var times:=LAPTOP_RUNTIME if laptop else PHONE_RUNTIME
			record.charge=maxf(0.0,float(record.charge)-1.0/float(record.get("runtime_seconds",times.get(record.tier,900.0))))
		if record.charge<=0.0 and active and laptop:game.computers._power_off(record.id)
		if record.reported!=roundi(record.charge*100.0) or was_connected!=(record.socket>=0):_report(key,record)
	banks.tick()

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
