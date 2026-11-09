extends VBoxContainer
## Additive shop controller. The host/rating adapters are supplied by the owning
## electronics UI; this file never writes profiles, inventory, prices or saves.
signal search_changed(value: String)
signal purchase_requested(request_id: String, intent: Dictionary)
const Values = preload("res://scripts/electronics/component_values/values.gd")
const Bands = preload("res://scripts/electronics/component_shop_ui/resistor_bands.gd")
const State = preload("res://scripts/electronics/component_shop_ui/shop_state.gd")
const Visual = preload("res://scripts/electronics/component_shop_ui/catalog_presentation.gd")
const GuideContent = preload("res://scripts/electronics/component_shop_ui/guide_content.gd")
const GuidePreview = preload("res://scripts/electronics/component_shop_ui/guide_preview.gd")
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const CUSTOM_FAMILY := "Custom ICs & PCBs"
var state = State.new()
var catalog := {}
var describe := Callable()
var quote := Callable()
var snapshot := Callable()
var close_action := Callable()
var restock_quote := Callable()
var restock_id := ""
var products: GridContainer
var catalog_scroll: ScrollContainer
var details: VBoxContainer
var inspector: PanelContainer
var layout: BoxContainer
var balance: Label
var feedback: Label
var total: Label
var buy: Button
var quantity: HSlider
var rating_fields: Array[Control] = []
var grouped := {}
var rating_picture: TextureRect
var band_legend: Label
var last_quote := {}
var categories: OptionButton
var card_counts := {}
var card_index := {}
var thumbnail_cache := {}
var product_buttons := {}
var ownership: Label
var empty: Label
var modal_host: Control
var guide_overlay: ColorRect
var guide_focus: Control
var guide_definitions := {}

func configure(entries: Dictionary, services: Dictionary, initial_search := "") -> void:
	catalog=entries.duplicate(true)
	guide_definitions=services.get("blueprints",{})
	describe=services.get("describe",Callable())
	quote=services.get("quote",Callable())
	restock_quote=services.get("restock_quote",Callable())
	snapshot=services.get("snapshot",Callable())
	close_action=services.get("close",Callable())
	balance=services.get("balance") as Label
	modal_host=services.get("modal_host",self) as Control
	state.search=initial_search.left(100)
	_build()
	resized.connect(_resize_layout)
	_resize_layout()

func _label(parent: Node, text: String, size := 16) -> Label:
	var node := Label.new();node.text=text;node.add_theme_font_size_override("font_size",size)
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(node);return node

func _button(parent: Node, text: String, action: Callable) -> Button:
	var node := Button.new();node.text=text;node.custom_minimum_size.y=44
	node.focus_mode=Control.FOCUS_ALL;parent.add_child(node);node.pressed.connect(action)
	return node

