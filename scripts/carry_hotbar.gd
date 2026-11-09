extends CanvasLayer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const InventoryTheme = preload("res://scripts/ui/design_system/theme.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const Dorm = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const SUPPLY_RARITY := {
	"calculator":"Rare", "calculator_financial":"Uncommon", "flashlight":"Uncommon",
	"lab_goggles":"Uncommon", "whiteboard":"Rare",
	"backpack_medium":"Uncommon", "backpack_large":"Epic", "backpack_giant":"Legendary"
}
var portraits := preload("res://scripts/ui/personal_inventory/item_portraits.gd").new()
var game: Node
var slots: Array=[{},{},{},{},{},{}]
var active := -1
var bar: HBoxContainer
var buttons: Array=[]
var slot_icons: Array[TextureRect]=[]
var painted_slots: Array=[]
var painted_active := -2
var normal_style: StyleBoxFlat
var equipped_badges: Array[Label]=[]
var switching := false
var food_model: Node3D
var food_visual_key := ""
func build(owner_game: Node) -> void:
	game=owner_game;layer=11
	normal_style=InventoryTheme.card_style("Common")
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color=Color("9aefdd")
	badge_style.set_corner_radius_all(4)
	badge_style.content_margin_left=4
	badge_style.content_margin_right=4
	bar=HBoxContainer.new();bar.theme=InventoryTheme.create();bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);bar.position=Vector2(-276,-90);bar.add_theme_constant_override("separation",5);add_child(bar)
	for i in range(6):
		var b := Button.new();b.custom_minimum_size=Vector2(88,64);b.focus_mode=Control.FOCUS_ALL;bar.add_child(b);buttons.append(b);b.pressed.connect(func():select_slot(i))
		var icon := TextureRect.new()
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left=5
		icon.offset_top=3
		icon.offset_right=-5
		icon.offset_bottom=-3
		slot_icons.append(icon)
		var number := Label.new()
		number.text=str(i+1)
		number.mouse_filter=Control.MOUSE_FILTER_IGNORE
		number.position=Vector2(7,3)
		number.add_theme_font_size_override("font_size",11)
		b.add_child(number)
		var badge := Label.new()
		badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_size_override("font_size",9)
		badge.add_theme_color_override("font_color",Color("10292d"))
		badge.add_theme_stylebox_override("normal",badge_style)
		b.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.hide()
		equipped_badges.append(badge)
		b.add_theme_stylebox_override("normal",normal_style)
		painted_slots.append(null)
	game.session.restarted.connect(func():slots=[{},{},{},{},{},{}];active=-1)
func title(item: Dictionary) -> String:
	match item.get("kind",""):
		"food":return str(game.campus_services.facilities.controller.host.menu.get(item.type,{}).get("name","Food"))
		"notebook":return "Notebook"
		"calculator":return str(Dorm.TOOLS.get(item.get("type","calculator"),"Calculator"))
		"pencil_case":return "Pencil case"
		"lab_goggles":return "Lab goggles"
		"backpack":
			var bag: Dictionary=game.electronics.profile.data.get("dorm",{}).get("backpacks",{}).get(item.id,{})
			var size: Dictionary = Dorm.Backpacks.SIZES.get(bag.get("size",""),{})
			return "Backpack" if size.is_empty() else "%s  %d/%d" % [size.name,bag.items.size(),size.capacity]
		"paper":
			var paper: Dictionary=game.school.papers.get(int(item.id),{})
			return "Sheet" if paper.is_empty() else str(paper.project.title).left(22)
		"kit":
			var profile = game.electronics.profile
			return "%s  %d/%d" % [profile.data.kits.get(item.id,{}).get("name","Kit"),profile.kit_used(item.id),profile.kit_capacity(item.id)]
		"board":return "Custom PCB" if item.get("type","")=="pcb" else "Circuit board"
		"component":
			var catalog: Dictionary=game.electronics.profile.catalog()
			return str(catalog.get(item.type,{}).get("name",item.type))
		"wire":return ["Red cable","Blue cable","Yellow cable","Black cable"][int(item.color)]
		"dc_wire":return ["Red cable","Blue cable","Yellow cable","Black cable"][int(item.color)]
	return str(Dorm.TOOLS.get(item.get("kind",""),"Empty"))

