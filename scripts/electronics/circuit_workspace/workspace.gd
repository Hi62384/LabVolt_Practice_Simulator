extends VBoxContainer
signal panel_requested(kind: String)
signal design_changed(board: Dictionary)
signal selection_changed(ids: Array)
signal placing_changed(type_id: String, instance_id: String)
signal component_selected(type_id: String)
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const LOWER_BANK_OPTION := 100
var canvas: Control
var actions: Dictionary
var state: Label
var project_menu: PopupMenu
var maker := false
var simulating := false
var simulation_button: Button
var placing_instance := ""
var sidebar: Control
var project_name: Label
var notices: Timer
var mode_buttons: Dictionary = {}
var size_button: MenuButton

func _process(_delta: float) -> void:
	if has_meta("panels"):get_meta("panels").refresh_measurement()

func configure(board: Dictionary, callbacks: Dictionary) -> void:
	actions=callbacks
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	var header:=HFlowContainer.new();add_child(header)
	var commands := MenuButton.new()
	commands.text = "Board ▾"
	header.add_child(commands)
	for entry in [["Save","save"],["Undo","undo"],["Redo","redo"],["Deploy","deploy"],["Disconnect","recall"],["Fit selection","fit_selection"]]:
		var key: String=entry[1]
		var menu := commands.get_popup()
		menu.add_item(entry[0])
		menu.set_item_metadata(menu.item_count - 1, key)
	commands.get_popup().index_pressed.connect(func(index: int):invoke(str(commands.get_popup().get_item_metadata(index))))
	state=Label.new();state.text="Editing";header.add_child(state)
	var tools := header
	project_menu=PopupMenu.new();add_child(project_menu)
	project_menu.add_item("Saved projects",0);project_menu.add_item("Carry board",1);project_menu.add_item("Reset view",2)
	for rows in [10,20,30,40]:project_menu.add_item(str(rows)+" rows",rows)
	project_menu.id_pressed.connect(func(id):
		if id==0:panel_requested.emit("projects")
		elif id==1:invoke("carry")
		elif id==2:canvas.fit_board()
		elif not canvas.resize_board(id):state.text=canvas.resize_error
	)
	for entry in [["Select","select"],["Wire","wire"],["Probe","probe+"],["Delete","remove"],["Interact","interact"]]:
		var key: String=entry[1]
		tools.add_child(UI.action(entry[0],"circuit",func():canvas.first="";canvas.selected_type=key))
	for entry in [["Add","components"],["Analyze","analyzer"],["Bench","bench"],["Project","projects"]]:
		var key: String=entry[1]
		tools.add_child(UI.action(entry[0],"settings",func():
			if key=="projects":project_menu.position=Vector2i(get_global_mouse_position());project_menu.popup()
			else:panel_requested.emit(key)
		))
	tools.add_child(UI.action("Fit","search",func():canvas.fit_board()))
	canvas=preload("res://scripts/electronics/circuit_workspace/workspace_canvas.gd").new()
	canvas.board=board.duplicate(true);canvas.selected_type="select"
	canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL;canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_child(canvas)
	canvas.design_changed.connect(func(candidate):design_changed.emit(candidate))
	canvas.selection_updated.connect(func(ids):selection_changed.emit(ids))