func _build() -> void:
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",16)
	if not is_instance_valid(balance):
		var heading := HBoxContainer.new();add_child(heading)
		_label(heading,"Component Store",21)
		balance=_label(heading,"Checking funds…",18);balance.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		if close_action.is_valid():_button(heading,"Close",close_action)
	var controls := HBoxContainer.new();add_child(controls)
	var search := LineEdit.new();search.name="ComponentSearch";search.placeholder_text="Search components or ratings";search.text=state.search;search.max_length=100
	search.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y=44;search.accessibility_name="Search components";controls.add_child(search)
	search.text_changed.connect(func(value: String):state.search=value;_filter();search_changed.emit(value))
	categories=OptionButton.new();categories.custom_minimum_size=Vector2(185,38);categories.accessibility_name="Component category";controls.add_child(categories)
	var names: Array[String]=["All"]
	for entry in catalog.values():
		var family: String=_family(entry)
		if not family in names:names.append(family)
	if not CUSTOM_FAMILY in names:names.append(CUSTOM_FAMILY)
	for family in names:categories.add_item(family)
	categories.item_selected.connect(func(index: int):state.family=categories.get_item_text(index);_filter())
	layout=BoxContainer.new();layout.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_theme_constant_override("separation",20);add_child(layout)
	var list_panel := PanelContainer.new();list_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(list_panel)
	var list_column := VBoxContainer.new();list_column.size_flags_vertical=Control.SIZE_EXPAND_FILL;list_panel.add_child(list_column)
	catalog_scroll=ScrollContainer.new();catalog_scroll.custom_minimum_size=Vector2(0,164);catalog_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;catalog_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;catalog_scroll.follow_focus=true;list_column.add_child(catalog_scroll)
	products=GridContainer.new();products.columns=1;products.size_flags_horizontal=Control.SIZE_EXPAND_FILL;products.add_theme_constant_override("h_separation",10);products.add_theme_constant_override("v_separation",10);catalog_scroll.add_child(products)
	catalog_scroll.resized.connect(_resize_columns)
	_group_ratings()
	for id in grouped:
		var entry: Dictionary=catalog[id]
		var item := _button(products,"",func():_select(str(id)))
		item.toggle_mode=true
		item.custom_minimum_size=Vector2(218,108);item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;item.alignment=HORIZONTAL_ALIGNMENT_LEFT
		item.tooltip_text="%s · %s"%[entry.get("name",id),entry.get("rarity","Common")]
		item.accessibility_name=item.tooltip_text;product_buttons[id]=item
		var row := HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE;item.add_child(row);row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);row.offset_left=12;row.offset_right=-12;row.offset_top=10;row.offset_bottom=-10;row.add_theme_constant_override("separation",12)
		_icon(row,entry,64)
		var text := VBoxContainer.new();text.mouse_filter=Control.MOUSE_FILTER_IGNORE;text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
		var name_label := _label(text,_product_name(id),16)
		name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_label.custom_minimum_size.y = 24
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var amount := _label(text,"",14);amount.mouse_filter=Control.MOUSE_FILTER_IGNORE;card_counts[id]=amount
		var searchable := PackedStringArray([_product_name(id), _family(entry), str(entry.get("category","")), str(entry.get("rarity",""))])
		for member in grouped[id]:
			searchable.append(str(catalog[member].get("name", member)))
			if catalog[member].has("value"):
				searchable.append(Values.format_value(float(catalog[member].value), str(catalog[member].get("unit",""))))
		card_index[id] = " ".join(searchable)
		for child in text.get_children():child.mouse_filter=Control.MOUSE_FILTER_IGNORE
	empty=_label(list_column,"No components match. Try a different search or family.");empty.hide()
	inspector=PanelContainer.new();inspector.custom_minimum_size=Vector2(320,164);layout.add_child(inspector)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.follow_focus = true
	inspector.add_child(detail_scroll)
	details=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",10);detail_scroll.add_child(details)
	feedback=_label(self,"");feedback.name="PurchaseResult";feedback.hide()
	_filter()
	if catalog.is_empty():empty.text="Component catalog unavailable."
	refresh_snapshot()

func _group_ratings() -> void:
	var groups := {}
	for id in catalog:
		var entry: Dictionary = catalog[id]
		var kind := str(entry.get("kind",""))
		var family := kind if kind in ["R","C","L","V","pot"] else str(id)
		if not groups.has(family): groups[family] = []
		groups[family].append(id)
	for family in groups:
		var ids: Array = groups[family]
		var representative: String = ids[0]
		if family == "R" and "r1000_t5_w25" in ids: representative = "r1000_t5_w25"
		grouped[representative] = ids

func _product_name(id: String) -> String:
	var entry: Dictionary = catalog[id]
	return {"R":"Resistor","C":"Capacitor","L":"Inductor","V":"Battery","pot":"Potentiometer"}.get(entry.get("kind"), str(entry.get("name",id)))

func _family(entry: Dictionary) -> String:
	if entry.get("kind") == "module" and entry.get("category") in ["IC", "PCB"]:
		return CUSTOM_FAMILY
	return Visual.family(entry)