func held_title() -> String:
	var kit: Dictionary = game.kit_world.kits.get(multiplayer.get_unique_id(),{})
	if kit.get("held",false):return title({"kind":"kit","id":kit.id})
	if active not in range(slots.size()) or slots[active].is_empty():return ""
	if slots[active].get("kind")=="kit":return ""
	return title(slots[active])

func item_rarity(item: Dictionary) -> String:
	var kind := str(item.get("kind",""))
	var item_type := str(item.get("type",kind))
	match kind:
		"kit":
			var profile = game.electronics.profile
			var tier: String = profile.data.get("kit_tiers",{}).get(item.get("id",""),"standard")
			return str(profile.KIT_TIERS.get(tier,{}).get("rarity","Common"))
		"backpack":
			if item_type == kind:
				var bags: Dictionary = game.electronics.profile.data.get("dorm",{}).get("backpacks",{})
				item_type = str(bags.get(item.get("id",""),{}).get("size",""))
		"component":
			var catalog: Dictionary = game.electronics.profile.catalog()
			var rarity := str(catalog.get(item_type,{}).get("rarity","Common")).capitalize()
			return rarity if rarity in ["Common","Uncommon","Rare","Epic","Legendary"] else "Rare"
		"board":
			return "Rare" if item_type == "pcb" else "Common"
	return SUPPLY_RARITY.get(item_type,"Common")

func style_inventory_tile(tile: Button, item: Dictionary, selected := false) -> void:
	if item.is_empty():return
	var rarity := item_rarity(item)
	tile.tooltip_text = "%s · %s" % [tile.text,rarity]
	tile.text += "\n" + rarity
	tile.add_theme_stylebox_override("normal",InventoryTheme.card_style(rarity,selected))
	tile.add_theme_color_override("font_color",Tokens.rarity_color(rarity))
func has_item(kind: String) -> bool:
	for item in slots:
		if item.get("kind")==kind:return true
	return false

func calculator_type() -> String:
	for item in slots:
		if item.get("kind")=="calculator":return str(item.get("type","calculator"))
	return ""

func _sync_dorm_items() -> void:
	var dorm: Dictionary = game.electronics.profile.data.get("dorm",{})
	var carried: Array = dorm.get("carry_items",[]).duplicate()
	if is_instance_valid(game.kit_world):
		for key in carried.duplicate():
			if key.begins_with("kit:") and game.kit_world.is_placed(multiplayer.get_unique_id(),key.trim_prefix("kit:")):carried.erase(key)
	var components: Array = []
	var quantities := {}
	for part in dorm.get("carried_components",[]):
		var key := str(part.type)+"/"+str(part.instance)
		var ordinal := int(quantities.get(key,0))
		quantities[key]=ordinal+1
		components.append({"kind":"component","type":part.type,"instance":part.instance,"ordinal":ordinal})
	for index in range(slots.size()):
		var key := str(slots[index].get("dorm_item",""))
		var stored_kit: bool = slots[index].get("kind")=="kit" and slots[index].get("id") in dorm.get("stored_kits",[])
		if (not key.is_empty() and key not in carried) or stored_kit or (slots[index].get("kind")=="component" and slots[index] not in components):
			slots[index]={}
			if active==index:active=-1
	for key in carried:
		if key.begins_with("kit:"):
			if game.electronics.profile.data.get("kits",{}).has(key.trim_prefix("kit:")):
				add_item({"kind":"kit","id":key.trim_prefix("kit:"),"dorm_item":key})
		elif key in Dorm.CALCULATORS:
			add_item({"kind":"calculator","type":key,"dorm_item":key})
		elif key.begins_with("bag:"):
			add_item({"kind":"backpack","id":key.trim_prefix("bag:"),"dorm_item":key})
		else:add_item({"kind":key,"dorm_item":key})
	for part in components:add_item(part)
