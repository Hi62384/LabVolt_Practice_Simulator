extends VBoxContainer

signal design_changed(slots: Array, hardware: Dictionary, colors: Dictionary)

const Catalog=preload("res://scripts/campus/items/calculator_layout.gd")
const KeyGrid=preload("res://scripts/campus/items/calculator_key_grid.gd")
const Tokens=preload("res://scripts/ui/design_system/tokens.gd")
const Widgets=preload("res://scripts/ui/design_system/widgets.gd")
const TINTS := ["39596c","1a6472","79434e","515278","254b65","254b65","254b65","335b59","315568","55466c","61564b","3c5362"]
const SWATCHES := {"Ivory":"eae3ce","Coral":"ed827a","Amber":"f4ba64","Mint":"64d6ad","Sky":"75bff5","Lilac":"b699f1"}

var slots: Array=[]
var hardware: Dictionary={}
var key_colors: Dictionary={}
var color_selection: Dictionary={}
var color_tools: PanelContainer
var color_count: Label
var color_picker: ColorPickerButton
var apply_color: Button
var reset_color: Button
var undo_steps: Array[Dictionary]=[]
var redo_steps: Array[Dictionary]=[]
var selected_slot := -1
var dragged_slot := -1
var grid: Container
var palette: VBoxContainer
var search: LineEdit
var hide_installed: CheckButton
var counter: Label
var feedback: Label
var remove_button: Button
var undo_button: Button
var redo_button: Button
var details_title: Label
var details_text: Label
var open_sections: Dictionary={}

func build(layout: Array, features: Dictionary, colors := {}) -> void:
	slots=Catalog.designer_slots(layout)
	hardware=features.duplicate()
	key_colors=colors.duplicate()
	add_theme_constant_override("separation",12)
	var columns:=HBoxContainer.new()
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",9)
	add_child(columns)
	var installed_column:=VBoxContainer.new()
	installed_column.custom_minimum_size.x=246
	installed_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	columns.add_child(installed_column)
	var installed:=_card(installed_column,Color("102b3b"))
	var header:=HBoxContainer.new()
	installed.add_child(header)
	var title:=Widgets.text("Installed keypad","SubtitleLabel")
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	counter=Widgets.text("","MutedLabel")
	header.add_child(counter)
	var presets:=OptionButton.new()
	_compact(presets)
	installed.add_child(presets)
	var tools:=HFlowContainer.new()
	tools.add_theme_constant_override("h_separation",4)
	tools.add_theme_constant_override("v_separation",4)
	installed.add_child(tools)
	presets.add_item("Load a preset")
	for name in ["Basic","Scientific","Financial","Algebra","Graphing"]:presets.add_item(name)
	presets.item_selected.connect(func(index: int):
		if index>0:apply_preset(presets.get_item_text(index));presets.select(0))
	undo_button=_button("Undo",undo)
	redo_button=_button("Redo",redo)
	remove_button=_button("Remove",func():remove_key(selected_slot))
	for button in [undo_button,redo_button,remove_button,_button("Clear",clear_keypad),_button("Defaults",restore_default)]:
		_compact(button)
		tools.add_child(button)
	var color_mode:=_button("Key colors",func():
		color_tools.visible=not color_tools.visible
		color_selection.clear()
		if color_tools.visible and selected_slot>=0 and not slots[selected_slot].is_empty():
			color_selection[slots[selected_slot]]=true
		_render_keys())
	color_mode.toggle_mode=true
	_compact(color_mode)
	tools.add_child(color_mode)
	_build_color_tools(installed)
	grid=KeyGrid.new()
	installed.add_child(grid)
	feedback=Widgets.text("Drag keys to rearrange or remove them.","MutedLabel")
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	installed.add_child(feedback)


	var library:=_card(columns,Color("102b3b"))
	var library_frame: Control=library.get_parent()
	library_frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	library_frame.custom_minimum_size.x=232
	library.add_child(Widgets.text("Available buttons","SubtitleLabel"))
	search=LineEdit.new()
	search.placeholder_text="Search keys"
	search.tooltip_text="Search button symbols or full function names"
	library.add_child(search)
	search.text_changed.connect(func(_text):_render_palette())
	hide_installed=CheckButton.new()
	hide_installed.text="Hide installed buttons"
	library.add_child(hide_installed)
	hide_installed.toggled.connect(func(_enabled):_render_palette())
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y=96
	library.add_child(scroll)
	palette=VBoxContainer.new()
	palette.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(palette)
	details_title=Widgets.text("Key details","SubtitleLabel")
	details_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	library.add_child(details_title)
	details_text=Widgets.text("Hover over a key for details.","MutedLabel")
	details_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	details_text.custom_minimum_size.y=48.0
	library.add_child(details_text)
	open_sections[0]=true
	open_sections[1]=true
	_render()

