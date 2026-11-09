extends PanelContainer
signal chosen(type_id: String, instance_id: String)
signal lab_lead_chosen(port: String)
signal source_changed
signal closed
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Query = preload("res://scripts/electronics/inventory_value_search/query.gd")
const Values = preload("res://scripts/electronics/component_values/values.gd")
const CATEGORIES = ["All", "Basic", "Resistors", "Potentiometers", "Capacitors", "Inductors", "LEDs", "ICs", "PCBs", "Input devices", "Output devices"]
const Debug = preload("res://scripts/electronics/circuit_workspace/debug_instruments.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const Artwork = preload("res://scripts/electronics/component_shop_ui/catalog_presentation.gd")
const VARIABLE_FAMILIES := {"R":"Resistors","pot":"Potentiometers","C":"Capacitors","polar_cap":"Capacitors","variable_cap":"Capacitors","L":"Inductors","variable_inductor":"Inductors"}
var profile := {}
var catalog := {}
var limits := {}
var creative := false
var family := "All"
var search: LineEdit
var rows: VBoxContainer
var filters: HFlowContainer
var feedback: Label
var persistent := false
var back: Button
var debug_source := false
var physical_kit := false
var lab_leads := {}
var placed := {}
var placed_instances := {}
var placing_type := ""
var placing_instance := ""

func set_board(board: Dictionary) -> void:
	var counts := {}
	var instances := {}
	var bindings: Dictionary=board.get("instance_ids",{})
	for part in board.get("parts",[]):
		counts[part.type]=int(counts.get(part.type,0))+1
		var instance := str(bindings.get(str(part.id),""))
		if not instance.is_empty():instances[instance]=true
	if placed==counts and placed_instances==instances:return
	placed=counts
	placed_instances=instances
	_refresh()

func set_placing(type_id: String, instance_id: String) -> void:
	placing_type=type_id
	placing_instance=instance_id
	if not is_instance_valid(rows):return
	for button in rows.get_children():
		if button is Button:_style_placement(button)

func _style_placement(button: Button) -> void:
	var category := str(button.get_meta("placement_group",""))
	var active_group := not category.is_empty() and category==str(VARIABLE_FAMILIES.get(catalog.get(placing_type,{}).get("kind",""),""))
	var active_part: bool = not placing_type.is_empty() and button.get_meta("placement_type","")==placing_type and button.get_meta("placement_instance","")==placing_instance
	_compact_style(button,active_group or active_part)

func _remaining(type_id: String, available: int, instance_id := "") -> int:
	if not instance_id.is_empty():return 0 if placed_instances.has(instance_id) else available
	return maxi(0,available-int(placed.get(type_id,0)))

func _available_count(type_id: String) -> int:
	if physical_kit:return int(limits.get(type_id,0))
	var owned := int(profile.get("inventory",{}).get(type_id,0))
	return owned if limits.is_empty() else mini(owned,int(limits.get(type_id,0)))

func _shows_variant(entry: Dictionary, available: int) -> bool:
	return available > 0 or (creative and not entry.get("archived", false))

func _ready() -> void:
	custom_minimum_size = Vector2.ZERO if persistent else Vector2(340, 320)
	clip_contents = persistent
	var root := VBoxContainer.new();add_child(root)
	if persistent:
		add_theme_stylebox_override("panel",Tokens.surface(Tokens.SURFACE,Tokens.BORDER,8))
		root.add_theme_constant_override("separation",5)
		var source := OptionButton.new()
		source.accessibility_name="Component source"
		source.add_item("Components")
		source.add_item("Connected lab wires" if physical_kit else "Debug components")
		_compact_style(source)
		source.item_selected.connect(_change_source)
		root.add_child(source)
	else:
		root.add_child(UI.header("Add component", "Choose an owned part, then choose its mounting holes.", close_picker))
	search = LineEdit.new();search.placeholder_text="Search name or value";search.accessibility_name="Search components";root.add_child(search)
	if persistent:
		search.add_theme_font_size_override("font_size",14)
		search.add_theme_stylebox_override("normal",Tokens.surface(Color("0d202c"),Tokens.BORDER,5))
	search.text_changed.connect(func(_value):_refresh())
	if persistent:
		back=Button.new()
		back.icon=UI.icon("back")
		back.expand_icon=true
		back.alignment=HORIZONTAL_ALIGNMENT_LEFT
		_compact_style(back)
		back.pressed.connect(func():
			family="All"
			_refresh())
		root.add_child(back)
	else:
		filters = HFlowContainer.new()
		root.add_child(filters)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size.y=80 if persistent else 220;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	if persistent:rows.add_theme_constant_override("separation",3)
	feedback=UI.text("", "MutedLabel");root.add_child(feedback)
	hide()

func configure(source_profile: Dictionary, source_catalog: Dictionary, kit_limits: Dictionary = {}, free_placement: bool = false) -> void:
	profile=source_profile.duplicate(true);catalog=source_catalog.duplicate(true);limits=kit_limits.duplicate(true);creative=free_placement
	if is_node_ready():_refresh_filters();_refresh()

func open_picker() -> void:
	if not is_node_ready():return
	show();_refresh_filters();_refresh();search.grab_focus()

func close_picker() -> void:
	hide();closed.emit()

func _change_source(index: int) -> void:
	debug_source=index==1
	family="All"
	search.clear()
	search.placeholder_text=("Search lab wires" if physical_kit else "Search debug components") if debug_source else "Search name or value"
	source_changed.emit()
	_refresh()

func _compact_style(control: Control, active := false) -> void:
	control.custom_minimum_size.y=30
	control.add_theme_font_size_override("font_size",14)
	control.add_theme_constant_override("icon_max_width",20)
	for state in ["normal","hover","pressed","hover_pressed"]:
		var fill := Color("285c59") if active else Tokens.RAISED if state=="normal" else Color("284956")
		var style := Tokens.surface(fill,Tokens.ACCENT if active else Tokens.BORDER,4)
		style.set_corner_radius_all(5)
		control.add_theme_stylebox_override(state,style)

func _compact_row(title: String, detail: String, entry: Dictionary, select: Callable, group := false, type_id := "", instance_id := "") -> void:
	var button := Button.new()
	button.set_meta("placement_type",type_id)
	button.set_meta("placement_instance",instance_id)
	button.set_meta("placement_group",title if group else "")
	_style_placement(button)
	button.accessibility_name=title+" "+detail
	button.tooltip_text=button.accessibility_name
	rows.add_child(button)
	button.pressed.connect(select)
	var contents := HBoxContainer.new()
	contents.mouse_filter=Control.MOUSE_FILTER_IGNORE
	contents.add_theme_constant_override("separation",5)
	button.add_child(contents)
	contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contents.offset_left=5
	contents.offset_right=-6
	var preview := TextureRect.new()
	preview.custom_minimum_size=Vector2(38,0)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture=Artwork.preview(entry)
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	contents.add_child(preview)
	var name_label := UI.text(title)
	name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size",14)
	contents.add_child(name_label)
	var count := UI.text(detail,"MutedLabel")
	count.size_flags_horizontal=Control.SIZE_SHRINK_END
	count.autowrap_mode=TextServer.AUTOWRAP_OFF
	count.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size",12)
	contents.add_child(count)
	if group:
		var chevron := UI.text("›","MutedLabel")
		chevron.size_flags_horizontal=Control.SIZE_SHRINK_END
		chevron.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		contents.add_child(chevron)

func _category(entry: Dictionary) -> String:
	var category := str(entry.get("category",""))
	if category=="Simulation":return "Simulation"
	if category=="Input":return "Input devices"
	if category=="Output":return "Output devices"
	if category=="PCB":return "PCBs"
	if category=="IC" or str(entry.get("kind","")).begins_with("ic:"):return "ICs"
	return "Basic"

func _icon(entry: Dictionary) -> String:
	match str(entry.get("kind","")):
		"R","resistor":return "resistor"
		"C","capacitor":return "capacitor"
		"L","inductor":return "inductor"
		"D","diode":return "diode"
		"LED":return "led"
		"button","toggle":return "switch"
	if _category(entry)=="ICs" or _category(entry)=="PCBs":return "chip"
	return "component"

func _refresh_filters() -> void:
	if persistent: return
	for child in filters.get_children():filters.remove_child(child);child.queue_free()
	for category in CATEGORIES:
		var button := Button.new()
		button.text = category
		button.toggle_mode = true
		button.button_pressed = family == category
		button.pressed.connect(func():family=category;_refresh_filters();_refresh())
		filters.add_child(button)

func set_lab_leads(leads: Dictionary) -> void:
	lab_leads=leads
	if debug_source:_refresh()

func _refresh() -> void:
	if not is_instance_valid(rows):return
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	if is_instance_valid(back):
		back.visible=family!="All"
		back.text="Components / "+family
	var text := search.text.strip_edges()
	if physical_kit and debug_source:
		for port in lab_leads:
			var lead: Dictionary=lab_leads[port]
			if not text.is_empty() and not str(lead.label).to_lower().contains(text.to_lower()):continue
			var button := UI.action(str(lead.label),"mode_wire",lab_lead_chosen.emit.bind(port))
			_compact_style(button)
			rows.add_child(button)
		feedback.text="Plug a lead into a lab device first." if lab_leads.is_empty() else "Choose a lead and click a breadboard hole."
		return
	var kind_filter: String = {"Resistors":"R","Potentiometers":"pot","Capacitors":"C","Inductors":"L","LEDs":"LED"}.get(family,"")
	var numeric: bool = kind_filter in ["R", "C", "L"] and text != "" and (text[0].is_valid_int() or text[0] in ["-", "+", "."])
	if numeric:
		var search_profile: Dictionary=profile
		if creative:
			var preview_stock := {}
			for type_id in catalog:preview_stock[type_id]=1
			search_profile={"inventory":preview_stock,"component_instances":{}}
		elif physical_kit:
			search_profile=profile.duplicate()
			search_profile.inventory=limits
		var result: Dictionary=Query.search_owned(search_profile,catalog,kind_filter,text,{},{} if creative else limits)
		if str(result.get("error",""))!="":feedback.text=str(result.error);return
		for row in result.rows:
			_add_row(str(row.type),str(row.instance_id),str(row.value_label),int(row.quantity))
		feedback.text=str(result.message) if result.rows.is_empty() else "%d closest owned parts"%result.rows.size()
		return
	var matches := 0
	var listed_groups := {}
	var group_counts := {}
	var group_variants := {}
	var group_families := persistent and family=="All" and text.is_empty() and not debug_source
	if group_families:
		for id in catalog:
			var group := str(VARIABLE_FAMILIES.get(catalog[id].get("kind",""),""))
			var available := _available_count(id)
			if not group.is_empty() and _shows_variant(catalog[id],available):
				group_variants[group]=int(group_variants.get(group,0))+1
				group_counts[group]=int(group_counts.get(group,0))+_remaining(id,available)
	for id in catalog:
		var entry: Dictionary=catalog[id]
		var debug_part: bool=id in [Debug.SOURCE,Debug.METER]
		if debug_part!=debug_source:continue
		var grouped_family := str(VARIABLE_FAMILIES.get(str(entry.get("kind","")),""))
		if family not in ["All","Basic"] and _category(entry)!=family and str(entry.get("kind",""))!=kind_filter and grouped_family!=family:continue
		if family=="Basic" and _category(entry)!="Basic":continue
		var available := _available_count(id)
		if not debug_part and not _shows_variant(entry,available):continue
		var raw_value: Variant=entry.get("value")
		var value_text := Values.format_value(float(raw_value),str(entry.get("unit",""))) if raw_value is float or raw_value is int else ""
		if text!="" and text.to_lower() not in (str(entry.get("name",id))+" "+value_text+" "+str(entry.get("category",""))).to_lower():continue
		if group_families and int(group_variants.get(grouped_family,0))>1:
			if not listed_groups.has(grouped_family):
				listed_groups[grouped_family]=true
				_compact_row(grouped_family,"Unlimited" if creative else "%d remaining" % group_counts[grouped_family],entry,func():
					family=grouped_family
					_refresh(),true)
				matches+=1
			continue
		_add_row(str(id),"",value_text,available)
		matches+=1
	feedback.text="Simulation only · no inventory required" if debug_source and matches>0 else "%d matching parts"%matches

func _add_row(id: String, instance_id: String, value_text: String, available: int) -> void:
	var entry: Dictionary=catalog.get(id,{})
	if persistent:
		var title := str(entry.get("name",id))
		if not value_text.is_empty() and not instance_id.is_empty():title+=" · "+value_text
		var details := "%d remaining" % _remaining(id,available,instance_id) if not creative else "Unlimited"
		if id in [Debug.SOURCE,Debug.METER]:details="Unlimited"
		_compact_row(title,details,entry,func():chosen.emit(id,instance_id),false,id,instance_id)
		return
	var card := UI.card(str(entry.get("name",id)),value_text+" · "+("Available: "+str(available) if not creative else "Design preview"),_icon(entry),str(entry.get("rarity","Common")))
	rows.add_child(card)
	var copy := card.get_node("Content/Copy")
	var place := UI.action("Place", "plus", func():
		chosen.emit(id,instance_id)
		if not persistent: close_picker(),true)
	copy.add_child(place)
