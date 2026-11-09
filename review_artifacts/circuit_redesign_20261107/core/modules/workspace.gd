extends VBoxContainer
signal panel_requested(kind: String)
signal design_changed(board: Dictionary)
signal selection_changed(ids: Array)
signal component_selected(type_id: String)
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var canvas: Control
var actions: Dictionary
var state: Label
var project_menu: PopupMenu

func _process(_delta: float) -> void:
	if has_meta("panels"):get_meta("panels").refresh_measurement()

func configure(board: Dictionary, callbacks: Dictionary) -> void:
	actions=callbacks
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	var header:=HFlowContainer.new();add_child(header)
	for entry in [["Save","save"],["Undo","undo"],["Redo","redo"],["Deploy","deploy"],["Disconnect","recall"],["Close","close"]]:
		var key: String=entry[1]
		header.add_child(UI.action(entry[0],UI.action_icon(entry[0]),func():invoke(key)))
	state=Label.new();state.text="Editing";header.add_child(state)
	var tools:=HFlowContainer.new();add_child(tools)
	project_menu=PopupMenu.new();add_child(project_menu)
	project_menu.add_item("Saved projects",0);project_menu.add_item("Carry board",1);project_menu.add_item("Reset view",2)
	for rows in [10,20,30,40]:project_menu.add_item(str(rows)+" rows",rows)
	project_menu.id_pressed.connect(func(id):
		if id==0:panel_requested.emit("projects")
		elif id==1:invoke("carry")
		elif id==2:canvas.fit_board()
		elif not canvas.resize_board(id):state.text="Move components and connections inside the smaller board first."
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
	tools.add_child(UI.action("Fit selection","search",func():canvas.fit_selection()))
	canvas=preload("res://scripts/electronics/circuit_workspace/workspace_canvas.gd").new()
	canvas.board=board.duplicate(true);canvas.selected_type="select"
	canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL;canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_child(canvas)
	canvas.design_changed.connect(func(candidate):design_changed.emit(candidate))
	canvas.selection_updated.connect(func(ids):selection_changed.emit(ids))

func choose_component(type_id: String) -> void:
	canvas.first="";canvas.selected_type=type_id;canvas.grab_focus()
	component_selected.emit(type_id)

func invoke(key: String) -> void:
	if key=="undo":canvas.undo()
	elif key=="redo":canvas.redo()
	elif actions.get(key,Callable()).is_valid():actions[key].call()

func _unhandled_key_input(event: InputEvent) -> void:
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
			KEY_ESCAPE:canvas.first="";canvas.moving=false;canvas.queue_redraw()
			_:handled=false
	if handled:get_viewport().set_input_as_handled()
