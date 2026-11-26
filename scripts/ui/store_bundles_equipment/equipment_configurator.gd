extends ConfirmationDialog

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Handset = preload("res://scripts/campus/phones/phone_handset.gd")
const Finish = preload("res://scripts/campus/items/equipment_finish.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")

var profile: RefCounted
var bought: Callable
var configuration: Dictionary
var kind: String
var base_price: int
var stage := 0
var headings: Label
var price: Label
var review: Label
var back: Button
var sections: Array[GridContainer] = []
var preview: SubViewport
var phone: Node3D
var rendered_product: Node3D
var keypad_panel: VBoxContainer
var keypad_grid: GridContainer
var optional_keys: HBoxContainer
var preview_builder: Callable

func build(owner: RefCounted, purchase_completed: Callable, product: Dictionary, model_builder: Callable) -> void:
	profile=owner
	bought=purchase_completed
	kind=product.kind
	base_price=product.price
	preview_builder=model_builder
	configuration=Config.defaults(kind)
	title="Configure " + str(product.name).to_lower()
	dialog_hide_on_ok=false
	var layout:=VBoxContainer.new()
	layout.custom_minimum_size=Vector2(610,350)
	layout.add_theme_constant_override("separation",12)
	add_child(layout)
	var header:=HBoxContainer.new()
	layout.add_child(header)
	headings=Widgets.text("","Title")
	headings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(headings)
	price=Widgets.text("","SubtitleLabel")
	header.add_child(price)
	var workbench:=HBoxContainer.new()
	workbench.size_flags_vertical=Control.SIZE_EXPAND_FILL
	workbench.add_theme_constant_override("separation",16)
	layout.add_child(workbench)
	_build_preview(workbench,model_builder)
	var options:=VBoxContainer.new()
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var scroll:=ScrollContainer.new()
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x=345
	workbench.add_child(scroll)
	scroll.add_child(options)
	for group in ["hardware","appearance"]:
		var fields:=GridContainer.new()
		fields.columns=2
		fields.add_theme_constant_override("h_separation",10)
		fields.add_theme_constant_override("v_separation",8)
		options.add_child(fields)
		sections.append(fields)
		for key in Config.DEFINITIONS[kind][group]:
			var option: Dictionary=Config.DEFINITIONS[kind][group][key]
			fields.add_child(Widgets.text(option.label))
			var selector:=OptionButton.new()
			selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			for choice in option.labels:selector.add_item(choice)
			selector.item_selected.connect(_select.bind(group,key))
			fields.add_child(selector)
	review=Widgets.text("")
	if kind==Config.CALCULATOR:
		keypad_panel=VBoxContainer.new()
		options.add_child(keypad_panel)
		var instructions:=Widgets.text("Drag keys to swap positions. Optional keys can be toggled below.","MutedLabel")
		instructions.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		keypad_panel.add_child(instructions)
		keypad_grid=GridContainer.new()
		keypad_panel.add_child(keypad_grid)
		optional_keys=HBoxContainer.new()
		keypad_panel.add_child(optional_keys)
		_rebuild_keypad()
	review.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	options.add_child(review)
	back=add_button("Back",true,"back")
	custom_action.connect(func(action: StringName):
		if action==&"back":_show_stage(stage-1))
	confirmed.connect(_advance)
	canceled.connect(queue_free)
	_show_stage(0)
	_update_quote()

func _build_preview(parent: Control, model_builder: Callable) -> void:
	var frame:=PanelContainer.new()
	frame.theme_type_variation="CardPanel"
	frame.custom_minimum_size=Vector2(200,265)
	parent.add_child(frame)
	var display:=SubViewportContainer.new()
	display.stretch=true
	frame.add_child(display)
	preview=SubViewport.new()
	preview.own_world_3d=true
	preview.transparent_bg=true
	preview.msaa_3d=Viewport.MSAA_2X
	display.add_child(preview)
	phone=Node3D.new()
	preview.add_child(phone)
	if kind==Config.PHONE:
		Handset.build(phone)
		rendered_product=phone
	elif kind in [Config.CALCULATOR,Config.BACKPACK]:
		rendered_product=Node3D.new()
		phone.add_child(rendered_product)
	else:
		rendered_product=model_builder.call(kind,phone)
	phone.rotation=Vector3(-.85 if kind==Config.NOTEBOOK else .28 if kind==Config.LAPTOP else -.12,-.38,.09)
	var camera:=Camera3D.new()
	camera.position=Vector3(0,0,{Config.PHONE:.36,Config.LAPTOP:.98,Config.USB:.21,Config.NOTEBOOK:.60,Config.BACKPACK:.89,Config.CALCULATOR:.43}[kind])
	camera.fov=42
	preview.add_child(camera)
	for setup in [[Vector3(-26,-30,0),1.4],[Vector3(15,63,0),.8]]:
		var light:=DirectionalLight3D.new()
		light.rotation_degrees=setup[0]
		light.light_energy=setup[1]
		preview.add_child(light)
	display.tooltip_text="Drag to rotate the preview"
	display.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			phone.rotate_y(event.relative.x*.013)
			phone.rotation.x=clampf(phone.rotation.x+event.relative.y*.012,-1.2,1.2)
			preview.render_target_update_mode=SubViewport.UPDATE_ONCE)
	display.resized.connect(func():preview.render_target_update_mode=SubViewport.UPDATE_ONCE)

