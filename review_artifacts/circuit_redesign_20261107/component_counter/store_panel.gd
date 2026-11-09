extends VBoxContainer
## Additive shop controller. The host/rating adapters are supplied by the owning
## electronics UI; this file never writes profiles, inventory, prices or saves.
signal search_changed(value: String)
signal purchase_requested(request_id: String, intent: Dictionary)
const State = preload("res://scripts/electronics/component_shop_ui/shop_state.gd")
const Visual = preload("res://scripts/electronics/component_shop_ui/catalog_presentation.gd")
var state = State.new()
var catalog := {}
var describe := Callable()
var quote := Callable()
var snapshot := Callable()
var close_action := Callable()
var products: GridContainer
var details: VBoxContainer
var layout: BoxContainer
var balance: Label
var feedback: Label
var total: Label
var buy: Button
var quantity: LineEdit
var rating_fields: Array[LineEdit] = []
var last_quote := {}
var categories: OptionButton
var card_counts := {}
var card_index := {}
var thumbnail_cache := {}
var product_buttons := {}
var ownership: Label
var empty: Label

func configure(entries: Dictionary, services: Dictionary, initial_search := "") -> void:
	catalog=entries.duplicate(true)
	describe=services.get("describe",Callable())
	quote=services.get("quote",Callable())
	snapshot=services.get("snapshot",Callable())
	close_action=services.get("close",Callable())
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
	var heading := HBoxContainer.new();add_child(heading)
	_label(heading,"Component Store",21)
	balance=_label(heading,"Checking funds…",18);balance.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	if close_action.is_valid():_button(heading,"Close",close_action)
	var search := LineEdit.new();search.name="ComponentSearch";search.placeholder_text="Search name, family, rating or rarity";search.text=state.search;search.max_length=100
	search.custom_minimum_size.y=44;search.accessibility_name="Search components";add_child(search)
	search.text_changed.connect(func(value: String):state.search=value;_filter();search_changed.emit(value))
	var controls := HBoxContainer.new();add_child(controls)
	categories=OptionButton.new();categories.custom_minimum_size=Vector2(185,38);categories.accessibility_name="Component category";controls.add_child(categories)
	var names: Array[String]=["All"]
	for entry in catalog.values():
		var family: String=Visual.family(entry)
		if not family in names:names.append(family)
	for family in names:categories.add_item(family)
	categories.item_selected.connect(func(index: int):state.family=categories.get_item_text(index);_filter())
	layout=BoxContainer.new();layout.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_theme_constant_override("separation",20);add_child(layout)
	var list_panel := PanelContainer.new();list_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(list_panel)
	var list_column := VBoxContainer.new();list_column.size_flags_vertical=Control.SIZE_EXPAND_FILL;list_panel.add_child(list_column)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size=Vector2(0,440);scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=true;list_column.add_child(scroll)
	products=GridContainer.new();products.columns=3;products.size_flags_horizontal=Control.SIZE_EXPAND_FILL;products.add_theme_constant_override("h_separation",10);products.add_theme_constant_override("v_separation",10);scroll.add_child(products)
	for id in catalog:
		var entry: Dictionary=catalog[id]
		var item := _button(products,"",func():_select(str(id)))
		item.toggle_mode=true
		item.custom_minimum_size=Vector2(180,116);item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;item.alignment=HORIZONTAL_ALIGNMENT_LEFT
		item.tooltip_text="%s · %s\n%s"%[entry.get("name",id),entry.get("rarity","Common"),entry.get("rating","")]
		item.accessibility_name=item.tooltip_text;product_buttons[id]=item
		var row := HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE;item.add_child(row);row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);row.offset_left=12;row.offset_right=-12;row.offset_top=10;row.offset_bottom=-10;row.add_theme_constant_override("separation",12)
		_icon(row,entry,64)
		var text := VBoxContainer.new();text.mouse_filter=Control.MOUSE_FILTER_IGNORE;text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
		_label(text,str(entry.get("name",id)),17).mouse_filter=Control.MOUSE_FILTER_IGNORE
		var amount := _label(text,"",14);amount.mouse_filter=Control.MOUSE_FILTER_IGNORE;card_counts[id]=amount
		card_index[id]=str(entry.get("name",id))+" "+str(entry.get("rating",""))+" "+Visual.family(entry)+" "+str(entry.get("rarity",""))+" "+str(entry.get("kind",""))
		for child in text.get_children():child.mouse_filter=Control.MOUSE_FILTER_IGNORE
	empty=_label(list_column,"No components match. Try a different search or family.");empty.hide()
	var detail_panel := PanelContainer.new();detail_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;layout.add_child(detail_panel)
	details=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",12);detail_panel.add_child(details)
	feedback=_label(self,"");feedback.name="PurchaseResult";feedback.hide()
	_filter()
	if state.search!="" and _visible_count()==0:
		state.search="";search.text="";_filter();search_changed.emit("")
	if catalog.is_empty():_label(details,"Component catalog unavailable.")
	refresh_snapshot()

func _icon(parent: Node, entry: Dictionary, pixels: int) -> void:
	var tile := PanelContainer.new();tile.custom_minimum_size=Vector2(pixels,pixels);tile.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new();box.bg_color=Visual.rarity_color(str(entry.get("rarity","Common")));box.set_corner_radius_all(10);box.set_content_margin_all(8);tile.add_theme_stylebox_override("panel",box);parent.add_child(tile)
	var picture := TextureRect.new();picture.texture=_thumbnail(Visual.icon(entry));picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;tile.add_child(picture)

