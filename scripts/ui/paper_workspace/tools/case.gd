extends Control
## Left edge tool case. The workspace owns paper-space objects and persistence.
signal tool_selected(tool: String)
signal properties_changed(properties: Dictionary)
signal text_action(action: String)

const WorkspaceTheme = preload("res://scripts/ui/design_system/theme.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const Body = preload("res://scripts/ui/paper_workspace/tools/body.gd")
const CURSORS := {
	"pencil": preload("res://assets/ui/paper_workspace/tools/pencil_cursor.svg"),
	"eraser": preload("res://assets/ui/paper_workspace/tools/eraser_cursor.svg"),
	"text": preload("res://assets/ui/paper_workspace/tools/text_cursor.svg"),
}
const WIDTH := 292.0
const PEEK := 42.0
const TRAY_SCALE_Y := .83
const TRAY_HEIGHT := 332.0 * TRAY_SCALE_Y
const TOOLS := ["pencil", "eraser", "text"]
var tool := "answer"
var properties := {"color": "263743", "width": 3.0, "hardness": 0.8, "opacity": 1.0, "font": "Sans", "font_size": 24, "angle": 0.0, "equation": false, "bold": false, "italic": false, "align": "left", "box_width": 280.0}
var selection: Dictionary = {}
var revealed := false
var _leave_elapsed := 0.0
var _target_x := 0.0
var _buttons := {}
var _body
var _property_host: VBoxContainer
var _selected_host: VBoxContainer
var _panel: Control
var _property_panel: PanelContainer
var _properties_hidden := false
var supported_text_actions := ["edit", "bake"]

static func cursor_texture(value: String) -> Texture2D:
	return CURSORS.get(value)

func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 560)
	size = custom_minimum_size
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = WorkspaceTheme.create()
	_build()
	_set_revealed(tool != "answer", true)

func configure(initial_tool: String, initial_properties: Dictionary) -> void:
	for key in properties.keys():
		if initial_properties.has(key): properties[key] = initial_properties[key]
	tool = initial_tool if initial_tool in TOOLS else "answer"
	if is_node_ready():
		_refresh()
		_set_revealed(tool != "answer", true)

func set_tool(value: String) -> void:
	var next := value if value in TOOLS else "answer"
	if next == tool: return
	tool = next
	_properties_hidden=false
	if is_node_ready():
		_refresh()
		_set_revealed(tool != "answer" or revealed)
	tool_selected.emit(tool)

func set_selection(item: Dictionary) -> void:
	selection = item.duplicate(true)
	if is_node_ready(): _refresh_selected()

func set_supported_text_actions(actions: Array) -> void:
	supported_text_actions = actions.duplicate()
	if is_node_ready(): _refresh_selected()

func _process(delta: float) -> void:
	if not is_node_ready(): return
	var viewport_rect := get_viewport_rect()
	scale = Vector2.ONE * clampf((viewport_rect.size.y - 95.0) / 570.0, .68, 1.10)
	var pointer := get_local_mouse_position()
	var over_edge := Rect2(0,0,PEEK,TRAY_HEIGHT).has_point(pointer)
	var over_open := revealed and Rect2(0,0,WIDTH,TRAY_HEIGHT).has_point(pointer)
	var over_properties := _property_panel.visible and _property_panel.get_rect().has_point(pointer-_panel.position)
	if over_edge or over_open or over_properties:
		_leave_elapsed=0.0
		_set_revealed(true)
	elif tool=="answer":
		_leave_elapsed+=delta
		if _leave_elapsed>.22:_set_revealed(false)
	_panel.position.x = move_toward(_panel.position.x, _target_x, 1100.0 * delta)
	var remaining := (get_parent() as Control).size.y/scale.y-_property_panel.position.y
	_property_panel.size=Vector2(WIDTH,maxf(0,remaining))
	if absf(_panel.position.x - _target_x) < 0.5: _panel.position.x = _target_x

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_target_x = 0.0 if revealed else PEEK - WIDTH