func _icon(parent: Node, entry: Dictionary, pixels: int) -> TextureRect:
	var tile := PanelContainer.new();tile.custom_minimum_size=Vector2(pixels,pixels);tile.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new();box.bg_color=Visual.rarity_color(str(entry.get("rarity","Common")));box.set_corner_radius_all(10);box.set_content_margin_all(5);tile.add_theme_stylebox_override("panel",box);parent.add_child(tile)
	var picture := TextureRect.new();picture.texture=_thumbnail(entry);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;tile.add_child(picture)
	return picture

func _thumbnail(entry: Dictionary) -> Texture2D:
	var key := str(entry.get("kind","")) + str(entry.get("worker_model","")) + str(entry.get("pins",[])) + str(entry.get("color",""))
	var category := str(entry.get("category",""))
	if category in ["IC","PCB"]: key += category + str(entry.get("name",""))
	if entry.get("kind") == "R": key += str(entry.get("value")) + str(entry.get("resistance_tolerance"))
	if not thumbnail_cache.has(key): thumbnail_cache[key] = Visual.preview(entry)
	return thumbnail_cache[key]

func _filter() -> void:
	if not state.pending_id.is_empty():return
	var needle: String=state.search.strip_edges().to_lower()
	var count := 0
	for id in product_buttons:
		var entry: Dictionary=catalog[id]
		var shown: bool=(state.family=="All" or _family(entry)==state.family) and (needle.is_empty() or str(card_index[id]).to_lower().contains(needle))
		product_buttons[id].visible=shown
		if shown:count+=1
	empty.text="No custom ICs or PCBs match. Save a blueprint in either builder to add it here." if state.family==CUSTOM_FAMILY else "No components match. Try a different search or family."
	empty.visible=count==0
	if not state.selected_id.is_empty() and (not product_buttons.has(state.selected_id) or not product_buttons[state.selected_id].visible):
		state.selected_id="";state.invalidate_confirmation()
		for child in details.get_children():details.remove_child(child);child.queue_free()

func restock(id: String) -> void:
	if not state.pending_id.is_empty() or not restock_quote.is_valid(): return
	for representative in grouped:
		if id not in grouped[representative]: continue
		var search := find_child("ComponentSearch", true, false) as LineEdit
		search.text = ""
		search.text_changed.emit("")
		categories.select(0)
		categories.item_selected.emit(0)
		state.quantity_text = "1"
		_select(representative, id)
		quantity.grab_focus()
		return

