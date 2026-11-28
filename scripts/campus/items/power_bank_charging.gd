extends RefCounted

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Inventory = preload("res://scripts/campus/items/power_bank_inventory.gd")
const TICKS_PER_UPDATE := 3
# Campus batteries run at one simulated minute per real second.
const HOURS_PER_UPDATE := float(TICKS_PER_UPDATE)/60.0
const CABLE_REACH := 1.25
var charging: Node
var game: Node
var connections := {}
var meter := {}
var elapsed_ticks := 0

func clear() -> void:
	connections.clear()
	meter.clear()
	elapsed_ticks=0

func position(peer: int,key: String) -> Variant:
	var placed: Dictionary=game.personal_placement.placed.get(game.personal_placement.key_for(peer,key),{})
	return placed.get("position")

func battery(peer: int,key: String) -> Dictionary:
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	if identity.is_empty():return {}
	return game.dorm_interactions._profile(identity).get("dorm",{}).get("power_banks",{}).get(key,{})

func percent(key: String) -> int:
	var local: Dictionary=game.electronics.profile.data.get("dorm",{}).get("power_banks",{}).get(key,{})
	if local.is_empty():return int(meter.get(key,0))
	return roundi(100.0*float(local.charge_wh)/Inventory.capacity(local.configuration))

func connection_on_socket(slot: int) -> String:
	for key in connections:
		if connections[key].socket==slot:return key
	return ""

func target_connected(target: String) -> bool:
	for connection in connections.values():
		if target in connection.targets:return true
	return false

func report_bank(key: String, bank: Dictionary) -> void:
	var level:=roundi(100.0*float(bank.charge_wh)/Inventory.capacity(bank.configuration))
	var connection: Dictionary=connections.get(key,{})
	var mode := ""
	if int(connection.get("socket",-1))>=0:mode="Charging"
	elif not connection.get("targets",[]).is_empty():mode="Powering %d"%connection.targets.size()
	charging.publish_bank(key,level,mode)

func on_socket(peer: int,key: String,slot: int) -> bool:
	var bank:=battery(peer,key)
	if bank.is_empty():return false
	var old: Dictionary=connections.get(key,{})
	if old.get("socket",-1)>=0 or not old.get("targets",[]).is_empty():
		_notice(peer,"Disconnect the power bank before moving it to a wall charger.")
		return false
	connections[key]={"peer":peer,"socket":slot,"targets":[]}
	report_bank(key,bank)
	return true

func disconnect_bank(peer: int,key: String) -> void:
	if connections.get(key,{}).get("peer",0)==peer:
		var old: Dictionary=connections[key]
		connections.erase(key)
		_report_targets(old.targets)
		var bank:=battery(peer,key)
		if not bank.is_empty():report_bank(key,bank)

func disconnect_target(key: String) -> void:
	for id in connections.keys():
		var connection: Dictionary=connections[id]
		if key not in connection.targets:continue
		connection.targets.erase(key)
		var bank:=battery(connection.peer,id)
		if not bank.is_empty():report_bank(id,bank)
		_report_targets([key])

func connect_output(peer: int,key: String,target: String) -> bool:
	var bank:=battery(peer,key)
	var point: Variant=position(peer,key)
	var target_point: Variant=target_position(peer,target)
	if bank.is_empty() or not point is Vector3 or not target_point is Vector3:return false
	var entry: Dictionary=connections.get(key,{"peer":peer,"socket":-1,"targets":[]})
	var connector: String=Config.value(Config.POWER_BANK,bank.configuration,"hardware","connector","usb_c")
	var ports: int=Config.value(Config.POWER_BANK,bank.configuration,"hardware","ports",1)
	var compatible:=connector=="usb_pd" or (target.begins_with("phone:") and connector=="usb_c") or (target.begins_with("laptop:") and connector=="laptop")
	if not compatible or point.distance_to(target_point)>CABLE_REACH or absf(point.y-target_point.y)>=.28:
		_notice(peer,"Place a compatible phone or laptop within cable reach.")
		return false
	if entry.socket>=0 or entry.targets.size()>=ports or target_connected(target):return false
	if float(bank.charge_wh)<=0.0:
		_notice(peer,"The power bank is empty.")
		return false
	var device:=_target_device(peer,target)
	if device.is_empty() or device.socket>=0:return false
	entry.targets.append(target)
	connections[key]=entry
	report_bank(key,bank)
	_report_targets([target])
	return true

func target_position(peer: int,key: String) -> Variant:
	if key.begins_with("phone:"):return position(peer,key)
	var entry: Dictionary=game.portable_laptops.placed.get(key.trim_prefix("laptop:"),{})
	return entry.get("position") if entry.get("peer",0)==peer else null

