extends Node3D

const T=preload("res://scripts/ui/design_system/tokens.gd")
const Dress=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Gym=preload("res://scripts/campus/facilities/gym_progress.gd")
const Mass=preload("res://scripts/campus/facilities/carry_mass.gd")
const Handset=preload("res://scripts/campus/phones/phone_handset.gd")
const WINDUP:=1.15
const GRAVITY:=Vector3(0,-9.8,0)
var game: Node
var charge_started:=0
var selected: Dictionary={}
var meter: ProgressBar
var card: PanelContainer
var caption: Label
var launching:=false
var flights: Dictionary={}
var windups: Dictionary={}
var pending: Dictionary={}
var landing_peer:=0
var landing_point:=Vector3.INF

func build(owner: Node) -> void:
	game=owner
	var hud:=CanvasLayer.new()
	hud.layer=28
	add_child(hud)
	card=PanelContainer.new()
	card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel",T.surface(Color("102a3aee"),Color("548da1"),10))
	hud.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.offset_left=-144
	card.offset_right=144
	card.offset_top=-218
	card.offset_bottom=-143
	var stack:=VBoxContainer.new()
	stack.mouse_filter=Control.MOUSE_FILTER_IGNORE
	card.add_child(stack)
	caption=Label.new()
	caption.add_theme_font_size_override("font_size",15)
	caption.add_theme_color_override("font_color",T.ACCENT)
	stack.add_child(caption)
	meter=ProgressBar.new()
	meter.show_percentage=false
	meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	meter.custom_minimum_size.y=10
	meter.add_theme_stylebox_override("background",T.surface(Color("213748"),Color("324d5f"),0))
	meter.add_theme_stylebox_override("fill",T.surface(Color("59d7ad"),Color("9bf1d8"),0))
	stack.add_child(meter)
	var hint:=Label.new()
	hint.text="Release to throw  ·  Right-click to cancel"
	hint.add_theme_font_size_override("font_size",13)
	hint.add_theme_color_override("font_color",T.MUTED)
	stack.add_child(hint)
	_cancel()
	game.session.leaving.connect(_clear)
	game.session.restarted.connect(_clear)
	multiplayer.peer_disconnected.connect(func(peer):windups.erase(peer);pending.erase(peer))

