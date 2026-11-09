extends VBoxContainer

const Values = preload("res://scripts/electronics/component_values/values.gd")
const Visual = preload("res://scripts/electronics/component_shop_ui/catalog_presentation.gd")
const Dorm = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Custom = preload("res://scripts/custom_circuit.gd")

signal sale_requested(id: String)
signal take_pcb_requested(id: String)

var profile: RefCounted
var results: GridContainer
var search: LineEdit
var order: OptionButton
var selected_family := "All"
var earnings_suppressed := false

func build(owner_profile: RefCounted) -> void:
	profile = owner_profile
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 9)
	var header := HBoxContainer.new()
	add_child(header)
	search = LineEdit.new()
	search.placeholder_text = "Search owned components or ratings"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = 44
	header.add_child(search)
	order = OptionButton.new()
	order.add_item("Name A–Z")
	order.add_item("Most owned")
	order.add_item("Least owned")
	header.add_child(order)
	var categories := HFlowContainer.new()
	var group := ButtonGroup.new()
	add_child(categories)
	for label in ["All","Resistors","Potentiometers","Capacitors","Inductors","Semiconductors","Inputs","Outputs","Power","Chips & boards","Custom ICs","Custom PCBs"]:
		var button := Button.new()
		button.text=label
		button.toggle_mode=true
		button.button_group=group
		button.button_pressed=label==selected_family
		button.pressed.connect(func():
			selected_family=label
			refresh())
		categories.add_child(button)
	var help := Label.new()
	help.text = "Loose components available to use, sell or pack into a kit"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	results = preload("res://scripts/ui/design_system/responsive_grid.gd").new()
	results.set("minimum_card_width",340.0)
	results.add_theme_constant_override("h_separation",10)
	results.add_theme_constant_override("v_separation",10)
	results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(results)
	search.text_changed.connect(func(_value): refresh())
	order.item_selected.connect(func(_index): refresh())
	refresh()

func refresh() -> void:
	for child in results.get_children():
		results.remove_child(child)
		child.queue_free()
	var rows: Array[Dictionary] = []
	var catalog: Dictionary = profile.catalog()
	var data: Dictionary = profile.data
	var stock := Dorm.loose_stock(data)
	var definitions: Dictionary = data.get("blueprints", {})
	var query := search.text.strip_edges().to_lower()
	for id in stock:
		var entry: Dictionary = catalog.get(id,{})
		var count := int(stock[id])
		if entry.is_empty() or count <= 0: continue
		var item_family := "Custom PCBs" if Custom.is_pcb(str(id),definitions) else "Custom ICs" if definitions.has(id) else "Potentiometers" if str(entry.get("kind","")) in ["pot","potentiometer"] else Visual.family(entry)
		if selected_family != "All" and selected_family != item_family: continue
		var rating := Values.format_value(float(entry.value),str(entry.get("unit",""))) if entry.has("value") else ""
		var name := str(entry.get("name",id))
		if not query.is_empty() and not (name + " " + rating).to_lower().contains(query): continue
		rows.append({"id":id,"name":name,"entry":entry,"count":count})
	rows.sort_custom(func(a, b):
		if order.selected == 1 and a.count != b.count: return a.count > b.count
		if order.selected == 2 and a.count != b.count: return a.count < b.count
		return a.name.naturalnocasecmp_to(b.name) < 0
	)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No owned components match."
		results.add_child(empty)
	for item in rows:
		var card := preload("res://scripts/ui/design_system/widgets.gd").card(item.name,
			"%d available" % item.count,
			"component",str(item.entry.get("rarity","Common")))
		var picture: TextureRect = card.get_node("Content/Icon").get_child(0)
		picture.texture = Visual.preview(item.entry)
		var actions := VBoxContainer.new()
		actions.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		card.get_node("Content").add_child(actions)
		if Custom.is_pcb(str(item.id),definitions) and int(item.count)>0:
			var take := Button.new()
			take.text="Take"
			take.tooltip_text="Transfer to hotbar"
			take.accessibility_name="Take "+item.name+" into your hotbar"
			take.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			take.pressed.connect(func():take_pcb_requested.emit(item.id))
			actions.add_child(take)
		var price: int = profile.resale_price(item.id)
		if price > 0:
			var sell := Button.new()
			sell.text = "Sell 1 · $%d" % (0 if earnings_suppressed else price)
			if earnings_suppressed:sell.tooltip_text="Playtest earnings are disabled."
			sell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sell.pressed.connect(func():
				sell.disabled = true
				sale_requested.emit(item.id))
			actions.add_child(sell)
		results.add_child(card)