func add_item(item: Dictionary) -> int:
	for i in range(6):
		if slots[i]==item:return i
	for i in range(6):
		if slots[i].is_empty():slots[i]=item;return i
	return -1
func _process(_delta: float) -> void:
	if not is_instance_valid(game):return
	bar.visible=game.front.in_game and game.player.enabled
	if not game.front.in_game:
		if is_instance_valid(food_model):food_model.hide()
		return
	_sync_dorm_items()
	for i in range(6):
		var slot: Dictionary = slots[i]
		if slot.get("kind") == "wire" and int(slot.station) in range(game.station_snapshots.size()):
			var station: Dictionary = game.station_snapshots[int(slot.station)]
			var peer := multiplayer.get_unique_id()
			var stashed: Dictionary = station.get("stored_cables", {})
			var held: bool = station.get("cables", []).any(func(cable): return int(cable.owner) == peer and int(cable.color) == int(slot.color))
			if not held and int(slot.color) not in stashed.get(peer, stashed.get(str(peer), [])):
				slots[i] = {}
				if active == i: active = -1
		elif slot.get("kind") == "dc_wire":
			var key := Vector2i(int(slot.station), int(slot.color))
			var held_key := Vector2i(game.dc_lab.picked_station, game.dc_lab.lead_color)
			if key != held_key and not game.dc_lab.local_stowed_leads.has(key) and not game.dc_lab.hotbar_lead_pending:
				slots[i] = {}
				if active == i: active = -1
		if slots[i].get("kind")=="paper":
			var paper: Dictionary=game.school.papers.get(int(slots[i].id),{})
			if paper.is_empty() or int(paper.get("owner",0))!=multiplayer.get_unique_id() or (not paper.get("held",false) and not paper.get("stowed",false)):
				slots[i]={}
				if active==i:active=-1
		if slots[i].get("kind")=="board":
			var state: Dictionary = game.dc_lab.states[int(slots[i].id)]
			if state.get("board_owner",0)!=multiplayer.get_unique_id() or (not state.get("board_held",false) and not state.get("board_stowed",false)):
				slots[i]={}
				if active==i:active=-1
			elif state.get("board",{}).get("standalone",false):
				slots[i]["type"]="pcb"
	var held_board: int=game.dc_lab.held_board()
	for index in game.dc_lab.states.size():
		var state: Dictionary = game.dc_lab.states[index]
		if state.get("board_owner",0)==multiplayer.get_unique_id() and state.get("board_stowed",false):
			add_item(_board_item(index))
	if held_board>=0:
		var index := add_item(_board_item(held_board))
		if index>=0:active=index
	var held: int=game.school.held(multiplayer.get_unique_id())
	if held!=0:
		var document: Dictionary = game.school.papers.get(held,{})
		var supply := Dorm.paper_supply(document)
		var index := -1
		if supply.is_empty():
			index = add_item({"kind":"paper","id":held})
		else:
			for i in slots.size():
				if slots[i].get("dorm_item")==supply:index=i;break
		if index>=0:active=index
	for station in game.station_snapshots.size():
		var stashed: Dictionary=game.station_snapshots[station].get("stored_cables",{})
		for color in stashed.get(multiplayer.get_unique_id(),stashed.get(str(multiplayer.get_unique_id()),[])):
			add_item({"kind":"wire","color":int(color),"station":station})
		for cable in game.station_snapshots[station].get("cables",[]):
			if int(cable.owner)==multiplayer.get_unique_id():
				var index := add_item({"kind":"wire","color":int(cable.color),"station":station})
				if index>=0:active=index
	for key in game.dc_lab.local_stowed_leads:
		add_item({"kind":"dc_wire","color":key.y,"station":key.x})
	if game.dc_lab.lead_color>=0:
		var index := add_item({"kind":"dc_wire","color":game.dc_lab.lead_color,"station":game.dc_lab.picked_station})
		if index>=0:active=index
	_sync_food()
	var held_kit: Dictionary=game.kit_world.kits.get(multiplayer.get_unique_id(),{})
	if held_kit.get("held",false):
		for i in slots.size():
			if slots[i].get("kind")=="kit" and slots[i].get("id")==held_kit.id:
				active=i
				break
	var hotbar_used := 0
	for slot in slots:
		if not slot.is_empty():hotbar_used+=1
	game.player.load_speed=Dorm.Backpacks.speed_multiplier(game.electronics.profile.data.get("dorm",{}),hotbar_used,slots.size())
	if bar.visible:_paint_slots()