func _target_device(peer: int,key: String) -> Dictionary:
	var id:=key.get_slice(":",1)
	if key.begins_with("laptop:"):
		id=key.trim_prefix("laptop:")
		var entry: Dictionary=game.portable_laptops.placed.get(id,{})
		if entry.get("peer",0)!=peer:return {}
		return charging._device(peer,"laptop",id,str(entry.tier))
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	var phone: Dictionary=game.dorm_interactions._profile(identity).get("dorm",{}).get("smartphones",{}).get(id,{})
	return {} if phone.is_empty() else charging._phone_device(peer,id,phone)

func _report_targets(keys: Array) -> void:
	for key in keys:
		if charging.devices.has(key):charging._report(key,charging.devices[key])

func _notice(peer: int,message: String) -> void:
	game.discarded_items._notice(peer,message)

func tick() -> void:
	elapsed_ticks+=1
	if elapsed_ticks<TICKS_PER_UPDATE:return
	elapsed_ticks=0
	var updates := {}
	for key in connections.keys():
		var connection: Dictionary=connections[key]
		var peer: int=connection.peer
		var point: Variant=position(peer,key)
		var bank:=battery(peer,key) if game.session.roster.has(peer) else {}
		if bank.is_empty() or not point is Vector3 or (connection.socket>=0 and not charging._on_bay(point,connection.socket)):
			disconnect_bank(peer,key)
			continue
		var options: Dictionary=bank.configuration
		var capacity:=Inventory.capacity(options)
		var level:=float(bank.charge_wh)
		var gains := {}
		var efficiency: float=Config.value(Config.POWER_BANK,options,"hardware","efficiency",.78)
		if connection.socket>=0:
			var input: float=Config.value(Config.POWER_BANK,options,"hardware","input",10.0)
			var refill: float=Config.value(Config.POWER_BANK,options,"hardware","charging",0.0)
			level=minf(capacity,level+(refill*TICKS_PER_UPDATE if refill>0.0 else input*HOURS_PER_UPDATE*efficiency))
		else:
			var valid_devices := {}
			for target in connection.targets.duplicate():
				var target_point: Variant=target_position(peer,target)
				if not target_point is Vector3 or point.distance_to(target_point)>CABLE_REACH or absf(point.y-target_point.y)>=.28:
					connection.targets.erase(target)
					_report_targets([target])
					continue
				var device:=_target_device(peer,target)
				if not device.is_empty() and device.socket<0 and float(device.charge)<1.0:valid_devices[target]=device
			var output: float=Config.value(Config.POWER_BANK,options,"hardware","output",12.0)
			var share:=output/float(maxi(1,valid_devices.size()))
			for target in valid_devices:
				var device: Dictionary=valid_devices[target]
				var is_phone: bool=device.kind=="phone"
				var nominal := 1200.0 if is_phone else 900.0
				var target_capacity := (12.0 if is_phone else 38.0)*float(device.runtime_seconds)/nominal
				if options.get("version",1)==2:target_capacity=100.0
				var max_input:=target_capacity*60.0/float(device.recharge_seconds)
				var drain:=minf(level,minf(share,max_input)*HOURS_PER_UPDATE)
				drain=minf(drain,(1.0-float(device.charge))*target_capacity/efficiency)
				level-=drain
				if drain>0:gains[target]=drain*efficiency/target_capacity
			if not connection.targets.is_empty() and level<=0.0:
				# Empty batteries never remain connected as a power source.
				disconnect_bank(peer,key)
			elif connection.targets.is_empty():
				disconnect_bank(peer,key)
		if is_equal_approx(level,float(bank.charge_wh)):continue
		if not updates.has(peer):
			var identity: String=game.dorm_interactions.authenticated_identity(peer)
			updates[peer]={"identity":identity,"profile":game.dorm_interactions._profile(identity).duplicate(true),"banks":[],"gains":{}}
		var update: Dictionary=updates[peer]
		update.profile.dorm.power_banks[key].charge_wh=clampf(level,0,capacity)
		update.banks.append(key)
		update.gains.merge(gains)
	for peer in updates:
		var update: Dictionary=updates[peer]
		update.profile.dorm.revision=int(update.profile.dorm.revision)+1
		if not game.dorm_interactions._commit_world_inventory(peer,update.identity,update.profile).ok:continue
		for target in update.gains:
			var device: Dictionary=charging.devices[target]
			device.charge=minf(1.0,float(device.charge)+float(update.gains[target]))
			charging._report(target,device)
		for key in update.banks:report_bank(key,update.profile.dorm.power_banks[key])