func configure_maker(board: Dictionary, callbacks: Dictionary, catalog: Dictionary, stock: Dictionary, creative: bool, physical := false) -> void:
	maker = true
	actions = callbacks
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var header := HBoxContainer.new()
	add_child(header)
	var commands := [] if physical else [["New Project","new","plus"],["Open Projects","open","folder"],["Save","save","save"]]
	for command in commands:
		header.add_child(UI.action(command[0],command[2],invoke.bind(command[1]),command[1]=="save"))
	project_name = Label.new()
	if physical:project_name.text="Kit breadboard"
	project_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(project_name)
	header.add_child(UI.action("Close","back",invoke.bind("close")))
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation",12)
	add_child(split)
	var board_column := VBoxContainer.new()
	board_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	split.add_child(board_column)
	var toolbar := HFlowContainer.new()
	board_column.add_child(toolbar)
	var mode_panel := PanelContainer.new()
	const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
	mode_panel.add_theme_stylebox_override("panel",Tokens.surface(Tokens.SURFACE,Tokens.BORDER,5))
	toolbar.add_child(mode_panel)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation",1)
	mode_panel.add_child(mode_row)
	const MODE_SIZE := 60
	const SWATCH_HEIGHT := 8
	const SWATCH_GAP := 3
	var wire_palette := ColorPickerButton.new()
	wire_palette.color=Color("ed5555")
	wire_palette.edit_alpha=false
	wire_palette.custom_minimum_size=Vector2(MODE_SIZE,SWATCH_HEIGHT)
	wire_palette.tooltip_text="Wire color"
	wire_palette.accessibility_name="Wire color"
	for style_name in ["normal","hover","pressed"]:
		var border := Tokens.BORDER if style_name=="normal" else Color("8de4cc")
		var swatch_style := Tokens.surface(Tokens.SURFACE,border,1)
		swatch_style.set_corner_radius_all(3)
		wire_palette.add_theme_stylebox_override(style_name,swatch_style)
	wire_palette.color_changed.connect(func(color):canvas.wire_color=color)
	var modes := ButtonGroup.new()
	for mode in [["Select","select","mode_select"],["Wire","wire","mode_wire"],["Place component","place","mode_place"],["Operate inputs","interact","mode_operate"]]:
		var button := UI.action("",mode[2],_choose_mode.bind(mode[1]))
		var icon := TextureRect.new()
		icon.texture=button.icon
		button.icon=null
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left=9
		icon.offset_top=7
		icon.offset_right=-9
		icon.offset_bottom=-7
		button.tooltip_text=mode[0]
		button.accessibility_name=mode[0]
		button.custom_minimum_size.x=MODE_SIZE
		button.toggle_mode = true
		button.button_group = modes
		if mode[1]=="wire":
			button.custom_minimum_size.y=MODE_SIZE-SWATCH_HEIGHT-SWATCH_GAP
			button.size_flags_vertical=Control.SIZE_EXPAND_FILL
			var wire_group := VBoxContainer.new()
			wire_group.add_theme_constant_override("separation",SWATCH_GAP)
			mode_row.add_child(wire_group)
			wire_group.add_child(wire_palette)
			wire_group.add_child(button)
		else:
			button.custom_minimum_size.y=MODE_SIZE
			mode_row.add_child(button)
		mode_buttons[mode[1]] = button
	var board_tools := HBoxContainer.new()
	board_tools.size_flags_vertical=Control.SIZE_SHRINK_END
	toolbar.add_child(board_tools)
	size_button=MenuButton.new()
	size_button.text="Size ▾"
	size_button.flat=false
	size_button.accessibility_name="Breadboard size"
	size_button.custom_minimum_size.y=44
	board_tools.add_child(size_button)
	var size_menu := size_button.get_popup()
	for rows in [10,20,30,40,50,60]:size_menu.add_radio_check_item("%d rows"%rows,rows)
	size_menu.add_separator()
	size_menu.add_check_item("Lower bank",LOWER_BANK_OPTION)
	size_menu.id_pressed.connect(_change_board_size)
	board_tools.add_child(UI.action("Fit","search",func():canvas.fit_board()))
	board_tools.add_child(UI.action("Take all","inventory",func():canvas.take_all()))
	var simulate := UI.action("Simulate","play",Callable(),true)
	simulation_button=simulate
	simulate.toggle_mode = true
	toolbar.add_child(simulate)
	simulate.visible=not physical
	simulate.toggled.connect(func(enabled):
		if enabled and actions.has("validate_simulation"):
			var error: String=actions.validate_simulation.call(canvas.board)
			if not error.is_empty():
				simulate.set_pressed_no_signal(false)
				notify(error)
				return
		simulating = enabled
		simulate.text = "Stop Simulation" if enabled else "Simulate"
		if not enabled:
			canvas.currents.clear()
			canvas.device_states.clear()
			canvas.accept_measurements({})
		notify("Simulation running." if enabled else "Simulation stopped."))
	state = Label.new()
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.custom_minimum_size.x = 120
	state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child(state)
	notices = Timer.new()
	notices.one_shot = true
	notices.wait_time = 4.0
	add_child(notices)
	notices.timeout.connect(func():state.text="")
	canvas = preload("res://scripts/electronics/circuit_workspace/maker_canvas.gd").new()
	canvas.physical_kit=physical
	canvas.board = board.duplicate(true)
	canvas.inventory_catalog = catalog
	canvas.stock_limits = stock
	canvas.unlimited = creative
	sync_board_options()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_column.add_child(canvas)
	sidebar = MarginContainer.new()
	sidebar.custom_minimum_size.x = 290
	split.add_child(sidebar)
	resized.connect(func():sidebar.custom_minimum_size.x=clampf(size.x*.29,260.0,460.0))
	canvas.design_changed.connect(func(candidate):design_changed.emit(candidate);sync_board_options())
	canvas.selection_updated.connect(func(ids):selection_changed.emit(ids))
	canvas.feedback.connect(notify)
	canvas.grabbed_component.connect(func(type_id: String, instance_id: String):
		if type_id.is_empty() and canvas.inventory_catalog.has(canvas.selected_type):
			placing_changed.emit(canvas.selected_type,placing_instance)
		else:
			placing_changed.emit(type_id,instance_id))
	_choose_mode("select")