func selected_food() -> Dictionary:
	if active >= 0 and slots[active].get("kind") == "food":return slots[active]
	return {}

func _sync_food() -> void:
	var orders: Dictionary=game.campus_services.facility_panel.state.get("profile",{}).get("orders",{})
	for i in slots.size():
		if slots[i].get("kind")!="food":continue
		var order: Dictionary=orders.get(slots[i].get("id",""),{})
		if order.is_empty() or order.station!="":
			slots[i]={}
			if active==i:active=-1
	for id in orders:
		var order: Dictionary=orders[id]
		if order.station=="":add_item({"kind":"food","id":id,"type":order.item})
	var held: Dictionary=orders.get(selected_food().get("id",""),{})
	var item := str(held.get("item",""))
	var key := "%s:%d" % [item,int(held.get("servings",0))] if not held.is_empty() else ""
	if key!=food_visual_key:
		food_visual_key=key
		if is_instance_valid(food_model):food_model.queue_free()
		food_model=null
		if key!="":
			food_model=preload("res://scripts/campus/facilities/food_visual.gd").build(item,int(held.servings))
			game.camera.add_child(food_model)
	if is_instance_valid(food_model):
		food_model.visible=game.player.enabled
		var grip: Vector3=game.held_item_position(multiplayer.get_unique_id(),game.camera.to_global(Vector3(.22,-.22,-.48)))
		food_model.global_position=grip+game.camera.global_basis*Vector3(-.035,.015,-.055)

func _board_item(index: int) -> Dictionary:
	var item := {"kind":"board","id":index}
	if game.dc_lab.states[index].get("board",{}).get("standalone",false):item.type="pcb"
	return item

func _paint_slots() -> void:
	for i in slots.size():
		var item: Dictionary=slots[i]
		var changed: bool=painted_slots[i]!=item
		if changed:
			slot_icons[i].texture=portraits.texture(item,game.electronics.profile)
			painted_slots[i]=item.duplicate()
		var selection_changed := active!=painted_active and (active==i or painted_active==i)
		if changed or selection_changed:
			var style := normal_style
			if not item.is_empty():
				style=InventoryTheme.card_style(item_rarity(item))
			buttons[i].add_theme_stylebox_override("normal",style)
			var badge := equipped_badges[i]
			badge.text="SELECTED" if item.is_empty() else "EQUIPPED"
			badge.reset_size()
			badge.position=Vector2(buttons[i].size.x-badge.size.x-5,4)
			badge.visible=active==i
		if changed or selection_changed or item.get("kind","") in ["paper","kit"]:
			var hint := "Key %d · %s"%[i+1,title(item)]
			if not item.is_empty():hint+=" · "+item_rarity(item)
			if buttons[i].tooltip_text!=hint:buttons[i].tooltip_text=hint
	painted_active=active
func stow() -> bool:
	if game.dc_lab.lead_color>=0:
		if add_item({"kind":"dc_wire","color":game.dc_lab.lead_color,"station":game.dc_lab.picked_station})<0:
			game.ui.log_message("All six slots are full. Return the cable or free a slot first.")
			return false
		game.dc_lab.stow_hotbar_lead()
	var board: int=game.dc_lab.held_board()
	if board>=0:
		if add_item(_board_item(board))<0:game.ui.log_message("All six slots are full. Put the board down first.");return false
		game.dc_lab.request(board,{"op":"stow_board"})
	if is_instance_valid(game.kit_world) and game.kit_world.held():game.kit_world.request({"op":"stow"})
	var peer := multiplayer.get_unique_id()
	for i in game.station_snapshots.size():
		for cable in game.station_snapshots[i].get("cables",[]):
			if cable.owner==peer:
				if cable.a!="" or cable.b!="":game.ui.log_message("Unplug the other end or press G before storing this cable.");return false
				if add_item({"kind":"wire","color":int(cable.color),"station":i})<0:game.ui.log_message("All six slots are full. Manage your loadout first.");return false
				game.session.request({"op":"stash","station":i})
	var held: int=game.school.held(peer)
	if held!=0:game.school.request({"op":"stow","id":held})
	return true
