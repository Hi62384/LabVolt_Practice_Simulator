extends VBoxContainer
## Reusable builder control. The host supplies fresh authoritative snapshots and
## performs the existing board save/deploy operation after selection.
signal choice_changed(type_id: String, instance_id: String)
const Query = preload("res://scripts/electronics/inventory_value_search/query.gd")
const Selection = preload("res://scripts/electronics/inventory_value_search/selection.gd")
const Values = preload("res://scripts/electronics/component_values/values.gd")
var selection := Selection.new()
var family_button: OptionButton
var value_input: LineEdit
var item_list: ItemList
var feedback: Label
var profile := {}
var catalog := {}
var reserved := {}
var kit_limits := {}
var family := ""

func _ready() -> void:
	var filters := HBoxContainer.new();add_child(filters)
	family_button = OptionButton.new();family_button.custom_minimum_size.x = 155;filters.add_child(family_button)
	value_input = LineEdit.new();value_input.placeholder_text = "Desired value, e.g. 2.2 kΩ";value_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL;filters.add_child(value_input)
	item_list = ItemList.new();item_list.custom_minimum_size.y = 180;item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL;add_child(item_list)
	feedback = Label.new();add_child(feedback)
	family_button.item_selected.connect(_family_selected)
	value_input.text_changed.connect(func(_value: String):_refresh())
	item_list.item_selected.connect(_row_selected)
	_refresh_families()

func set_inventory(next_profile: Dictionary, next_catalog: Dictionary, next_reserved: Dictionary = {}, next_kit_limits: Dictionary = {}) -> void:
	profile = next_profile.duplicate(true)
	catalog = next_catalog.duplicate(true)
	reserved = next_reserved.duplicate(true)
	kit_limits = next_kit_limits.duplicate(true)
	if is_node_ready():_refresh_families()

func _refresh_families() -> void:
	var families := {}
	for type_id in catalog:
		var entry: Dictionary = catalog[type_id]
		if not Values.fields(entry).has("value"):continue
		families[str(entry.get("kind", ""))] = true
	var names: Array = families.keys();names.sort()
	family_button.clear()
	for kind in names:
		family_button.add_item(_family_name(str(kind)))
		family_button.set_item_metadata(family_button.item_count - 1, kind)
	var index := names.find(family)
	if index < 0:
		family = str(names[0]) if not names.is_empty() else ""
		index = names.find(family)
	if index >= 0:family_button.select(index)
	_refresh()

func _family_name(kind: String) -> String:
	match kind:
		"R":return "Resistor"
		"C":return "Capacitor"
		"L":return "Inductor"
		"V":return "Voltage source"
		"pot":return "Potentiometer"
		_:return kind

func _family_selected(index: int) -> void:
	family = str(family_button.get_item_metadata(index))
	value_input.clear()
	selection.selected_type = "";selection.selected_instance = ""
	choice_changed.emit("", "")
	_refresh()

func _refresh() -> void:
	if item_list == null:return
	var before_type := selection.selected_type
	var before_instance := selection.selected_instance
	var outcome: Dictionary = Query.search_owned(profile,catalog,family,value_input.text,reserved,kit_limits)
	selection.refresh(outcome.rows)
	item_list.clear()
	for row in selection.rows:
		var caption := "%s  ·  %s  ·  %s  ×%d" % [row.name,row.value_label,row.rating,int(row.quantity)]
		item_list.add_item(caption)
		var index := item_list.item_count - 1
		item_list.set_item_metadata(index,{"type":row.type,"instance_id":row.instance_id})
		item_list.set_item_tooltip(index,"%s · %s · %s" % [row.rarity,row.value_label,"Owned unit" if str(row.instance_id)!="" else "Available stock"])
		if row.type == selection.selected_type and row.instance_id == selection.selected_instance:item_list.select(index)
	feedback.text = str(outcome.error) if str(outcome.error)!="" else str(outcome.message)
	if before_type!="" and selection.selected_type=="":choice_changed.emit("", "")
	if before_type!=selection.selected_type or before_instance!=selection.selected_instance:queue_redraw()

func _row_selected(index: int) -> void:
	var item: Dictionary = item_list.get_item_metadata(index)
	if selection.choose(str(item.type),str(item.instance_id)):
		choice_changed.emit(selection.selected_type,selection.selected_instance)
