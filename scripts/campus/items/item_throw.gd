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
var flight: Node3D

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

func route(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and charge_started>0:
		_cancel()
		return true
	if not event is InputEventKey or event.physical_keycode!=game.player.keys.throw_item:return false
	if not game.front.in_game or not game.player.enabled or game.player.inspecting or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		_cancel()
		return false
	if event.echo or launching:return true
	if event.pressed:
		selected=_held()
		if selected.is_empty():return true
		charge_started=Time.get_ticks_msec()
		card.show()
	elif charge_started>0:
		var power:=_amount()
		var item:=selected
		_cancel()
		if item==_held():_launch(item,power)
	return true

func _process(_delta: float) -> void:
	if charge_started==0:return
	if not game.front.in_game or not game.player.enabled or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or selected!=_held():
		_cancel()
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
	if is_instance_valid(flight):flight.queue_free()
	flight=null

func _item(key: String, visual: String, weight: float, label: String) -> Dictionary:
	return {"key":key,"visual":visual,"mass":weight,"name":label}

func _held() -> Dictionary:
	var peer:=multiplayer.get_unique_id()
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
	var board: int=game.dc_lab.held_board()
	if board>=0:return _item("board:"+str(board),"pcb",.45,"Circuit board")
	if game.ac_laptops._held("laptops")>=0:return _item("lab_laptop","laptop",2.1,"Lab laptop")
	if game.ac_laptops._held("cables")>=0:return _item("lab_cable","wire_0",.06,"USB cable")
	if game.school._holding_cable(peer):return _item("wire","wire_0",.06,"Lab lead")
	var slot: int=game.hotbar.active
	if slot not in range(game.hotbar.slots.size()):return {}
	var item: Dictionary=game.hotbar.slots[slot]
	if item.is_empty():return {}
	var key:=str(item.get("dorm_item",""))
	var label: String=game.hotbar.title(item)
	if item.get("kind","")=="component":return _item("part:%s:%s:%d"%[item.type,item.instance,item.ordinal],"component:"+str(item.type),Mass.component_mass(item.type),label)
	if item.get("kind","")=="food":return _item("food:"+str(item.id),"food_"+str(item.get("food","")), .35,label)
	if key.begins_with("kit:"):return _item(key,"kit_"+str(profile.get("kit_tiers",{}).get(key.get_slice(":",1),"compact")),Mass.kit_mass(profile,key.get_slice(":",1),{}),label)
	if key.begins_with("laptop:"):return _item(key,"laptop",2.0,label)
	if key.begins_with("phone:"):return _item(key,"phone",.18,label)
	if key.begins_with("bag:"):
		var id:=key.get_slice(":",1)
		return _item(key,"bag_"+str(dorm.get("backpacks",{}).get(id,{}).get("size","backpack_small")),Mass.bag_mass(profile,id,{}),label)
	if key.begins_with("usb:"):return _item(key,"usb",.035,label)
	if Dress.is_notebook(key):return _item(key,"notebook",Mass.supply_mass(dorm,key),label)
	if Dress.is_calculator(key):return _item(key,Dress.Keypad.model_for(key),Mass.supply_mass(dorm,key),label)
	if Dress.PowerBanks.valid_key(key):return _item(key,"power_bank",Mass.supply_mass(dorm,key),label)
	return _item(key,key,Mass.supply_mass(dorm,key),label) if not key.is_empty() else {}

func _launch(item: Dictionary,power: float) -> void:
	var profile: Dictionary=game.carry_load.profile_for(multiplayer.get_unique_id())
	var strength:=Gym.overall_strength(profile.get("facilities",{}).get("gym",{"muscles":{}}))
	var speed: float=lerpf(3.0,12.0,power)*(1.0+strength*.70)/sqrt(1.0+float(item.mass)*.28)
	var aim: Vector3=-game.camera.global_basis.z
	var origin: Vector3=game.camera.global_position+aim*.31
	var velocity:=aim*speed+Vector3.UP*1.1
	var feet: Vector3=game.player.global_position
	var path: Array[Vector3]=[origin]
	var landing: Dictionary={}
	var length:=0
	var portable: bool=item.key.begins_with("laptop:") or item.key.begins_with("phone:") or item.key.begins_with("usb:") or item.key.begins_with("bag:") or item.key.begins_with("part:") or item.key in profile.get("dorm",{}).get("carry_items",[]) and not item.key.begins_with("kit:")
	var reach:=8.0 if portable and multiplayer.is_server() else 1.7
	for step in range(1,61):
		var time:=float(step)/40.0
		var point:=origin+velocity*time+GRAVITY*time*time*.5
		var hit:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(path[-1],point,1))
		if not hit.is_empty():
			point=hit.position
			if hit.normal.y>.80 and feet.distance_to(point)<=reach:
				landing={"position":point,"table":hit.collider.get_meta("role","")=="table","throw_range":reach}
		if feet.distance_to(point)>reach:break
		path.append(point)
		length=step
		if not hit.is_empty():break
	if landing.is_empty():
		var last:=path.back() as Vector3
		var ground: Variant=game.school.ground_drop_position(last,multiplayer.get_unique_id())
		if ground is Vector3 and feet.distance_to(ground)<=reach:
			landing={"position":ground,"table":false,"throw_range":reach}
	if landing.is_empty():return
	flight=Node3D.new()
	add_child(flight)
	flight.global_position=origin
	if item.visual=="phone":
		Handset.build(flight)
		flight.rotation.x=-PI*.5
	elif item.visual in ["belt","plate","bar","weight","power_bank"]:
		game._box(flight,Vector3.ZERO,Vector3(.15,.06,.10),Color("445559"))
	else:game.discarded_items._add_item_visual(flight,item.visual,{"label":item.name})
	launching=true
	var duration:=maxf(.12,length/40.0)
	var tween:=flight.create_tween().set_parallel()
	tween.tween_method(func(progress: float):
		var index:=progress*(path.size()-1)
		var lower:=floori(index)
		flight.global_position=path[lower].lerp(path[mini(lower+1,path.size()-1)],index-lower)
		flight.rotation.z=progress*TAU,0.0,1.0,duration)
	await tween.finished
	if not is_instance_valid(flight):return
	flight.queue_free()
	flight=null
	launching=false
	if item==_held():game._place_held_item(landing)