func select_slot(index: int) -> void:
	if switching or index<0 or index>=6:return
	switching=true
	if not stow():switching=false;return
	await get_tree().create_timer(.12).timeout
	for _attempt in range(20):
		if not game.dc_lab.hotbar_lead_pending:break
		await get_tree().create_timer(.1).timeout
	if game.dc_lab.hotbar_lead_pending or game.dc_lab.lead_color>=0:
		switching=false
		return
	if active==index:active=-1;switching=false;return
	active=index;var item: Dictionary=slots[index]
	match item.get("kind",""):
		"component":
			var dialog := ConfirmationDialog.new()
			dialog.title=title(item)
			dialog.dialog_text="Move this component to your available inventory for kit and board builds?"
			dialog.ok_button_text="Move to inventory"
			dialog.confirmed.connect(func():
				active=-1
				game.dorm_interactions.component_transfer(str(item.type),str(item.instance),"release_component")
				dialog.queue_free()
				game.capture())
			dialog.canceled.connect(func():active=-1;dialog.queue_free();game.capture())
			game.ui.add_child(dialog)
			game.release_mouse()
			dialog.popup_centered()
		"notebook", "calculator", "pencil_case", "lab_goggles", "backpack", "flashlight", "marker", "whiteboard":
			var kind := str(item.get("dorm_item",item.get("type",item.kind)))
			for document in game.school.papers.values():
				if document.owner==multiplayer.get_unique_id() and Dorm.paper_supply(document)==kind and not document.get("supply_released",false):
					game.school.request({"op":"equip_paper","id":int(document.id)})
					switching=false
					return
			game.school.request({"op":kind})
		"board":game.dc_lab.request(int(item.id),{"op":"carry_board"})
		"paper":game.school.request({"op":"equip_paper","id":int(item.id)})
		"wire":game.session.request({"op":"unstash","station":int(item.station),"color":int(item.color)})
		"dc_wire":
			active=-1
			game.dc_lab.equip_hotbar_lead(int(item.station),int(item.color))
		"kit":game.electronics.profile.data.equipped=item.id;game.electronics.profile.save();game.kit_world.request({"op":"equip","id":item.id,"name":game.electronics.profile.data.kits[item.id].name})
	switching=false