func _select(index: int, group: String, key: String) -> void:
	configuration[group][key]=index
	if kind==Config.CALCULATOR and group=="hardware":
		if key=="model":configuration.keypad=Config.Keypad.keys(_calculator_model())
		_rebuild_keypad()
	_update_quote()

func _calculator_model() -> String:
	return Config.value(kind,configuration,"hardware","model","calculator_basic")

func _rebuild_keypad() -> void:
	for parent in [keypad_grid,optional_keys]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	keypad_grid.columns=int(Config.value(kind,configuration,"hardware","columns",4))
	for index in configuration.keypad.size():
		var key: String=configuration.keypad[index]
		var button:=Button.new()
		button.text=key
		button.tooltip_text="Drag to move "+key
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		keypad_grid.add_child(button)
		button.set_drag_forwarding(_drag_key.bind(button,index),_can_drop_key,_drop_key.bind(index))
	for key in Config.Keypad.OPTIONAL:
		if key not in Config.Keypad.keys(_calculator_model()):continue
		var button:=CheckButton.new()
		button.text=key
		button.button_pressed=key in configuration.keypad
		button.toggled.connect(_toggle_key.bind(key))
		optional_keys.add_child(button)

func _drag_key(_position: Vector2, button: Button, index: int) -> Dictionary:
	var label:=Label.new()
	label.text=button.text
	button.set_drag_preview(label)
	return {"key_index":index}

func _can_drop_key(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("key_index") is int and data.key_index in range(configuration.keypad.size())

func _drop_key(position: Vector2, data: Variant, destination: int) -> void:
	if not _can_drop_key(position,data) or data.key_index==destination:return
	var key: String=configuration.keypad[destination]
	configuration.keypad[destination]=configuration.keypad[data.key_index]
	configuration.keypad[data.key_index]=key
	_rebuild_keypad()
	_update_quote()

func _toggle_key(enabled: bool, key: String) -> void:
	if enabled:configuration.keypad.append(key)
	else:configuration.keypad.erase(key)
	_rebuild_keypad()
	_update_quote()

func _quote() -> Dictionary:
	return Config.quote(kind,base_price,configuration)

func _update_quote() -> void:
	var quoted:=_quote()
	price.text="$%d"%quoted.price
	if kind==Config.PHONE:Handset.apply_appearance(phone,configuration.appearance)
	elif kind==Config.NOTEBOOK:preload("res://scripts/campus/items/notebook_model.gd").update(rendered_product,configuration)
	elif kind==Config.BACKPACK:
		var model: String=Config.value(kind,configuration,"hardware","size","backpack_small")
		preload("res://scripts/campus/items/backpack_model.gd").update(rendered_product,model,configuration)
	elif kind==Config.CALCULATOR:
		for child in rendered_product.get_children():
			rendered_product.remove_child(child)
			child.queue_free()
		preview_builder.call(kind,rendered_product,configuration)
	else:Finish.apply_finish(rendered_product,kind,configuration)
	preview.render_target_update_mode=SubViewport.UPDATE_ONCE

func _show_stage(index: int) -> void:
	stage=clampi(index,0,2)
	headings.text=["Specifications","Appearance","Review purchase"][stage]
	ok_button_text=["Continue to appearance","Review","Confirm purchase"][stage]
	back.visible=stage>0
	for i in sections.size():sections[i].visible=i==stage
	if is_instance_valid(keypad_panel):keypad_panel.visible=stage==0
	review.visible=stage==2
	if stage==2:
		var lines:=PackedStringArray()
		for group in ["hardware","appearance"]:
			for key in Config.DEFINITIONS[kind][group]:
				var option: Dictionary=Config.DEFINITIONS[kind][group][key]
				lines.append("%s  ·  %s"%[option.label,option.labels[configuration[group][key]]])
		if kind==Config.CALCULATOR:lines.append("Keypad  ·  %d keys"%configuration.keypad.size())
		review.text="\n".join(lines)

func _advance() -> void:
	if stage<2:
		_show_stage(stage+1)
		return
	get_ok_button().disabled=true
	var message: String
	match kind:
		Config.PHONE:message=profile.buy_smartphone("basic",6,"",configuration)
		Config.LAPTOP:message=profile.buy_portable_laptop("basic",6,"",configuration)
		Config.NOTEBOOK:message=profile.buy_study_tool(Config.NOTEBOOK,6,configuration)
		Config.BACKPACK:message=profile.buy_study_tool(Config.BACKPACK,6,configuration)
		Config.CALCULATOR:message=profile.buy_study_tool(Config.CALCULATOR,6,configuration)
		Config.USB:
			var capacity:=int(Config.value(Config.USB,configuration,"hardware","storage",8))
			message=profile.buy_usb(capacity,6,"",configuration)
	hide()
	queue_free()
	bought.call(message)
