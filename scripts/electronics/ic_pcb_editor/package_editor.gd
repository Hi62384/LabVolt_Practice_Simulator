extends Control
signal saved(message: String)
const Model=preload("res://scripts/electronics/ic_pcb_editor/package_pin_model.gd")
const Preview=preload("res://scripts/electronics/ic_pcb_editor/package_preview.gd")
var model=Model.new()
var profile: RefCounted
var preview: Control
var preview_3d: SubViewportContainer
var inspector: VBoxContainer
var status: Label
var selected_index:=-1
var active_page := 0
var steps: Array[Button] = []

func open_project(owner_profile: RefCounted,board: Dictionary,draft: Dictionary,kind: String) -> void:
	profile=owner_profile;model.open(board,draft,kind)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root:=VBoxContainer.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(root)
	var header:=HBoxContainer.new();root.add_child(header)
	var title:=Label.new();title.text="IC / PCB Builder   ›   " + ("IC package" if kind=="IC" else "PCB package");title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",8)
	root.add_child(tabs)
	for i in range(4):
		var tab := _button(tabs,["Package","Surface","Pins","Preview"][i],func(): _page(i))
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		steps.append(tab)
	var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;root.add_child(split)
	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(stage)
	preview=Preview.new();preview.model=model;preview.custom_minimum_size=Vector2(320,290);preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL;preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;stage.add_child(preview)
	preview_3d = preload("res://scripts/electronics/ic_pcb_editor/package_view_3d.gd").new()
	preview_3d.model = model
	preview_3d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(preview_3d)
	preview_3d.hide()
	preview.selected.connect(_select);preview.moved.connect(func(index,point):
		if not model.set_pin(index,{"position":{"x":point.x,"y":point.y}}):status.text=model.error
		preview.queue_redraw();_select(index))
	preview.add_requested.connect(func(point):
		if model.add_pin(point):_select(model.pins.size()-1)
		else:status.text=model.error
		preview.queue_redraw())
	var inspector_scroll:=ScrollContainer.new();inspector_scroll.custom_minimum_size.x=280;inspector_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;split.add_child(inspector_scroll)
	inspector=VBoxContainer.new();inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inspector_scroll.add_child(inspector)
	var footer := HBoxContainer.new()
	root.add_child(footer)
	_button(footer,"Save",func():status.text=model.save_draft(profile))
	_button(footer,"Save As…",_save_as)
	_button(footer,"Validate",func():
		var result := model.validate_package(profile)
		status.text = "Package is ready to create." if result.is_empty() else result)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_button(footer,"Create Package",func():
		var message := model.save(profile)
		status.text = message
		saved.emit(message))
	status=Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status)
	_page(0)

func _page(index: int) -> void:
	active_page = index
	for i in steps.size(): steps[i].set_pressed_no_signal(i == index)
	preview.visible = index == 2
	preview_3d.visible = index != 2
	status.text = ["Set the package type and dimensions.", "Choose the color, marking and orientation marker.",
		"Click an empty cell to add a pin, or drag an existing pin.", "Drag to orbit · Mouse wheel to zoom"][index]
	_base_fields()