func manager(parent: Node) -> void:
	_sync_dorm_items()
	parent.theme=InventoryTheme.create()
	var dorm: Dictionary=game.electronics.profile.data.get("dorm",{})
	var back_id := Dorm.Backpacks.equipped(dorm)
	parent.add_child(UI.text("Hotbar","SubtitleLabel"))
	var hotbar_grid := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
	hotbar_grid.minimum_card_width=120
	hotbar_grid.maximum_columns=6
	parent.add_child(hotbar_grid)
	for index in slots.size():
		var item: Dictionary=slots[index]
		var card := VBoxContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		hotbar_grid.add_child(card)
		var tile := UI.action("%d  ·  %s" % [index+1,title(item)],"inventory",Callable())
		tile.icon=portraits.texture(item,game.electronics.profile)
		tile.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
		tile.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		tile.custom_minimum_size=Vector2(115,94)
		tile.add_theme_constant_override("icon_max_width",58)
		tile.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		style_inventory_tile(tile,item)
		if active==index and not item.is_empty():tile.text+=" · Equipped"
		tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_child(tile)
		tile.set_drag_forwarding(_drag_hotbar_slot.bind(tile,index),_can_drop_hotbar_slot.bind(index),_drop_hotbar_slot.bind(index))
		var discard_entry := _pack_entry(item)
		if item.get("kind","") in ["paper","wire","dc_wire","food","board"]:discard_entry=item.duplicate()
		if not discard_entry.is_empty():
			tile.tooltip_text+="\nRight click for options"
			var equip := _equip_inventory_slot.bind(index,item)
			if item.kind=="lab_goggles":equip=_toggle_goggles.bind(true)
			elif item.kind=="backpack":equip=_bag_intent.bind({"op":"bag_move","bag":item.id,"destination":"back"})
			tile.gui_input.connect(_item_menu.bind(tile,item,{"location":"hotbar","item":discard_entry},equip))
		if not back_id.is_empty():
			var entry := _pack_entry(item)
			if not entry.is_empty():
				card.add_child(UI.action("Pack","plus",_bag_intent.bind({"op":"bag_pack","bag":back_id,"item":entry})))
	parent.add_child(UI.text("Body accessories","SubtitleLabel"))
	var accessories := HBoxContainer.new()
	parent.add_child(accessories)
	var goggles_on: bool=dorm.get("worn_supplies",{}).get("head","")=="lab_goggles"
	var head_item := {"kind":"lab_goggles"} if goggles_on else {}
	var back_item := {"kind":"backpack","id":back_id,"type":dorm.backpacks[back_id].size} if not back_id.is_empty() else {}
	_accessory_tile(accessories,"Head","user",head_item,_toggle_goggles.bind(false),{"location":"head","item":{"kind":"supply","id":"lab_goggles"}})
	_accessory_tile(accessories,"Back","inventory",back_item,_bag_intent.bind({"op":"bag_move","bag":back_id,"destination":"hotbar"}),{"location":"back","item":{"kind":"bag","id":back_id}})
	if not back_id.is_empty():
		var bag: Dictionary=dorm.backpacks[back_id]
		var capacity: int=Dorm.Backpacks.SIZES[bag.size].capacity
		parent.add_child(UI.text("Backpack  ·  %d / %d slots" % [bag.items.size(),capacity],"SubtitleLabel"))
		var contents := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
		contents.minimum_card_width=105
		contents.maximum_columns=8
		parent.add_child(contents)
		for index in capacity:
			var item: Dictionary=_unpack_item(bag.items[index]) if index<bag.items.size() else {}
			var slot := UI.action(title(item) if not item.is_empty() else str(index+1),"inventory",_bag_intent.bind({"op":"bag_unpack","bag":back_id,"slot":index}))
			slot.icon=portraits.texture(item,game.electronics.profile)
			slot.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
			slot.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
			slot.custom_minimum_size.y=68
			slot.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			slot.disabled=item.is_empty()
			style_inventory_tile(slot,item)
			slot.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			contents.add_child(slot)
			if not item.is_empty():
				slot.gui_input.connect(_item_menu.bind(slot,item,{"location":"packed","bag":back_id,"slot":index,"item":bag.items[index]},Callable()))

func _drag_hotbar_slot(_position: Vector2, tile: Button, index: int) -> Variant:
	if switching or slots[index].is_empty():return null
	var preview := Label.new()
	preview.text=title(slots[index])
	tile.set_drag_preview(preview)
	return {"hotbar_slot":index,"item":slots[index].duplicate()}

func _can_drop_hotbar_slot(_position: Vector2, data: Variant, destination: int) -> bool:
	if switching or not data is Dictionary:return false
	var source := int(data.get("hotbar_slot",-1))
	return source in range(slots.size()) and source!=destination and not slots[source].is_empty() and slots[source]==data.get("item")

func _drop_hotbar_slot(position: Vector2, data: Variant, destination: int) -> void:
	if not _can_drop_hotbar_slot(position,data,destination):return
	var source: int=data.hotbar_slot
	var item: Dictionary=slots[source]
	slots[source]=slots[destination]
	slots[destination]=item
	if active==source:active=destination
	elif active==destination:active=source
	game.electronics.open.call_deferred("inventory",game.electronics.bench)

func _equip_inventory_slot(index: int, item: Dictionary) -> void:
	if slots[index]!=item or active==index:return
	game.electronics.close()
	select_slot(index)