func _set_revealed(value: bool, instant := false) -> void:
	revealed = value or tool != "answer"
	_target_x = 0.0 if revealed else PEEK - WIDTH
	if instant and _panel: _panel.position.x = _target_x
	if _panel: _panel.size.y = 560 if tool != "answer" else TRAY_HEIGHT
	for key in _buttons:
		_buttons[key].mouse_filter = Control.MOUSE_FILTER_STOP if revealed else Control.MOUSE_FILTER_IGNORE

func _build() -> void:
	_panel = Control.new()
	_panel.custom_minimum_size = Vector2(WIDTH, 332)
	_panel.size = _panel.custom_minimum_size
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_body = Body.new()
	_body.size = Vector2(WIDTH, 332)
	_body.scale.y=TRAY_SCALE_Y
	_panel.add_child(_body)
	for spec in [["pencil", "✎ Pencil", "Draw on paper (P)"], ["eraser", "◯ Eraser", "Erase marks (E)"], ["text", "T Text", "Place or select text (T)"]]:
		var name: String = spec[0]
		var button := Button.new()
		button.text = ""
		button.tooltip_text = spec[2] + ". Select again to leave the tool."
		button.toggle_mode = true
		button.position = Vector2(16 + TOOLS.find(name) * 88, 72*TRAY_SCALE_Y)
		button.size = Vector2(78, 208)
		button.scale.y=TRAY_SCALE_Y
		button.flat = true
		for state in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
			button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(func(): _choose(name))
		_panel.add_child(button)
		_buttons[name] = button
	_property_panel = PanelContainer.new()
	_property_panel.position = Vector2(0,TRAY_HEIGHT+10)
	_property_panel.custom_minimum_size.x = WIDTH
	_property_panel.add_theme_stylebox_override("panel", T.surface(Color("1b3542"), Color("89b9b2"), 12))
	_panel.add_child(_property_panel)
	var compact := WorkspaceTheme.create()
	compact.default_font_size=13
	for type in ["Label","Button","OptionButton","LineEdit","ColorPickerButton","CheckButton"]:
		compact.set_font_size("font_size",type,13)
		for state in compact.get_stylebox_list(type):
			var style := compact.get_stylebox(state,type).duplicate() as StyleBox
			style.content_margin_top=3
			style.content_margin_bottom=3
			compact.set_stylebox(state,type,style)
	_property_panel.theme=compact
	var property_stack := VBoxContainer.new()
	property_stack.add_theme_constant_override("separation",3)
	_property_panel.add_child(property_stack)
	var header := HBoxContainer.new()
	property_stack.add_child(header)
	var title := _label("Tool properties")
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text="×"
	close.tooltip_text="Hide tool properties"
	close.accessibility_name="Hide tool properties"
	header.add_child(close)
	close.pressed.connect(func():
		_properties_hidden=true
		_property_panel.hide())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	property_stack.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	_property_host = VBoxContainer.new()
	fields.add_child(_property_host)
	_selected_host = VBoxContainer.new()
	fields.add_child(_selected_host)
	_refresh()

func _choose(value: String) -> void:
	if tool==value and _properties_hidden:
		_properties_hidden=false
		_property_panel.show()
		return
	set_tool("answer" if tool == value else value)

func _refresh() -> void:
	for key in TOOLS:
		var button: Button = _buttons[key]
		button.button_pressed = tool == key
	_body.selected = tool
	_body.queue_redraw()
	_property_panel.visible = tool != "answer" and not _properties_hidden
	_clear_children(_property_host)
	if tool == "answer":
		pass
	elif tool == "pencil":
		_property_host.add_child(_label("PENCIL BRUSH"))
		_slider("Size", "width", 1, 32, 1)
		_slider("Hardness", "hardness", 0, 1, 0.05)
		_slider("Opacity", "opacity", 0.05, 1, 0.05)
		_color()
	elif tool == "eraser":
		_property_host.add_child(_label("ERASER"))
		_slider("Size", "width", 4, 64, 1)
	else:
		_property_host.add_child(_label("TEXT DEFAULTS"))
		_text_fields(false)
	_refresh_selected()