func route(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and charge_started>0:
		_cancel_charge()
		return true
	if not event is InputEventKey or event.physical_keycode!=game.player.keys.throw_item:return false
	if not game.front.in_game or not game.player.enabled or game.player.inspecting or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		_cancel_charge()
		return false
	if event.echo or launching:return true
	if event.pressed:
		selected=_held()
		if selected.is_empty():return true
		charge_started=Time.get_ticks_msec()
		card.show()
		_send_charge("begin",selected.key)
	elif charge_started>0:
		var item:=selected
		_cancel()
		_send_charge("release" if item==_held() else "cancel",item.key)
	return true

func _process(_delta: float) -> void:
	if charge_started==0:return
	if not game.front.in_game or not game.player.enabled or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or selected!=_held():
		_cancel_charge()
		return
	var power:=_amount()
	meter.value=100.0*power
	caption.text="%s   ·   %d%%"%[selected.name,roundi(100.0*power)]

func _amount() -> float:
	return clampf((Time.get_ticks_msec()-charge_started)/1000.0/WINDUP,0.0,1.0)

func _cancel() -> void:
	selected={}
	charge_started=0
	card.hide()

func _clear() -> void:
	_cancel()
	launching=false
	windups.clear()
	pending.clear()
	for flight in flights.values():flight.queue_free()
	flights.clear()

func _cancel_charge() -> void:
	if charge_started>0:_send_charge("cancel",str(selected.get("key","")))
	_cancel()

func _item(key: String, visual: String, weight: float, label: String) -> Dictionary:
	return {"key":key,"visual":visual,"mass":weight,"name":label}

func _equipped(peer: int) -> Dictionary:
	var profile: Dictionary=game.carry_load.profile_for(peer)
	var dorm: Dictionary=profile.get("dorm",{})
	var belt: int=game.gym_barbells.held_belt(peer)
	if belt>=0:return _item("belt:"+str(belt),"belt",.8,"Weight belt")
	var plate: int=game.gym_barbells.held_plate(peer)
	if plate>=0:return _item("plate:"+str(plate),"plate",maxf(.5,Mass.gym_mass(peer,[],{},[],game.gym_barbells.plates)),"Weight plate")
	var bar: String=game.gym_barbells.held_bar(peer)
	if not bar.is_empty():return _item("bar:"+bar,"bar",maxf(20.0,Mass.gym_mass(peer,[],game.gym_barbells.bars,[],game.gym_barbells.plates)),"Barbell")
	var dumbbell: int=game.gym_weights.held_id(peer)
	if dumbbell>=0:return _item("weight:"+str(dumbbell),"weight",maxf(.5,float(game.gym_weights.items[dumbbell].get("lb",5))*Mass.LB_TO_KG*2.0),"Dumbbells")
	var paper: int=game.school.held(peer)
	if paper!=0:
		var supply:=str(game.school.papers.get(paper,{}).get("supply_id",""))
		var visual:=supply if not supply.is_empty() else "paper"
		return _item("sheet:"+str(paper),visual,Mass.supply_mass(dorm,visual),"Worksheet" if visual=="paper" else visual.capitalize())
	var board: int=game.dc_lab.held_board(peer)
	if board>=0:return _item("board:"+str(board),"pcb",maxf(.22,Mass.board_mass(game.dc_lab.states[board].get("board",{}))),"Circuit board")
	var laptop: int=game.ac_laptops.model.held_laptop(peer)
	if laptop>=0:return _item("lab_laptop","laptop",2.1,"Lab laptop")
	var cable: int=game.ac_laptops.model.held_cable(peer)
	if cable>=0 and game.ac_laptops.model.cables[cable].where=="held":return _item("lab_cable","wire_0",.06,"USB cable")
	if game.kit_world.held_by(peer):
		var id: String=game.kit_world.kits[peer].id
		return _item("kit:"+id,"kit_"+str(profile.get("kit_tiers",{}).get(id,"compact")),Mass.kit_mass(profile,id,{}),"Electronics kit")
	if game.school._holding_cable(peer):return _item("wire","wire_0",.06,"Lab lead")
	return {}

func _held() -> Dictionary:
	var peer:=multiplayer.get_unique_id()
	# Clients mirror lab laptop state for the selected hotbar entry.
	if not multiplayer.is_server():
		if game.ac_laptops._held("laptops")>=0:return _item("lab_laptop","laptop",2.1,"Lab laptop")
		if game.ac_laptops._held("cables")>=0:return _item("lab_cable","wire_0",.06,"USB cable")
	var equipped:=_equipped(peer)
	if not equipped.is_empty():return equipped
	var slot: int=game.hotbar.active
	if slot not in range(game.hotbar.slots.size()):return {}
	var item: Dictionary=game.hotbar.slots[slot]
	if item.is_empty():return {}
	var key:=str(item.get("dorm_item",""))
	if item.get("kind","")=="component":key="part:%s:%s:%d"%[item.type,item.instance,item.ordinal]
	if item.get("kind","")=="food":return _item("food:"+str(item.id),"food_"+str(item.get("food","")),.35,game.hotbar.title(item))
	if not multiplayer.is_server() and key.begins_with("kit:"):return _item(key,"kit_standard",.4,game.hotbar.title(item))
	return _inventory_item(peer,key)

func _inventory_item(peer: int,key: String) -> Dictionary:
	var profile: Dictionary=game.carry_load.profile_for(peer)
	var dorm: Dictionary=profile.get("dorm",{})
	if key.begins_with("food:"):
		var host=game.campus_services.facilities.controller.host
		var context: Dictionary=host.trusted(peer)
		if context.is_empty():return {}
		var order: Dictionary=host.profile(context).get("orders",{}).get(key.trim_prefix("food:"),{})
		if not order.is_empty() and str(order.get("station","")).is_empty():
			return _item(key,"food_"+str(order.item),.35,"Food or drink")
		return {}
	if key.begins_with("laptop:"):
		var id:=key.trim_prefix("laptop:")
		var laptop: Dictionary=dorm.get("portable_laptops",{}).get(id,{})
		if laptop.get("location","")=="hotbar" and key in dorm.get("carry_items",[]) and not game.portable_laptops.placed.has(id):
			return _item(key,"laptop",2.0,"Laptop")
		return {}
	if game.personal_placement.is_placed(peer,key):return {}
	var label: String=game.personal_placement._carried_label(peer,key,dorm)
	if label.is_empty():return {}
	if key.begins_with("part:"):return _item(key,"component:"+key.get_slice(":",1),Mass.component_mass(key.get_slice(":",1)),label)
	if key.begins_with("phone:"):return _item(key,"phone",.18,label)
	if key.begins_with("bag:"):
		var id:=key.get_slice(":",1)
		return _item(key,"bag_"+str(dorm.get("backpacks",{}).get(id,{}).get("size","backpack_small")),Mass.bag_mass(profile,id,{}),label)
	if key.begins_with("usb:"):return _item(key,"usb",.035,label)
	if Dress.is_notebook(key):return _item(key,"notebook",Mass.supply_mass(dorm,key),label)
	if Dress.is_calculator(key):return _item(key,Dress.Keypad.model_for(key),Mass.supply_mass(dorm,key),label)
	if Dress.PowerBanks.valid_key(key):return _item(key,"power_bank",Mass.supply_mass(dorm,key),label)
	return _item(key,key,Mass.supply_mass(dorm,key),label)

func _validated_item(peer: int,key: String) -> Dictionary:
	var item:=_equipped(peer)
	if not item.is_empty():return item if item.key==key else {}
	return _inventory_item(peer,key)

func _send_charge(op: String,key: String) -> void:
	if multiplayer.is_server():_charge_for(multiplayer.get_unique_id(),op,key)
	elif game.session.online:_charge_request.rpc_id(1,op,key)

@rpc("any_peer","call_remote","reliable")
func _charge_request(op: String,key: String) -> void:
	if multiplayer.is_server():_charge_for(multiplayer.get_remote_sender_id(),op,key)

func _charge_for(peer: int,op: String,key: String) -> void:
	if key.length()>160 or not game.session.roster.has(peer) or pending.has(peer):return
	if op=="cancel":
		windups.erase(peer)
		return
	if op not in ["begin","release"]:return
	var item:=_validated_item(peer,key)
	if item.is_empty() or game.health.locked(peer) or game.campus_services.facilities.controller.host.movement_locked(peer):
		windups.erase(peer)
		return
	var now:=Time.get_ticks_msec()
	if op=="begin":
		windups[peer]={"key":key,"start":now}
		return
	var charge: Dictionary=windups.get(peer,{})
	windups.erase(peer)
	if charge.get("key","")!=key:return
	_launch(peer,item,clampf((now-int(charge.start))/(1000.0*WINDUP),0.0,1.0))

static func throw_speed(power: float,strength: float,mass: float) -> float:
	return lerpf(3.0,12.0,power)*(1.0+strength*.70)/sqrt(1.0+mass*.28)

func _launch(peer: int,item: Dictionary,power: float) -> void:
	var local:=peer==multiplayer.get_unique_id()
	var pose: Dictionary=game.session.poses.get(peer,{})
	var feet: Vector3=game.player.global_position if local else pose.get("position",Vector3.INF)
	if not feet.is_finite():return
	var yaw: float=game.player.global_rotation.y if local else float(pose.get("yaw",0))
	var eye: float=1.16 if pose.get("seated",false) else (.95 if pose.get("crouch",false) else 1.65)
	var origin: Vector3=game.camera.global_position if local else feet+Vector3.UP*eye
	var aim: Vector3=-game.camera.global_basis.z if local else -Basis.from_euler(Vector3(float(pose.get("pitch",0)),yaw,0)).z
	var profile: Dictionary=game.carry_load.profile_for(peer)
	var strength:=Gym.lifting_strength(profile.get("facilities",{}).get("gym",{"muscles":{}}))
	var velocity:=aim*throw_speed(power,strength,float(item.mass))+Vector3.UP*1.1
	var path:=PackedVector3Array([origin])
	var landing:=Vector3.INF
	var space:=get_world_3d().direct_space_state
	for step in range(1,281):
		var time:=float(step)/40.0
		var point:=origin+velocity*time+GRAVITY*time*time*.5
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(path[-1],point,1))
		if hit.is_empty():
			path.append(point)
			continue
		if hit.normal.y>.8:
			landing=hit.position
			path.append(landing)
		else:
			var stop: Vector3=hit.position+(path[-1]-point).normalized()*.06
			path.append(stop)
			var below:=space.intersect_ray(PhysicsRayQueryParameters3D.create(stop,stop+Vector3.DOWN*8.0,1))
			if not below.is_empty() and below.normal.y>.8:
				landing=below.position
				var fall_steps:=maxi(1,ceili(sqrt(stop.distance_to(landing)*2.0/9.8)*40.0))
				for i in range(1,fall_steps+1):
					path.append(stop.lerp(landing,pow(float(i)/fall_steps,2.0)))
		break
	if not landing.is_finite():return
	var duration:=maxf(.12,(path.size()-1)/40.0)
	pending[peer]=path
	_show_flight(peer,str(item.visual),str(item.name),path,duration)
	if game.session.online:
		for other in game.session.connected_peers():_show_flight.rpc_id(other,peer,item.visual,item.name,path,duration)
	await get_tree().create_timer(duration,false).timeout
	if pending.get(peer)!=path:return
	pending.erase(peer)
	if not game.session.roster.has(peer) or _validated_item(peer,item.key).is_empty():return
	landing_peer=peer
	landing_point=landing
	_place_thrown(peer,item.key,landing,yaw)
	landing_peer=0
	landing_point=Vector3.INF