func _card(parent: Control, color: Color) -> VBoxContainer:
	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",Tokens.surface(color,Color("305569"),10))
	parent.add_child(card)
	var stack:=VBoxContainer.new()
	stack.add_theme_constant_override("separation",7)
	card.add_child(stack)
	return stack

func _button(caption: String, action: Callable) -> Button:
	var button:=Button.new()
	button.text=caption
	button.pressed.connect(action)
	return button

func _compact(button: Button) -> void:
	button.add_theme_font_size_override("font_size",13)
	for state in ["normal","hover","pressed","disabled"]:
		var base := button.get_theme_stylebox(state)
		var style: StyleBox=base.duplicate()
		style.content_margin_top=3.0
		style.content_margin_bottom=3.0
		style.content_margin_left=6.0
		style.content_margin_right=6.0
		button.add_theme_stylebox_override(state,style)
	button.custom_minimum_size.y=25

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _render() -> void:
	_render_keys()
	_render_palette()

func _build_color_tools(parent: Control) -> void:
	color_tools=PanelContainer.new()
	color_tools.add_theme_stylebox_override("panel",Tokens.surface(Color("163849"),Color("396577"),6))
	parent.add_child(color_tools)
	color_tools.hide()
	var rows:=VBoxContainer.new()
	rows.add_theme_constant_override("separation",3)
	color_tools.add_child(rows)
	var selection_tools:=HFlowContainer.new()
	rows.add_child(selection_tools)
	color_count=Widgets.text("Select keys to color","MutedLabel")
	selection_tools.add_child(color_count)
	for option in ["All keys","Clear selection"]:
		var action:=_button(option,func():
			color_selection.clear()
			if option=="All keys":
				for key in slots:
					if not key.is_empty():color_selection[key]=true
			_render_keys())
		_compact(action)
		selection_tools.add_child(action)
	var swatches:=HFlowContainer.new()
	rows.add_child(swatches)
	for name in SWATCHES:
		var swatch:=_button(" ",func():color_picker.color=Color(SWATCHES[name]))
		swatch.accessibility_name=name
		swatch.tooltip_text=name
		swatch.custom_minimum_size=Vector2(23,23)
		for state in ["normal","hover","pressed"]:
			var tint:=Color(SWATCHES[name])
			var style:=Tokens.surface(tint if state=="normal" else tint.lightened(.2),Color("b7d1df"),0)
			style.set_corner_radius_all(5)
			swatch.add_theme_stylebox_override(state,style)
		swatches.add_child(swatch)
	color_picker=ColorPickerButton.new()
	color_picker.color=Color("64d6ad")
	color_picker.edit_alpha=false
	color_picker.custom_minimum_size=Vector2(30,23)
	color_picker.tooltip_text="Choose a custom color"
	color_picker.accessibility_name=color_picker.tooltip_text
	swatches.add_child(color_picker)
	apply_color=_button("Apply color",func():_color_keys(color_picker.color.to_html(false)))
	reset_color=_button("Restore default colors",func():_color_keys(""))
	for action in [apply_color,reset_color]:
		_compact(action)
		swatches.add_child(action)

func _color_keys(hex: String) -> void:
	if color_selection.is_empty():return
	_remember()
	for symbol in color_selection:
		if hex.is_empty():key_colors.erase(symbol)
		else:key_colors[symbol]=hex
	_publish("Default colors restored." if hex.is_empty() else "Color applied.")