func _clear_children(host: Control) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _slider(title: String, key: String, low: float, high: float, step_value: float, selected := false) -> void:
	var host := _selected_host if selected else _property_host
	var row := HBoxContainer.new()
	host.add_child(row)
	var label := _label(title)
	label.custom_minimum_size.x = 85
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step_value
	var current := float(selection.get(key, properties.get(key, low))) if selected else float(properties.get(key, low))
	if selected and key == "angle": current = rad_to_deg(current)
	spin.value = clampf(current, low, high)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.tooltip_text = title + (" for selected text" if selected else " for the next mark")
	row.add_child(spin)
	spin.value_changed.connect(func(value: float): _change(key, value, selected))

func _color(selected := false) -> void:
	var host := _selected_host if selected else _property_host
	var row := HBoxContainer.new()
	host.add_child(row)
	var label := _label("Color")
	label.custom_minimum_size.x = 85
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = Color(str(selection.get("color", properties.color)) if selected else str(properties.color))
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(90, 25)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = "Color for selected text" if selected else "Color for the next mark"
	row.add_child(picker)
	picker.color_changed.connect(func(value: Color): _change("color", value.to_html(false), selected))

func _text_fields(selected: bool) -> void:
	var host := _selected_host if selected else _property_host
	var row := HBoxContainer.new()
	host.add_child(row)
	var font_label := _label("Font")
	font_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	font_label.custom_minimum_size.x = 85
	row.add_child(font_label)
	var font := OptionButton.new()
	font.accessibility_name = "Font"
	font.custom_minimum_size.y = 25
	for family in ["Sans", "Serif", "Mono"]: font.add_item(family)
	font.select(maxi(0, ["Sans", "Serif", "Mono"].find(str(selection.get("font", "Sans") if selected else properties.font))))
	font.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(font)
	font.item_selected.connect(func(i: int): _change("font", font.get_item_text(i), selected))
	_slider("Opacity", "opacity", 0.05, 1.0, 0.05, selected)
	_color(selected)
	var style_row := HBoxContainer.new();host.add_child(style_row)
	for spec in [["bold","Bold"],["italic","Italic"]]:
		var key: String=spec[0]
		var toggle := CheckBox.new();toggle.text=spec[1]
		toggle.button_pressed=bool(selection.get(key,properties.get(key,false))) if selected else bool(properties.get(key,false))
		style_row.add_child(toggle)
		toggle.toggled.connect(func(value: bool):_change(key,value,selected))
	var alignment := OptionButton.new();host.add_child(alignment)
	for value in ["left","center","right"]:alignment.add_item(value.capitalize())
	alignment.select(maxi(0,["left","center","right"].find(str(selection.get("align",properties.align)) if selected else str(properties.align))))
	alignment.item_selected.connect(func(index: int):_change("align",["left","center","right"][index],selected))
	var equation := CheckBox.new()
	equation.text = "Equation layout"
	equation.tooltip_text = "Render fractions and superscripts in this text"
	equation.button_pressed = bool(selection.get("kind", "text") == "equation") if selected else bool(properties.equation)
	host.add_child(equation)
	equation.toggled.connect(func(value: bool): _change("equation", value, selected))

func _refresh_selected() -> void:
	_clear_children(_selected_host)
	var editing := tool == "text" and not selection.is_empty() and not bool(selection.get("baked", false))
	_property_host.visible = not editing
	if not editing: return
	_text_fields(true)
	if "delete" in supported_text_actions:
		var button := Button.new()
		button.text="Delete"
		button.custom_minimum_size.y=24
		button.pressed.connect(func():text_action.emit("delete"))
		_selected_host.add_child(button)

func _change(key: String, value: Variant, selected: bool) -> void:
	if selected:
		# The workspace applies this to the selected annotation and records undo.
		var annotation_value: Variant = deg_to_rad(float(value)) if key == "angle" else value
		selection[key] = annotation_value
		if key == "equation": selection["kind"] = "equation" if value else "text"
		properties_changed.emit({"_scope": "selection", key: annotation_value})
	else:
		properties[key] = value
		properties_changed.emit(properties.duplicate(true))

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit: return
	match event.keycode:
		KEY_P: _choose("pencil")
		KEY_E: _choose("eraser")
		KEY_T: _choose("text")
		KEY_ESCAPE:
			if tool != "answer": set_tool("answer")
			else: return
		_: return
	get_viewport().set_input_as_handled()
