extends Node3D

const Transfer = preload("res://scripts/ui/personal_inventory/discard_transfer.gd")
const Lifetime := 120000
var game: Node
var drops := {}
var views := {}
var next_id := 1
var clock_offset := 0

func build(owner_game: Node) -> void:
	game=owner_game
	game.session.restarted.connect(func():drops.clear();_publish())
	game.session.roster_changed.connect(_publish)

func discard(source: Dictionary) -> void:
	var point: Vector3 = game.player.global_position-game.player.global_basis.z
	if multiplayer.is_server():_discard(multiplayer.get_unique_id(),source,point)
	else:request_drop.rpc_id(1,source,point)

@rpc("any_peer","call_remote","reliable")
func request_drop(source: Dictionary,point: Vector3) -> void:
	if multiplayer.is_server():_discard(multiplayer.get_remote_sender_id(),source,point)

func _discard(peer: int,source: Dictionary,point: Vector3) -> void:
	if not game.session.roster.has(peer) or var_to_bytes(source).size()>1024 or not source.get("item") is Dictionary:return
	if drops.size()>=96:_notice(peer,"Too many discarded items are on the ground.");return
	var floor_point: Variant = _drop_position(peer,point)
	if floor_point==null:_notice(peer,"Face a clear spot on the floor to discard the item.");return
	var dorm = game.dorm_interactions
	var identity: String = dorm.authenticated_identity(peer)
	var profile: Dictionary = dorm._profile(identity)
	if not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():
		_notice(peer,"Inventory is unavailable.");return
	var item: Dictionary = source.item
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
		if not kit.is_empty() and not kit.get("stowed",false) and parcel.kits.has(kit.get("id","")):
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
	drops[next_id]={"position":floor_point,"expires":Time.get_ticks_msec()+Lifetime,"label":label,"parcel":parcel}
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
	if Time.get_ticks_msec()>=int(drop.expires) or not game.school._near(peer,drop.position):return
	var parcel: Dictionary = drop.parcel
	if parcel.has("paper"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return
		if not game.dc_lab._can_hold_lead(peer):_notice(peer,"Put down the item you are holding first.");return
		var paper: Dictionary = parcel.paper
		paper.owner=peer
		paper.held=true
		paper.stowed=false
		game.school.papers[paper.id]=paper
		game.school.broadcast()
	elif parcel.has("wire"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return
		if not _give_wire(peer,parcel):_notice(peer,"This cable cannot fit in your hotbar.");return
	elif parcel.has("food"):
		if slots<=0:_notice(peer,"Free a hotbar slot first.");return
		var result := _move_food(peer,"",parcel.food)
		if not result.ok:_notice(peer,str(result.error));return
	elif parcel.has("pcb") and slots>0:
		var result := _give_pcb(peer,parcel)
		if not result.ok:_notice(peer,str(result.error));return
	else:
		var dorm = game.dorm_interactions
		var identity: String = dorm.authenticated_identity(peer)
		var profile: Dictionary = dorm._profile(identity)
		if not profile.has("dorm") or not profile.get("pending_trade",{}).is_empty():
			_notice(peer,"Inventory is unavailable.");return
		var d: Dictionary = profile.dorm
		var limit := mini(6,d.get("carry_items",[]).size()+d.get("carried_components",[]).size()+clampi(slots,0,6))
		var result := Transfer.give(profile,parcel,limit)
		if not result.ok:_notice(peer,str(result.error));return
		var saved: Dictionary = dorm._commit_world_inventory(peer,identity,result.profile)
		if not saved.ok:_notice(peer,str(saved.error));return
	drops.erase(id)
	_publish()

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

func _give_pcb(peer: int,parcel: Dictionary) -> Dictionary:
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
	var saved: Dictionary=dorm._commit_world_inventory(peer,identity,next,deployment)
	if not saved.ok:return saved
	var station=lab.benches[slot]
	station.apply({"op":"board","design":design})
	station.board_owner=peer
	station.board_stowed=true
	lab.broadcast()
	return {"ok":true}

func _move_food(peer: int,id: String,incoming: Dictionary = {}) -> Dictionary:
	var controller = game.campus_services.facilities.controller
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
	if not host.commit_profile.call(str(context.identity),0,profile):return Transfer.Dorm.fail("Could not save food transfer.")
	controller._deliver(peer,{"ok":true,"state":host.private_state(peer)})
	return {"ok":true,"order":order}

func _title(parcel: Dictionary,profile: Dictionary) -> String:
	var item: Dictionary=parcel.item
	match item.kind:
		"kit":return str(parcel.kits[item.id].name)
		"bag":return str(Transfer.Dorm.Backpacks.SIZES[parcel.bags[item.id].size].name)
		"supply":return str(Transfer.Dorm.TOOLS[item.id])
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
	var public := {}
	for id in drops:
		var drop: Dictionary=drops[id]
		public[id]={"position":drop.position,"expires":drop.expires,"label":drop.label}
	for peer in game.session.connected_peers():sync_drops.rpc_id(peer,public,Time.get_ticks_msec())

@rpc("authority","call_remote","reliable")
func sync_drops(public: Dictionary,server_ticks: int) -> void:
	drops=public
	clock_offset=server_ticks-Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if not is_instance_valid(game):return
	var now := Time.get_ticks_msec()+clock_offset
	var changed := false
	if multiplayer.is_server():
		for id in drops.keys():
			if now>=int(drops[id].expires):
				drops.erase(id)
				changed=true
	if changed:_publish()
	for id in views.keys():
		if not drops.has(id):
			views[id].queue_free()
			views.erase(id)
	for id in drops:
		var drop: Dictionary=drops[id]
		if not views.has(id):views[id]=_make_view(id,drop)
		var root: StaticBody3D=views[id]
		var seconds := maxi(0,ceili((int(drop.expires)-now)/1000.0))
		root.visible=seconds>0
		root.collision_layer=4 if seconds>0 else 0
		var label: Label3D=root.get_node("Countdown")
		var text := "%s  ·  %d:%02d" % [drop.label,seconds/60,seconds%60]
		if label.text!=text:label.text=text

func _make_view(id: int,drop: Dictionary) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.collision_layer=4
	root.collision_mask=0
	root.set_meta("role","discarded_item")
	root.set_meta("discard_id",id)
	root.set_meta("label","Pick up "+str(drop.label))
	add_child(root)
	root.global_position=drop.position
	game._box(root,Vector3.UP*.055,Vector3(.22,.11,.16),Color("325765"))
	game._box(root,Vector3.UP*.11,Vector3(.225,.025,.165),Color("cfb183"))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.27,.16,.21)
	collision.shape=shape
	collision.position.y=.08
	root.add_child(collision)
	var label := Label3D.new()
	label.name="Countdown"
	label.position.y=.24
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size=32
	label.pixel_size=.003
	label.outline_size=8
	root.add_child(label)
	return root
