extends Control
signal saved(message: String)
const Model=preload("res://review_artifacts/circuit_redesign_20261107/ic_pcb_editor/modules/package_pin_model.gd")
const Preview=preload("res://review_artifacts/circuit_redesign_20261107/ic_pcb_editor/modules/package_preview.gd")
var model=Model.new()
var profile: RefCounted
var preview: Control
var inspector: VBoxContainer
var status: Label
var selected_index:=-1

func open_project(owner_profile: RefCounted,board: Dictionary,draft: Dictionary,kind: String) -> void:
	profile=owner_profile;model.open(board,draft,kind)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root:=VBoxContainer.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(root)
	var header:=HBoxContainer.new();root.add_child(header)
	var title:=Label.new();title.text="IC package" if kind=="IC" else "PCB package";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	_button(header,"Save",func():var message:=model.save(profile);status.text=message;saved.emit(message))
	_button(header,"Rotate package",func():
		if not model.rotate():status.text=model.error
		_base_fields();preview.queue_redraw())
	var split:=HSplitContainer.new();split.size_flags_vertical=Control.SIZE_EXPAND_FILL;root.add_child(split)
	preview=Preview.new();preview.model=model;preview.custom_minimum_size=Vector2(420,360);preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL;preview.size_flags_vertical=Control.SIZE_EXPAND_FILL;split.add_child(preview)
	preview.selected.connect(_select);preview.moved.connect(func(index,point):
		if not model.set_pin(index,{"position":{"x":point.x,"y":point.y}}):status.text=model.error
		preview.queue_redraw();_select(index))
	preview.add_requested.connect(func(point):
		if model.add_pin(point):_select(model.pins.size()-1)
		else:status.text=model.error
		preview.queue_redraw())
	inspector=VBoxContainer.new();inspector.custom_minimum_size.x=260;split.add_child(inspector)
	_base_fields()
	status=Label.new();status.text="Click a pin to inspect it. Drag to reposition; click an empty grid cell to add.";root.add_child(status)

func _base_fields() -> void:
	for child in inspector.get_children():inspector.remove_child(child);child.queue_free()
	var name:=LineEdit.new();name.placeholder_text="Package name";name.text=str(model.draft.get("name",""));inspector.add_child(name);name.text_changed.connect(func(value):model.draft.name=value)
	var description:=LineEdit.new();description.placeholder_text="Description";description.text=str(model.draft.get("description",""));inspector.add_child(description);description.text_changed.connect(func(value):model.draft.description=value)
	var marking:=LineEdit.new();marking.placeholder_text="Surface marking";marking.text=str(model.draft.get("marking",""));inspector.add_child(marking);marking.text_changed.connect(func(value):model.draft.marking=value)
	for axis in ["width","height"]:
		var spin:=SpinBox.new();spin.min_value=2;spin.max_value=80;spin.value=int(model.draft.footprint[axis]);spin.prefix=axis.capitalize()+"  ";inspector.add_child(spin)
		spin.value_changed.connect(func(value):
			var old=model.draft.footprint[axis];model.draft.footprint[axis]=int(value)
			if model.validate()!="":model.draft.footprint[axis]=old;spin.set_value_no_signal(old);status.text=model.error
			preview.queue_redraw())
	var body:=SpinBox.new();body.min_value=.1;body.max_value=100;body.step=.1;body.value=float(model.draft.footprint.get("body_height_mm",3));body.prefix="Body mm  ";inspector.add_child(body);body.value_changed.connect(func(value):model.draft.footprint.body_height_mm=value)
	var thickness:=SpinBox.new();thickness.min_value=.1;thickness.max_value=100;thickness.step=.1;thickness.value=float(model.draft.footprint.get("thickness_mm",1.6));thickness.prefix="Board mm  ";inspector.add_child(thickness);thickness.value_changed.connect(func(value):model.draft.footprint.thickness_mm=value)
	var color:=ColorPickerButton.new();color.color=Color(str(model.draft.footprint.get("color","24775b")));inspector.add_child(color);color.color_changed.connect(func(value):model.draft.footprint.color=value.to_html(false);preview.queue_redraw())
	var orientation:=OptionButton.new();inspector.add_child(orientation)
	for item in ["dot","notch","triangle","none"]:orientation.add_item(item)
	orientation.select(["dot","notch","triangle","none"].find(str(model.draft.get("orientation_marker","dot"))))
	orientation.item_selected.connect(func(_index):model.draft.orientation_marker=orientation.text)
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

func _button(parent: Node,label: String,action: Callable) -> void:
	var button:=Button.new();button.text=label;button.focus_mode=Control.FOCUS_ALL;parent.add_child(button);button.pressed.connect(action)