func _render_keys() -> void:
	_clear_children(grid)
	var used:=0
	for symbol in slots:
		if not symbol.is_empty():used+=Catalog.span(symbol)
	counter.text="%d / %d cells used"%[used,slots.size()]
	undo_button.disabled=undo_steps.is_empty()
	redo_button.disabled=redo_steps.is_empty()
	remove_button.disabled=color_tools.visible or selected_slot<0 or slots[selected_slot].is_empty()
	color_count.text="Select keys to color" if color_selection.is_empty() else "%d selected"%color_selection.size()
	apply_color.disabled=color_selection.is_empty()
	reset_color.disabled=color_selection.is_empty()
	for index in slots.size():
		if Catalog.continuation(slots,index,Catalog.COLUMNS):
			var covered:=Control.new()
			covered.hide()
			grid.add_child(covered)
			continue
		var symbol: String=slots[index]
		var painting:=color_tools.visible
		var selected:=color_selection.has(symbol) if painting else index==selected_slot
		var key:=_tile(symbol,"",selected,false,key_colors.get(symbol,""))
		key.custom_minimum_size=Vector2.ZERO
		key.set_meta("keypad_span",Catalog.span(symbol))
		key.add_theme_font_size_override("font_size",14)
		key.accessibility_name="Empty position %d"%(index+1) if symbol.is_empty() else "%s, position %d"%[Catalog.catalog(symbol).name,index+1]
		key.pressed.connect(_select_slot.bind(index))
		if painting:
			key.toggle_mode=true
			key.set_pressed_no_signal(selected)
			key.disabled=symbol.is_empty()
		else:
			key.set_drag_forwarding(_source.bind(key,symbol,index),_allow_drop.bind(index),_drop.bind(index))
		if not symbol.is_empty():_wire_details(key,symbol)
		grid.add_child(key)

func _tile(symbol: String, foot: String, selected := false, locked := false, custom_hex := "") -> Button:
	var tile:=Button.new()
	tile.text=Catalog.caption(symbol)
	tile.clip_text=true
	tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size=Vector2(82 if Catalog.span(symbol)==2 else 46,32)
	tile.add_theme_font_size_override("font_size",16)
	var data:=Catalog.catalog(symbol)
	var tint:=Color("1b3848") if symbol.is_empty() else Color(TINTS[data.category])
	if symbol=="RUN":tint=Color("16665e")
	if not custom_hex.is_empty():tint=Color(custom_hex)
	if locked:tint=tint.darkened(.58)
	var skin:=Tokens.surface(tint,Color("8ee5d3") if selected else tint.lightened(.17),0)
	skin.set_corner_radius_all(5)
	if not symbol.is_empty():
		skin.shadow_color=Color("071822")
		skin.shadow_size=2
		skin.shadow_offset=Vector2(0,2)
	var hover: StyleBoxFlat=skin.duplicate()
	hover.bg_color=tint.lightened(.14)
	tile.add_theme_stylebox_override("normal",skin)
	tile.add_theme_stylebox_override("hover",hover)
	tile.add_theme_stylebox_override("pressed",hover)
	tile.add_theme_stylebox_override("hover_pressed",hover)
	if not custom_hex.is_empty():
		var ink:=Color("12252f") if tint.get_luminance()>.38 else Color("ffffff")
		for state in ["font_color","font_hover_color","font_focus_color","font_pressed_color"]:
			tile.add_theme_color_override(state,ink)
	if not foot.is_empty():tile.custom_minimum_size.y=29
	return tile

func _render_palette() -> void:
	_clear_children(palette)
	var query:=search.text.strip_edges().to_lower()
	var matches:=0
	var catalog_symbols:=Catalog.available()
	for category in Catalog.CATEGORIES.size():
		var symbols:=PackedStringArray()
		for symbol in Catalog.NUMERIC_PAD if category==0 else catalog_symbols:
			var data:=Catalog.catalog(symbol)
			if int(data.category)!=category or (hide_installed.button_pressed and symbol in slots):continue
			if query.is_empty() or query in symbol.to_lower() or query in str(data.name).to_lower():symbols.append(symbol)
		if symbols.is_empty():continue
		matches+=symbols.size()
		var group:=VBoxContainer.new()
		palette.add_child(group)
		var heading:=Button.new()
		heading.toggle_mode=true
		heading.set_pressed_no_signal(not query.is_empty() or bool(open_sections.get(category,false)))
		heading.text="%s  %s"%["▾" if heading.button_pressed else "›",Catalog.CATEGORIES[category]]
		heading.alignment=HORIZONTAL_ALIGNMENT_LEFT
		group.add_child(heading)
		var buttons: Container=GridContainer.new() if category==0 else HFlowContainer.new()
		if buttons is GridContainer:buttons.columns=3
		buttons.add_theme_constant_override("h_separation",8)
		buttons.add_theme_constant_override("v_separation",8)
		buttons.visible=heading.button_pressed
		group.add_child(buttons)
		heading.toggled.connect(func(value: bool):
			open_sections[category]=value
			buttons.visible=value
			heading.text="%s  %s"%["▾" if value else "›",Catalog.CATEGORIES[category]])
		for symbol in symbols:
			var data:=Catalog.catalog(symbol)
			var index:=slots.find(symbol)
			var locked:=not Catalog.unlocked(symbol,hardware)
			var foot: String="✓ Installed" if index>=0 else "Locked" if locked else "$%d"%data.price
			var tile_stack:=VBoxContainer.new()
			tile_stack.add_theme_constant_override("separation",3)
			buttons.add_child(tile_stack)
			var tile:=_tile(symbol,foot,index>=0,locked)
			tile.accessibility_name="%s, %s"%[data.name,foot]
			tile.pressed.connect(_choose_library.bind(symbol))
			tile.set_drag_forwarding(_source.bind(tile,symbol,-1),Callable(),Callable())
			_wire_details(tile,symbol)
			tile_stack.add_child(tile)
			var price:=Widgets.text(foot,"MutedLabel")
			price.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			price.add_theme_font_size_override("font_size",11)
			price.mouse_filter=Control.MOUSE_FILTER_IGNORE
			tile_stack.add_child(price)
	if matches==0:palette.add_child(Widgets.text("No buttons match your search.","MutedLabel"))