func _maker_tool(index: int) -> void:
	match index:
		0: canvas.undo()
		1: canvas.redo()
		2: canvas.fit_board()
		3: panel_requested.emit("analyzer")
		4: _choose_mode("interact")

func _choose_mode(mode: String) -> void:
	canvas.cancel_grab()
	canvas.selected_lab_lead=""
	placing_instance=""
	placing_changed.emit("","")
	canvas.first = ""
	canvas.hovered=""
	canvas.placement_turns = 0
	canvas.placement = {}
	canvas.selected.clear()
	canvas.selected_wire=-1
	canvas.moving=false
	canvas.selected_type = mode
	canvas.refresh_selection()
	for id in mode_buttons:
		var button: Button=mode_buttons[id]
		button.set_pressed_no_signal(id==mode)
		button.theme_type_variation=&"PrimaryButton" if id==mode else &"Button"
	canvas.queue_redraw()
	if mode=="wire":
		state.text="Click two holes to connect. Shift-click an occupied hole to start a new jumper."
		if is_instance_valid(notices):notices.stop()
	elif mode=="interact":
		state.text="Click or drag inputs. Scroll over a knob to adjust it."
		if is_instance_valid(notices):notices.stop()

func notify(message: String) -> void:
	state.text = message
	if is_instance_valid(notices): notices.start()

func sync_board_options() -> void:
	var menu := size_button.get_popup()
	var rows := int(canvas.board.rows)
	for row_count in [10,20,30,40,50,60]:
		menu.set_item_checked(menu.get_item_index(row_count),row_count==rows)
	var expanded := bool(canvas.board.get("expanded",false))
	menu.set_item_checked(menu.get_item_index(LOWER_BANK_OPTION),expanded)
	size_button.tooltip_text="%d rows%s" % [rows," · Lower bank enabled" if expanded else ""]

func _change_board_size(option: int) -> void:
	canvas.cancel_grab()
	if option!=LOWER_BANK_OPTION:
		if option!=int(canvas.board.rows) and not canvas.resize_board(option):
			notify(canvas.resize_error)
		sync_board_options()
		return
	var candidate: Dictionary=canvas.board.duplicate(true)
	candidate.expanded=not bool(candidate.get("expanded",false))
	var error: String = canvas.validate_board_layout(candidate)
	if not error.is_empty():
		notify(error)
		return
	canvas.commit()
	canvas.board=candidate
	canvas.design_changed.emit(candidate)
	canvas.fit_board()

func choose_component(type_id: String, instance_id := "") -> void:
	if maker:
		_choose_mode("place" if canvas.inventory_catalog.has(type_id) else type_id)
	canvas.first="";canvas.selected_type=type_id;canvas.grab_focus()
	if maker and canvas.inventory_catalog.has(type_id):
		placing_instance=instance_id
		placing_changed.emit(type_id,instance_id)
	component_selected.emit(type_id)

func invoke(key: String) -> void:
	if key=="undo":canvas.undo()
	elif key=="redo":canvas.redo()
	elif key=="fit_selection":canvas.fit_selection()
	elif actions.get(key,Callable()).is_valid():actions[key].call()

func cancel_action() -> bool:
	if maker and not canvas.selected_lab_lead.is_empty():
		canvas.selected_lab_lead=""
		canvas.queue_redraw()
		return true
	if maker and not canvas.grabbed_hole.is_empty():
		canvas.cancel_grab()
		return true
	if maker and (not canvas.first.is_empty() or canvas.selected_type != "select"):
		_choose_mode("select")
		return true
	if canvas.first.is_empty() and not canvas.moving and canvas.selected_type == "select":return false
	canvas.first = ""
	canvas.moving = false
	canvas.selected_type = "select"
	canvas.queue_redraw()
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if get_meta("project_prompt_open",false):return
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
	var focused:=get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:return
	if canvas.read_only:return
	var handled:=true
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_S:invoke("save")
			KEY_Z:canvas.undo()
			KEY_Y:canvas.redo()
			KEY_C:canvas.copy_selected()
			KEY_V:canvas.paste_selected()
			_:handled=false
	else:
		match event.keycode:
			KEY_DELETE:canvas.delete_selected()
			KEY_R:canvas.rotate_or_preview()
			KEY_ESCAPE:
				if maker: cancel_action()
				else: canvas.first="";canvas.moving=false;canvas.queue_redraw()
			_:handled=false
	if handled:get_viewport().set_input_as_handled()