func _save_as() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Save package draft as"
	var input := LineEdit.new()
	input.placeholder_text = "Project name"
	input.max_length = 32
	input.custom_minimum_size.x = 320
	dialog.add_child(input)
	add_child(dialog)
	dialog.confirmed.connect(func():
		if not input.text.strip_edges().is_empty(): status.text = model.save_draft(profile,input.text.strip_edges())
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	input.grab_focus()

func _process(_delta: float) -> void:
	if is_instance_valid(preview_3d) and preview_3d.is_visible_in_tree():preview_3d.refresh()

func _base_fields() -> void:
	for child in inspector.get_children():inspector.remove_child(child);child.queue_free()
	if active_page == 3:
		var summary := Label.new()
		summary.text = "%s   ·   %d × %d grid\n%d mapped pins" % [model.draft.package,model.draft.footprint.width,model.draft.footprint.height,model.pins.size()]
		inspector.add_child(summary)
		return
	if active_page == 0:
		var type := OptionButton.new()
		type.add_item("IC")
		type.add_item("PCB")
		type.select(0 if model.draft.package == "IC" else 1)
		inspector.add_child(type)
		type.item_selected.connect(func(_index):model.draft.package=type.text;preview_3d.refresh())
		var name:=LineEdit.new();name.placeholder_text="Package name";name.text=str(model.draft.get("name",""));inspector.add_child(name);name.text_changed.connect(func(value):model.draft.name=value)
		var description:=LineEdit.new();description.placeholder_text="Description";description.text=str(model.draft.get("description",""));inspector.add_child(description);description.text_changed.connect(func(value):model.draft.description=value)
		for axis in ["width","height"]:
			var spin:=SpinBox.new();spin.min_value=2;spin.max_value=80;spin.value=int(model.draft.footprint[axis]);spin.prefix=axis.capitalize()+"  ";inspector.add_child(spin)
			spin.value_changed.connect(func(value):
				var old=model.draft.footprint[axis];model.draft.footprint[axis]=int(value)
				if model.validate()!="":model.draft.footprint[axis]=old;spin.set_value_no_signal(old);status.text=model.error
				preview.queue_redraw())
		var body:=SpinBox.new();body.min_value=.1;body.max_value=100;body.step=.1;body.value=float(model.draft.footprint.get("body_height_mm",3));body.prefix="Body mm  ";inspector.add_child(body);body.value_changed.connect(func(value):model.draft.footprint.body_height_mm=value)
		var thickness:=SpinBox.new();thickness.min_value=.1;thickness.max_value=100;thickness.step=.1;thickness.value=float(model.draft.footprint.get("thickness_mm",1.6));thickness.prefix="Board mm  ";inspector.add_child(thickness);thickness.value_changed.connect(func(value):model.draft.footprint.thickness_mm=value)
		_button(inspector,"Rotate package",func():
			if not model.rotate():status.text=model.error
			_base_fields();preview.queue_redraw())
		return
	if active_page == 1:
		var marking:=LineEdit.new();marking.placeholder_text="Surface marking";marking.text=str(model.draft.get("marking",""));inspector.add_child(marking);marking.text_changed.connect(func(value):model.draft.marking=value)
		var color:=ColorPickerButton.new();color.color=Color(str(model.draft.footprint.get("color","24775b")));inspector.add_child(color);color.color_changed.connect(func(value):model.draft.footprint.color=value.to_html(false);preview.queue_redraw())
		var orientation:=OptionButton.new();inspector.add_child(orientation)
		for item in ["dot","notch","triangle","none"]:orientation.add_item(item)
		orientation.select(["dot","notch","triangle","none"].find(str(model.draft.get("orientation_marker","dot"))))
		orientation.item_selected.connect(func(_index):model.draft.orientation_marker=orientation.text)
		return
	var layout := OptionButton.new()
	for preset in ["Dual row","Single row","Perimeter"]: layout.add_item(preset)
	inspector.add_child(layout)
	var spacing := SpinBox.new()
	spacing.min_value = 1
	spacing.max_value = 8
	spacing.prefix = "Spacing   "
	inspector.add_child(spacing)
	_button(inspector,"Apply pin layout",func():
		if model.apply_layout(layout.selected, int(spacing.value)):
			preview.queue_redraw()
		else: status.text = model.error)
	var advanced:=CheckButton.new();advanced.text="Advanced pin table";inspector.add_child(advanced)
	var table:=VBoxContainer.new();table.visible=false;inspector.add_child(table)
	advanced.toggled.connect(func(value):table.visible=value)
	for i in model.pins.size():
		var row:=HBoxContainer.new();table.add_child(row)
		var button:=Button.new();button.text=str(i+1);row.add_child(button);button.pressed.connect(func():_select(i))
		for key in ["name","hole"]:
			var field:=LineEdit.new();field.text=str(model.pins[i].get(key,""));field.custom_minimum_size.x=80;row.add_child(field)
			field.text_submitted.connect(func(value):
				if not model.set_pin(i,{key:value.strip_edges().to_upper() if key=="hole" else value.strip_edges()}):status.text=model.error
				preview.queue_redraw())
	if selected_index>=0 and selected_index<model.pins.size():_pin_fields()

func _select(index: int) -> void:
	selected_index=index;preview.selected_index=index;preview.queue_redraw();_base_fields()

func _pin_fields() -> void:
	var pin: Dictionary=model.pins[selected_index]
	var heading:=Label.new();heading.text="Pin %d · %s"%[selected_index+1,str(pin.id)];inspector.add_child(heading)
	for key in ["name","hole"]:
		var field:=LineEdit.new();field.placeholder_text="Pin name" if key=="name" else "Internal breadboard hole";field.text=str(pin.get(key,""));inspector.add_child(field)
		field.text_submitted.connect(func(value):
			if not model.set_pin(selected_index,{key:value.strip_edges().to_upper() if key=="hole" else value.strip_edges()}):status.text=model.error
			_select(selected_index))
	for key in ["role","connector"]:
		var field:=OptionButton.new();inspector.add_child(field)
		var values:=preload("res://scripts/package_editor/package_geometry.gd").ROLES if key=="role" else preload("res://scripts/package_editor/package_geometry.gd").CONNECTORS
		for value in values:field.add_item(value)
		field.select(values.find(str(pin.get(key,values[0]))))
		field.item_selected.connect(func(_index):model.set_pin(selected_index,{key:field.text}))
	for axis in ["x","y"]:
		var spin:=SpinBox.new();spin.prefix=axis.to_upper()+"  ";spin.min_value=0;spin.max_value=int(model.draft.footprint.width if axis=="x" else model.draft.footprint.height)-1;spin.value=int(pin.position[axis]);inspector.add_child(spin)
		spin.value_changed.connect(func(value):
			var position: Dictionary=model.pins[selected_index].position.duplicate(true);position[axis]=int(value)
			if not model.set_pin(selected_index,{"position":position}):status.text=model.error;spin.set_value_no_signal(int(model.pins[selected_index].position[axis]))
			preview.queue_redraw())
	_button(inspector,"Remove pin",func():
		if model.remove_pin(selected_index):selected_index=-1;_base_fields();preview.queue_redraw()
		else:status.text=model.error)

func _button(parent: Node,label: String,action: Callable) -> Button:
	var button:=Button.new();button.text=label;button.focus_mode=Control.FOCUS_ALL;parent.add_child(button);button.pressed.connect(action)
	button.custom_minimum_size.y = 44
	return button