func _wire_details(button: Button,symbol: String) -> void:
	var data:=Catalog.catalog(symbol)
	var footprint:=" · 2 cells" if Catalog.span(symbol)==2 else ""
	button.tooltip_text="%s%s\n%s\nExample: %s%s"%[data.name,footprint,data.description,data.example,_requirement(symbol)]
	button.mouse_entered.connect(_inspect.bind(symbol))
	button.focus_entered.connect(_inspect.bind(symbol))

func _requirement(symbol: String) -> String:
	var requirement: String=Catalog.catalog(symbol).requires
	if requirement.is_empty():return ""
	return "\nRequires "+Catalog.CAPABILITIES[requirement]+"."

func _inspect(symbol: String) -> void:
	var data:=Catalog.catalog(symbol)
	if data.is_empty():return
	details_title.text="%s  ·  %s  ·  $%d"%[Catalog.caption(symbol),data.name,data.price]
	details_text.text="%s\nExample: %s%s"%[data.description,data.example,_requirement(symbol)]

func _select_slot(index: int) -> void:
	if color_tools.visible:
		var symbol: String=slots[index]
		if symbol.is_empty():return
		if color_selection.has(symbol):color_selection.erase(symbol)
		else:color_selection[symbol]=true
		_render_keys.call_deferred()
		return
	selected_slot=index
	if not slots[index].is_empty():_inspect(slots[index])
	_render.call_deferred()

func _choose_library(symbol: String) -> void:
	_inspect(symbol)
	var index:=slots.find(symbol)
	if index>=0:_select_slot(index)
	else:add_key(symbol)

func _source(_at: Vector2, source: Control, symbol: String, index: int) -> Variant:
	if symbol.is_empty() or (index<0 and (symbol in slots or not Catalog.unlocked(symbol,hardware))):return null
	dragged_slot=index
	var ghost:=Label.new()
	ghost.text=Catalog.caption(symbol)
	ghost.add_theme_font_size_override("font_size",20)
	source.set_drag_preview(ghost)
	return {"owner":get_instance_id(),"slot":index,"symbol":symbol}

func _allow_drop(at: Vector2, data: Variant, destination: int) -> bool:
	if not data is Dictionary or data.get("owner")!=get_instance_id():return false
	var source:=int(data.slot)
	if source==destination and Catalog.span(slots[source])==2 and at.x>grid.get_child(source).size.x*.5:
		destination+=1
	return _can_move(source,destination) if source>=0 else _can_place(str(data.symbol),destination)

func _drop(at: Vector2, data: Variant, destination: int) -> void:
	if not _allow_drop(at,data,destination):return
	var source:=int(data.slot)
	if source>=0:
		if source==destination:destination+=1
		move_key(source,destination)
	else:add_key(str(data.symbol),destination)

func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END and dragged_slot>=0:
		var source:=dragged_slot
		dragged_slot=-1
		if not is_drag_successful() and not grid.get_global_rect().has_point(get_global_mouse_position()):
			remove_key(source)