func _select(id: String, exact_id := "") -> void:
	if not state.pending_id.is_empty() or not catalog.has(id) or not product_buttons[id].visible:return
	inspector.show()
	restock_id = exact_id
	state.selected_id=id;state.fields={};state.invalidate_confirmation();rating_fields.clear()
	for product_id in product_buttons:product_buttons[product_id].set_pressed_no_signal(product_id==id)
	for child in details.get_children():details.remove_child(child);child.queue_free()
	var entry: Dictionary=catalog[id if exact_id.is_empty() else exact_id]
	var head := HBoxContainer.new();head.add_theme_constant_override("separation",12);details.add_child(head);rating_picture=_icon(head,entry,85)
	var text := VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(text)
	_label(text,_product_name(id) if exact_id.is_empty() else str(entry.name),22)
	_label(text,"%s · %s"%[entry.get("rarity","Common"),entry.get("category") if _family(entry)==CUSTOM_FAMILY else _family(entry)],14)
	var kind := str(entry.get("kind",""))
	var guide_button := _button(details,"Guide",func():_show_guide(id if exact_id.is_empty() else exact_id, entry))
	guide_button.accessibility_name="Guide for "+str(entry.name)
	band_legend = null
	if kind == "R" and exact_id.is_empty():
		_label(details, "Color bands", 14)
		band_legend = _label(details, "", 14)
		band_legend.autowrap_mode = TextServer.AUTOWRAP_OFF
		band_legend.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		band_legend.max_lines_visible = 1
	_label(details, "%d pins" % entry.get("pins",[]).size(), 14)
	ownership=_label(details,"")
	var description: Dictionary=describe.call(id) if describe.is_valid() else {}
	var specs: Array=description.get("fields",[]) if exact_id.is_empty() else []
	if specs.is_empty():_label(details,"Fixed specification · sold as listed",14)
	for spec in specs:
		var key := str(spec.get("key",""))
		if key.is_empty():continue
		if kind == "R" and key == "resistance_tolerance":
			_label(details, "Resistance tolerance", 14)
			var tolerance := OptionButton.new()
			tolerance.accessibility_name = "Resistance tolerance"
			tolerance.add_item("1%")
			tolerance.add_item("5%")
			var parsed := Values.parse(spec.default, str(spec.unit))
			tolerance.select(0 if parsed.ok and is_equal_approx(float(parsed.value), .01) else 1)
			state.fields[key] = .01 if tolerance.selected == 0 else .05
			rating_fields.append(tolerance)
			details.add_child(tolerance)
			tolerance.item_selected.connect(func(index: int):
				state.fields["resistance_tolerance"] = .01 if index == 0 else .05
				_requote())
			continue
		_label(details,str(spec.get("label",key))+(" ("+str(spec.unit)+")" if not str(spec.get("unit","")).is_empty() else ""),14)
		var choices: Array = []
		if kind == "R":
			match key:
				"value": choices = Bands.ratings()
				"power_rating_w": choices = preload("res://scripts/physical_resistors.gd").POWER_RATINGS.duplicate()
		if kind == "V" and key == "value": choices = [1.5,3.0,3.7,4.5,5.0,6.0,9.0,12.0,24.0]
		if kind == "C" and key == "value": choices = [1e-9,10e-9,100e-9,1e-6,10e-6,100e-6,470e-6,1000e-6]
		if kind == "L" and key == "value": choices = [.0001,.001,.01,.1,1.0,10.0]
		if kind == "pot" and key == "value": choices = [100.0,1000.0,5000.0,10000.0,50000.0,100000.0,1000000.0]
		if not choices.is_empty():
			choices.sort()
			var slider := HSlider.new()
			slider.custom_minimum_size.y = 36
			slider.accessibility_name = str(spec.get("label",key))
			slider.max_value=choices.size()-1
			slider.step=1
			var default := Values.parse(spec.default, str(spec.unit))
			var selected := 0
			for i in choices.size():
				var value := float(choices[i])
				if default.ok and is_equal_approx(value,float(default.value)): selected = i
			slider.value=selected
			state.fields[key] = choices[selected]
			var format_choice := func(index: int) -> String:
				return Values.format_value(float(choices[index]),str(spec.unit))
			var current := _label(details,format_choice.call(selected),15)
			rating_fields.append(slider)
			details.add_child(slider)
			slider.value_changed.connect(func(index: float):
				state.fields[key]=choices[int(index)]
				current.text=format_choice.call(int(index))
				_requote())
			continue
		var input := LineEdit.new();input.custom_minimum_size.y=44;input.max_length=80;input.text=str(spec.get("default",""));input.placeholder_text=str(spec.get("placeholder",""));input.tooltip_text=str(spec.get("help",""));input.accessibility_name=str(spec.get("label",key));details.add_child(input)
		state.fields[key]=input.text;rating_fields.append(input)
		input.text_changed.connect(func(value: String):state.fields[key]=value;_requote())
	var count_label := _label(details,"Quantity · "+state.quantity_text,14)
	quantity=HSlider.new();quantity.name="PurchaseQuantity";quantity.accessibility_name="Purchase quantity in whole units";quantity.custom_minimum_size.y=36
	quantity.min_value=1;quantity.max_value=20;quantity.step=1;quantity.value=clampi(int(state.quantity_text),1,20);details.add_child(quantity)
	state.quantity_text=str(int(quantity.value))
	count_label.text="Quantity · "+state.quantity_text
	quantity.value_changed.connect(func(value: float):
		state.quantity_text=str(int(value))
		count_label.text="Quantity · "+state.quantity_text
		_requote())
	total=_label(details,"",20)
	buy=_button(details,"Review purchase",_review_or_purchase);buy.name="ConfirmPurchase"
	refresh_snapshot();_requote()

