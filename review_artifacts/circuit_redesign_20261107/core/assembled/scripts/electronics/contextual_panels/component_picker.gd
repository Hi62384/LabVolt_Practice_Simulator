extends PanelContainer
signal chosen(type_id: String, instance_id: String)
signal closed
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Query = preload("res://scripts/electronics/inventory_value_search/query.gd")
const Values = preload("res://scripts/electronics/component_values/values.gd")
var profile := {}
var catalog := {}
var limits := {}
var creative := false
var family := "All"
var search: LineEdit
var rows: VBoxContainer
var filters: HFlowContainer
var feedback: Label

func _ready() -> void:
	custom_minimum_size = Vector2(340, 320)
	var root := VBoxContainer.new();add_child(root)
	root.add_child(UI.header("Add component", "Choose an owned part, then choose its mounting holes.", close_picker))
	search = LineEdit.new();search.placeholder_text="Search name or value, e.g. 4.7 kΩ";search.accessibility_name="Search components";root.add_child(search)
	search.text_changed.connect(func(_value):_refresh())
	filters=HFlowContainer.new();root.add_child(filters)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size.y=220;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
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

func _category(entry: Dictionary) -> String:
	var category := str(entry.get("category",""))
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
	for child in filters.get_children():filters.remove_child(child);child.queue_free()
	for category in ["All","Basic","Resistors","Capacitors","Inductors","ICs","PCBs","Input devices","Output devices"]:
		var button := UI.action(category,_icon({"category":"IC"}) if category=="ICs" else "circuit",func():family=category;_refresh())
		button.toggle_mode=true;button.button_pressed=family==category;filters.add_child(button)

func _refresh() -> void:
	if not is_instance_valid(rows):return
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var text := search.text.strip_edges()
	var kind_filter := {"Resistors":"R","Capacitors":"C","Inductors":"L"}.get(family,"")
	var numeric := kind_filter!="" and text!="" and (text[0].is_valid_int() or text[0]=="-")
	if numeric:
		var search_profile: Dictionary=profile
		if creative:
			var preview_stock := {}
			for type_id in catalog:preview_stock[type_id]=1
			search_profile={"inventory":preview_stock,"component_instances":{}}
		var result: Dictionary=Query.search_owned(search_profile,catalog,kind_filter,text,{},{} if creative else limits)
		if str(result.get("error",""))!="":feedback.text=str(result.error);return
		for row in result.rows:
			_add_row(str(row.type),str(row.instance_id),str(row.value_label),int(row.quantity))
		feedback.text=str(result.message) if result.rows.is_empty() else "%d closest owned parts"%result.rows.size()
		return
	var matches := 0
	for id in catalog:
		var entry: Dictionary=catalog[id]
		if family not in ["All","Basic"] and _category(entry)!=family and str(entry.get("kind",""))!=kind_filter:continue
		if family=="Basic" and _category(entry)!="Basic":continue
		var owned := int(profile.get("inventory",{}).get(id,0))
		var available := owned if limits.is_empty() else mini(owned,int(limits.get(id,0)))
		if not creative and available<=0:continue
		var raw_value: Variant=entry.get("value")
		var value_text := Values.format_value(float(raw_value),str(entry.get("unit",""))) if raw_value is float or raw_value is int else str(entry.get("rating",""))
		if text!="" and text.to_lower() not in (str(entry.get("name",id))+" "+value_text+" "+str(entry.get("category",""))).to_lower():continue
		_add_row(str(id),"",value_text,available)
		matches+=1
	feedback.text="%d matching parts"%matches

func _add_row(id: String, instance_id: String, value_text: String, available: int) -> void:
	var entry: Dictionary=catalog.get(id,{})
	var card := UI.card(str(entry.get("name",id)),value_text+" · "+("Available: "+str(available) if not creative else "Design preview"),_icon(entry),str(entry.get("rarity","Common")))
	rows.add_child(card)
	card.get_node("Content/Copy").add_child(UI.action("Place", "plus", func():chosen.emit(id,instance_id);close_picker(),true))