func add_key(symbol: String,index := -1) -> bool:
	if symbol in slots or Catalog.catalog(symbol).is_empty():return false
	if not Catalog.unlocked(symbol,hardware):
		feedback.text="Unlock %s in Specifications to add this key."%Catalog.CAPABILITIES[Catalog.catalog(symbol).requires]
		return false
	if index<0:
		for candidate in slots.size():
			if _can_place(symbol,candidate):
				index=candidate
				break
	if not _can_place(symbol,index):
		feedback.text="This key needs two free cells side by side." if Catalog.span(symbol)==2 else "Choose a free cell."
		return false
	_remember()
	slots[index]=symbol
	selected_slot=index
	_publish("%s added."%symbol)
	return true

func _can_place(symbol: String,index: int) -> bool:
	if index not in range(slots.size()) or not slots[index].is_empty() or Catalog.continuation(slots,index,Catalog.COLUMNS):return false
	return Catalog.span(symbol)==1 or (index%Catalog.COLUMNS!=Catalog.COLUMNS-1 and slots[index+1].is_empty())

func _can_move(source: int,destination: int) -> bool:
	if source==destination or source not in range(slots.size()) or destination not in range(slots.size()):return false
	if slots[source].is_empty() or (source!=destination-1 and Catalog.continuation(slots,destination,Catalog.COLUMNS)):return false
	var swapped:=slots.duplicate()
	swapped[source]=slots[destination]
	swapped[destination]=slots[source]
	return Catalog.spans_fit(swapped,Catalog.COLUMNS)

func move_key(source: int,destination: int) -> void:
	if not _can_move(source,destination):return
	_remember()
	var symbol: String=slots[source]
	slots[source]=slots[destination]
	slots[destination]=symbol
	selected_slot=destination
	_publish("%s moved."%symbol)

func remove_key(index: int) -> void:
	if index not in range(slots.size()) or slots[index].is_empty():return
	_remember()
	var symbol: String=slots[index]
	slots[index]=""
	_publish("%s removed."%symbol)

func clear_keypad() -> void:
	_replace(Catalog.new_slots([]),hardware,"Keypad cleared.")

func restore_default() -> void:
	_replace(Catalog.default_slots(),hardware,"Default keypad restored.")

func apply_preset(preset_name: String) -> void:
	var preset:=Catalog.preset(preset_name)
	_replace(preset.keypad,preset.hardware,preset_name+" preset loaded.")

func change_hardware(next: Dictionary) -> void:
	if hardware==next:return
	var layout:=slots.duplicate()
	var removed:=0
	for index in layout.size():
		if not layout[index].is_empty() and not Catalog.unlocked(layout[index],next):
			layout[index]=""
			removed+=1
	_replace(layout,next,"%d incompatible keys removed. Undo to restore them."%removed if removed>0 else "")

func _replace(layout: Array,features: Dictionary,message: String) -> void:
	_remember()
	slots=layout.duplicate()
	hardware=features.duplicate()
	selected_slot=-1
	_publish(message)

func _record() -> Dictionary:
	return {"slots":slots.duplicate(),"hardware":hardware.duplicate(),"colors":key_colors.duplicate()}

func _remember() -> void:
	undo_steps.append(_record())
	if undo_steps.size()>32:undo_steps.pop_front()
	redo_steps.clear()

func undo() -> void:
	if undo_steps.is_empty():return
	redo_steps.append(_record())
	_restore(undo_steps.pop_back(),"Change undone.")

func redo() -> void:
	if redo_steps.is_empty():return
	undo_steps.append(_record())
	_restore(redo_steps.pop_back(),"Change redone.")

func _restore(record: Dictionary,message: String) -> void:
	slots=record.slots
	hardware=record.hardware
	key_colors=record.colors
	selected_slot=-1
	_publish(message)

func _publish(message: String) -> void:
	for symbol in key_colors.keys():
		if symbol not in slots:key_colors.erase(symbol)
	for symbol in color_selection.keys():
		if symbol not in slots:color_selection.erase(symbol)
	var missing:=PackedStringArray()
	for key in Catalog.REQUIRED:
		if key not in slots:missing.append(key)
	feedback.text=message
	if not missing.is_empty():feedback.text+=( " " if not message.is_empty() else "")+"Missing common keys: "+", ".join(missing)+"."
	_render.call_deferred()
	design_changed.emit(slots.duplicate(),hardware.duplicate(),key_colors.duplicate())