func _item_menu(event: InputEvent, tile: Button, item: Dictionary, source: Dictionary, equip: Callable) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_RIGHT:return
	tile.accept_event()
	var menu := PopupMenu.new()
	tile.add_child(menu)
	if equip.is_valid():menu.add_item("Equip",0)
	menu.add_item("Discard",1)
	menu.id_pressed.connect(func(id: int):
		if id==0:equip.call()
		else:_confirm_discard(title(item),source))
	menu.popup_hide.connect(menu.queue_free)
	menu.position=Vector2i(get_viewport().get_mouse_position())
	menu.popup()

func _confirm_discard(item_title: String, source: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title="Discard item?"
	dialog.dialog_text="%s will drop on the ground. Anyone can pick it up for two minutes." % item_title
	dialog.ok_button_text="Yes, discard"
	dialog.cancel_button_text="No"
	game.electronics.screen.add_child(dialog)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		game.discarded_items.discard(source))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _accessory_tile(parent: Control, slot_name: String, icon_key: String, item: Dictionary, remove: Callable, source: Dictionary) -> void:
	var tile := UI.action(slot_name+" · "+("Empty" if item.is_empty() else title(item)),icon_key,remove)
	if not item.is_empty():
		tile.icon=portraits.texture(item,game.electronics.profile)
		style_inventory_tile(tile,item)
		tile.tooltip_text+="\nClick to return to hotbar"
		tile.gui_input.connect(_item_menu.bind(tile,item,source,Callable()))
	tile.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
	tile.add_theme_constant_override("icon_max_width",58)
	tile.custom_minimum_size.y=94
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tile.disabled=item.is_empty()
	parent.add_child(tile)

func _pack_entry(item: Dictionary) -> Dictionary:
	var key := str(item.get("dorm_item",""))
	match item.get("kind",""):
		"backpack":return {"kind":"bag","id":item.id}
		"kit":
			if not key.is_empty():return {"kind":"kit","id":item.id}
		"component":return {"kind":"component","type":item.type,"instance":item.instance}
		_:
			if Dorm.TOOLS.has(key):return {"kind":"supply","id":key}
	return {}

func _unpack_item(entry: Dictionary) -> Dictionary:
	if entry.kind=="supply":return {"kind":"calculator" if entry.id in Dorm.CALCULATORS else entry.id,"type":entry.id}
	if entry.kind=="bag":return {"kind":"backpack","id":entry.id}
	return entry

func _bag_intent(intent: Dictionary, show_inventory := true) -> void:
	if not stow():return
	var dorm: Dictionary=game.electronics.profile.data.get("dorm",{})
	intent=intent.duplicate(true)
	intent.revision=int(dorm.get("revision",-1))
	var result: Dictionary=game.dorm_interactions.submit_intent(Crypto.new().generate_random_bytes(16).hex_encode(),intent)
	if not show_inventory:
		if not result.get("ok",false) and not result.get("pending",false):
			game.ui.log_message(str(result.get("error","Backpack move failed")))
		return
	if result.get("ok",false):game.electronics.open("inventory")
	elif result.get("pending",false):game.electronics.status.text="Waiting for host…"
	else:game.electronics.status.text=str(result.get("error","Backpack move failed"))

func _toggle_goggles(wear: bool, show_inventory := true) -> void:
	if not wear and {} not in slots:
		game.electronics.status.text="Free a hotbar slot first."
		return
	if wear and not stow():return
	var dorm: Dictionary=game.electronics.profile.data.get("dorm",{})
	var result: Dictionary=game.dorm_interactions.submit_intent(Crypto.new().generate_random_bytes(16).hex_encode(),{"op":"wear_goggles","wear":wear,"revision":int(dorm.get("revision",-1))})
	if not show_inventory:
		if not result.get("ok",false) and not result.get("pending",false):
			game.ui.log_message(str(result.get("error","Could not equip goggles")))
		return
	if result.get("pending",false):
		game.electronics.status.text="Waiting for host…"
	elif result.get("ok",false):
		game.electronics.open("inventory")
	else:
		game.electronics.status.text=str(result.get("error","Could not change head accessory."))