func _thumbnail(path: String) -> Texture2D:
	if not thumbnail_cache.has(path):thumbnail_cache[path]=load(path)
	return thumbnail_cache[path]

func _visible_count() -> int:
	var n := 0
	for card in product_buttons.values():
		if card.visible:n+=1
	return n

func _first_visible() -> String:
	for id in product_buttons:
		if product_buttons[id].visible:return str(id)
	return ""

func _filter() -> void:
	if not state.pending_id.is_empty():return
	var needle: String=state.search.strip_edges().to_lower()
	var count := 0
	for id in product_buttons:
		var entry: Dictionary=catalog[id]
		var shown: bool=(state.family=="All" or Visual.family(entry)==state.family) and needle in str(card_index[id]).to_lower()
		product_buttons[id].visible=shown
		if shown:count+=1
	empty.visible=count==0
	if not state.selected_id.is_empty() and (not product_buttons.has(state.selected_id) or not product_buttons[state.selected_id].visible):
		state.selected_id="";state.invalidate_confirmation()
		for child in details.get_children():details.remove_child(child);child.queue_free()
		if count>0:_select(_first_visible())
		else:_label(details,"No matching component selected.",14)
	elif state.selected_id.is_empty() and count>0:_select(_first_visible())

func _select(id: String) -> void:
	if not state.pending_id.is_empty() or not catalog.has(id) or not product_buttons[id].visible:return
	state.selected_id=id;state.fields={};state.invalidate_confirmation();rating_fields.clear()
	for product_id in product_buttons:product_buttons[product_id].set_pressed_no_signal(product_id==id)
	for child in details.get_children():details.remove_child(child);child.queue_free()
	var entry: Dictionary=catalog[id]
	var head := HBoxContainer.new();head.add_theme_constant_override("separation",12);details.add_child(head);_icon(head,entry,72)
	var text := VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(text)
	_label(text,str(entry.get("name",id)),22)
	_label(text,"%s · %s"%[entry.get("rarity","Common"),Visual.family(entry)],14)
	_label(details,str(entry.get("rating","")))
	ownership=_label(details,"")
	var description: Dictionary=describe.call(id) if describe.is_valid() else {}
	var specs: Array=description.get("fields",[])
	if specs.is_empty():_label(details,"Fixed specification · sold as listed",14)
	for spec in specs:
		var key := str(spec.get("key",""))
		if key.is_empty():continue
		_label(details,str(spec.get("label",key))+(" ("+str(spec.unit)+")" if not str(spec.get("unit","")).is_empty() else ""),14)
		var input := LineEdit.new();input.custom_minimum_size.y=44;input.max_length=80;input.text=str(spec.get("default",""));input.placeholder_text=str(spec.get("placeholder",""));input.tooltip_text=str(spec.get("help",""));input.accessibility_name=str(spec.get("label",key));details.add_child(input)
		state.fields[key]=input.text;rating_fields.append(input)
		input.text_changed.connect(func(value: String):state.fields[key]=value;_requote())
	_label(details,"Quantity · whole units",14)
	quantity=LineEdit.new();quantity.name="PurchaseQuantity";quantity.accessibility_name="Purchase quantity in whole units";quantity.custom_minimum_size.y=44;quantity.max_length=6;quantity.text=state.quantity_text;quantity.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER;details.add_child(quantity)
	quantity.text_changed.connect(func(value: String):state.quantity_text=value;_requote())
	total=_label(details,"",20)
	buy=_button(details,"Review purchase",_review_or_purchase);buy.name="ConfirmPurchase"
	quantity.text_submitted.connect(func(_text: String):if not buy.disabled:_review_or_purchase())
	refresh_snapshot();_requote()

func _requote() -> void:
	state.invalidate_confirmation();last_quote={}
	if not is_instance_valid(buy):return
	buy.text="Review purchase";buy.disabled=true
	var error := State.quantity_error(state.quantity_text)
	if not error.is_empty():total.text=error;return
	if not quote.is_valid():total.text="Pricing unavailable. Reopen when the host is ready.";return
	# Raw field strings go to the canonical service. No electrical unit parser here.
	last_quote=quote.call(state.selected_id,state.fields.duplicate(true),int(state.quantity_text))
	if not last_quote.get("ok",false):total.text=str(last_quote.get("error","This specification is unavailable."));return
	_refresh_ownership(str(last_quote.get("id",state.selected_id)))
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
	quantity.editable=not value
	for field in rating_fields:field.editable=not value
	for item in product_buttons.values():item.disabled=value
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
		card_counts[id].text="$%d · Owned %d · %s"%[int(catalog[id].get("price",0)),int(view.get("inventory",{}).get(id,0)),catalog[id].get("rarity","Common")]

func _refresh_ownership(component_id: String) -> void:
	if not is_instance_valid(ownership):return
	var view: Dictionary=snapshot.call() if snapshot.is_valid() else {}
	ownership.text="Owned at this specification: %d · kit space: %d each"%[int(view.get("inventory",{}).get(component_id,0)),int(catalog.get(state.selected_id,{}).get("space",0))]

func _resize_layout() -> void:
	if is_instance_valid(layout):
		layout.vertical=size.x<850
		products.columns=2 if size.x<850 else (3 if size.x<1400 else 4)

func _commas(amount: int) -> String:
	var digits := str(amount);var result := ""
	while digits.length()>3:
		result=","+digits.right(3)+result;digits=digits.left(-3)
	return digits+result