func is_landing(peer: int,point: Vector3) -> bool:
	return multiplayer.is_server() and peer==landing_peer and landing_point.distance_squared_to(point)<.0144

func _place_thrown(peer: int,key: String,point: Vector3,yaw: float) -> void:
	var table: bool=game.school._table_position(point,peer)
	var suffix:=key.get_slice(":",1)
	match key.get_slice(":",0):
		"belt":game.gym_barbells._accept_belt(peer,"drop",int(suffix),point)
		"plate":game.gym_barbells._accept_plate(peer,"drop",int(suffix),"",0,point)
		"bar":game.gym_barbells._accept(peer,"drop_bar",suffix,0.0,0,point)
		"weight":game.gym_weights._accept(peer,"drop",int(suffix),point)
		"lab_laptop":game.ac_laptops._apply(peer,"place_laptop",-1,point,-1)
		"lab_cable":game.ac_laptops._apply(peer,"drop_cable",-1,point,-1)
		"wire":game.school.apply(peer,{"op":"drop_floor_lead","position":point})
		"sheet":game.school.apply(peer,{"op":"drop","id":int(suffix),"position":point})
		"board":game.dc_lab.accept(peer,int(suffix),{"op":"place_board","position":point,"ground":not table})
		"kit":game.kit_world.apply(peer,{"op":"place" if table else "drop","position":point})
		"food":
			var controller: Node=game.campus_services.facilities.controller
			var host=controller.host
			var context: Dictionary=host.trusted(peer)
			if context.is_empty():return
			var profile: Dictionary=host.profile(context)
			var room: String=game.campus.registry.locate(point+Vector3.UP*.05)
			controller._deliver(peer,host.act(peer,{"op":"place","order_id":suffix,"position":point,"ground":not table,"sequence":int(profile.get("last_sequence",0))+1},room))
		"laptop":game.portable_laptops._place_for(peer,suffix,point,yaw)
		_:game.personal_placement._place(peer,key,point,yaw)

@rpc("authority","call_remote","reliable")
func _show_flight(peer: int,visual: String,label: String,path: PackedVector3Array,duration: float) -> void:
	if flights.has(peer):flights[peer].queue_free()
	var flying:=Node3D.new()
	flights[peer]=flying
	add_child(flying)
	flying.global_position=path[0]
	if visual=="phone":
		Handset.build(flying)
		flying.rotation.x=-PI*.5
	elif visual in ["belt","plate","bar","weight","power_bank"]:
		game._box(flying,Vector3.ZERO,Vector3(.15,.06,.10),Color("445559"))
	else:game.discarded_items._add_item_visual(flying,visual,{"label":label})
	var local:=peer==multiplayer.get_unique_id()
	if local:launching=true
	var tween:=flying.create_tween()
	tween.tween_method(func(progress: float):
		var index:=progress*(path.size()-1)
		var lower:=floori(index)
		flying.global_position=path[lower].lerp(path[mini(lower+1,path.size()-1)],index-lower)
		flying.rotation.z=progress*TAU,0.0,1.0,duration)
	await tween.finished
	if flights.get(peer)!=flying:return
	flights.erase(peer)
	flying.queue_free()
	if local:launching=false