func _show_guide(type_id: String, entry: Dictionary) -> void:
	if is_instance_valid(guide_overlay):return
	guide_focus=get_viewport().gui_get_focus_owner()
	guide_overlay=ColorRect.new()
	guide_overlay.color=Color(0,0,0,.60)
	guide_overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	modal_host.add_child(guide_overlay)
	guide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	guide_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",Tokens.surface(Tokens.SURFACE))
	panel.custom_minimum_size=Vector2(clampf(modal_host.size.x-54,0,740),clampf(modal_host.size.y-54,0,660))
	center.add_child(panel)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation",12)
	panel.add_child(contents)
	var heading := HBoxContainer.new()
	contents.add_child(heading)
	_icon(heading,entry,58)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(labels)
	labels.add_child(UI.text("COMPONENT GUIDE","MutedLabel"))
	labels.add_child(UI.text(str(entry.get("name","Component")),"SubtitleLabel"))
	var close := UI.action("Close","close",close_guide)
	close.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	heading.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.focus_mode=Control.FOCUS_ALL
	contents.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	body.add_child(UI.text("Breadboard preview", "SubtitleLabel"))
	var preview := GuidePreview.new()
	preview.configure(type_id, entry, guide_definitions)
	body.add_child(preview)
	body.add_child(UI.text("Numbered arrows point to the mounted terminals. The terminal names are listed below.", "MutedLabel"))
	var lesson := GuideContent.lesson(entry)
	body.add_child(UI.text("What it does", "SubtitleLabel"))
	body.add_child(UI.text(str(lesson[0])))
	body.add_child(UI.text("How to use it", "SubtitleLabel"))
	body.add_child(UI.text(str(lesson[1])))
	var exercise := GuideContent.exercise(entry)
	if not exercise.is_empty():
		body.add_child(UI.text("Try it in the simulator", "SubtitleLabel"))
		body.add_child(UI.text(exercise))
	var pin_roles := GuideContent.pin_roles(entry)
	if not pin_roles.is_empty():
		body.add_child(UI.text("Pin reference", "SubtitleLabel"))
		for pin in entry.get("pins", []):
			if pin_roles.has(pin):
				body.add_child(UI.text("%s  ·  %s" % [pin, pin_roles[pin]]))
	var rating := str(entry.get("rating", ""))
	if not rating.is_empty():
		body.add_child(UI.text("Model details", "SubtitleLabel"))
		body.add_child(UI.text(rating))
	close.focus_next=close.get_path_to(scroll)
	close.focus_previous=close.focus_next
	scroll.focus_next=scroll.get_path_to(close)
	scroll.focus_previous=scroll.focus_next
	close.grab_focus()

func close_guide() -> bool:
	if not is_instance_valid(guide_overlay):return false
	guide_overlay.hide()
	guide_overlay.queue_free()
	guide_overlay=null
	if is_instance_valid(guide_focus):guide_focus.grab_focus()
	guide_focus=null
	return true

func _requote() -> void:
	state.invalidate_confirmation();last_quote={}
	if not is_instance_valid(buy):return
	buy.text="Review purchase";buy.disabled=true
	var error := State.quantity_error(state.quantity_text)
	if not error.is_empty():total.text=error;return
	if not quote.is_valid():total.text="Pricing unavailable. Reopen when the host is ready.";return
	# Raw field strings go to the canonical service. No electrical unit parser here.
	last_quote=quote.call(state.selected_id,state.fields.duplicate(true),int(state.quantity_text)) if restock_id.is_empty() else restock_quote.call(restock_id,{},int(state.quantity_text))
	if not last_quote.get("ok",false):total.text=str(last_quote.get("error","This specification is unavailable."));return
	_refresh_ownership(str(last_quote.get("id",state.selected_id)))
	if is_instance_valid(band_legend):
		var entry: Dictionary = catalog[state.selected_id].duplicate()
		entry.value = state.fields.get("value", entry.value)
		entry.resistance_tolerance = state.fields.get("resistance_tolerance", .05)
		rating_picture.texture = _thumbnail(entry)
		var names := PackedStringArray()
		for band in Bands.bands(float(entry.value), float(entry.resistance_tolerance)): names.append(band.name.capitalize())
		band_legend.text = " · ".join(names)
		band_legend.tooltip_text = band_legend.text
	total.text="$%d total · %d × $%d"%[int(last_quote.get("total",0)),int(state.quantity_text),int(last_quote.get("unit_price",0))]
	buy.disabled=not state.pending_id.is_empty()

func _review_or_purchase() -> void:
	if not state.pending_id.is_empty() or buy.disabled:return
	if state.confirmation.is_empty():
		# Confirm the exact validated intent. Any edit invalidates this confirmation.
		if not last_quote.get("intent") is Dictionary:return
		state.confirmation=last_quote.duplicate(true)
		buy.text="Confirm · buy %s for $%d"%[state.quantity_text,int(last_quote.get("total",0))]
		return
	var intent: Dictionary=state.confirmation.intent.duplicate(true)
	var request_id: String=state.begin_request()
	if request_id.is_empty():return
	_set_pending(true)
	_message("Sending purchase to the host…",false)
	purchase_requested.emit(request_id,intent)

func complete_purchase(request_id: String, result: Dictionary) -> void:
	# Only the adapter processing the matching authoritative response calls this.
	if not state.finish_request(request_id):return
	_set_pending(false);refresh_snapshot();_requote()
	_message(str(result.get("message", "Purchase saved." if result.get("ok",false) else "Purchase could not be saved.")),not result.get("ok",false))

func _set_pending(value: bool) -> void:
	if is_instance_valid(quantity):quantity.editable=not value
	for field in rating_fields:
		if field is LineEdit or field is Slider: field.editable = not value
		else: field.disabled = value
	for item in product_buttons.values():item.disabled=value
	if is_instance_valid(buy):
		buy.disabled=value
		if value:buy.text="Awaiting host confirmation…"

func _message(text: String, failed: bool) -> void:
	feedback.text=("Purchase failed · " if failed else "")+text;feedback.show()
	feedback.add_theme_color_override("font_color",Color("ffc6be") if failed else Color("b5f1d2"))

func refresh_snapshot() -> void:
	var view: Dictionary=snapshot.call() if snapshot.is_valid() else {}
	# Unlimited status must come from the host policy snapshot, never a UI flag.
	var policy: Dictionary=view.get("economy",{})
	balance.text="$∞" if policy.get("ok",false) and policy.get("unlimited_purchases",false) else "$%s"%_commas(int(view.get("dollars",0)))
	if view.is_empty():balance.text="Funds unavailable"
	_refresh_ownership(str(last_quote.get("id",state.selected_id)))
	for id in card_counts:
		var owned := 0
		for member in grouped[id]: owned += int(view.get("loose_inventory",view.get("inventory",{})).get(member,0))
		card_counts[id].text="$%d · Loose %d\n%s"%[int(catalog[id].get("price",0)),owned,catalog[id].get("rarity","Common")]

func _refresh_ownership(component_id: String) -> void:
	if not is_instance_valid(ownership):return
	var view: Dictionary=snapshot.call() if snapshot.is_valid() else {}
	var total := int(view.get("inventory",{}).get(component_id,0))
	var loose := int(view.get("loose_inventory",view.get("inventory",{})).get(component_id,0))
	ownership.text="Loose: %d · Total owned: %d · Kit space: %d each" % [loose,total,int(catalog.get(state.selected_id,{}).get("space",0))]

func _resize_layout() -> void:
	if is_instance_valid(layout):
		layout.vertical=size.x<640
		inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL if layout.vertical else Control.SIZE_FILL

func _resize_columns() -> void:
	products.columns = clampi(floori((catalog_scroll.size.x - 8) / 228.0), 1, 5)

func _commas(amount: int) -> String:
	var digits := str(amount);var result := ""
	while digits.length()>3:
		result=","+digits.right(3)+result;digits=digits.left(-3)
	return digits+result
