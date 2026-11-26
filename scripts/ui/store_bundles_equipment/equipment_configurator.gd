extends ConfirmationDialog

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Handset = preload("res://scripts/campus/phones/phone_handset.gd")
const Finish = preload("res://scripts/campus/items/equipment_finish.gd")
const Display = preload("res://scripts/campus/items/device_display.gd")
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
var optional_keys: HFlowContainer
var screen_demo: ShaderMaterial
var notebook_cover_view:=false
var feature_selectors: Dictionary={}
var fields_scroll: ScrollContainer
var preview_builder: Callable
var decoration_editor: Control
var camera: Camera3D
var preview_distance: float
var preview_rotation: Vector3
var editing_key := ""
var original_configuration: Dictionary={}

func build(owner: RefCounted, purchase_completed: Callable, product: Dictionary, model_builder: Callable, owned: Dictionary = {}, item_key := "") -> void:
	profile=owner
	bought=purchase_completed
	kind=product.kind
	base_price=product.price
	preview_builder=model_builder
	editing_key=item_key
	original_configuration=owned.duplicate(true)
	configuration=Config.defaults(kind) if editing_key.is_empty() else owned.duplicate(true)
	title=("Configure " if editing_key.is_empty() else "Decorate ")+str(product.name).to_lower()
	dialog_hide_on_ok=false
	var layout:=VBoxContainer.new()
	layout.custom_minimum_size=Vector2(620,300)
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
	fields_scroll=scroll
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio=1.15
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x=305
	workbench.add_child(scroll)
	scroll.add_child(options)
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for group in ["hardware","appearance"]:
		var fields:=GridContainer.new()
		fields.columns=2
		fields.add_theme_constant_override("h_separation",10)
		fields.add_theme_constant_override("v_separation",8)
		options.add_child(fields)
		sections.append(fields)
		for key in Config.definitions(kind,int(configuration.version))[group]:
			var option: Dictionary=Config.definitions(kind,int(configuration.version))[group][key]
			fields.add_child(Widgets.text(option.label))
			var selector:=OptionButton.new()
			selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			selector.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			for index in option.labels.size():
				selector.add_item("%s  ·  +$%d"%[option.labels[index],option.prices[index]])
			if group=="hardware":feature_selectors[key]=selector
			selector.select(int(configuration[group][key]))
			selector.item_selected.connect(_select.bind(group,key))
			fields.add_child(selector)
	decoration_editor=preload("res://scripts/ui/store_bundles_equipment/decoration_editor.gd").new()
	options.add_child(decoration_editor)
	decoration_editor.build(profile,kind)
	decoration_editor.restore(configuration.get("decoration",[]))
	decoration_editor.design_changed.connect(_set_decoration)
	decoration_editor.focus_surface.connect(_show_decoration_surface)
	review=Widgets.text("")
	if kind==Config.CALCULATOR:
		keypad_panel=VBoxContainer.new()
		options.add_child(keypad_panel)
		var instructions:=Widgets.text("Drag installed keys to reorder. Click a key below to add or remove it.","MutedLabel")
		instructions.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		keypad_panel.add_child(instructions)
		keypad_grid=GridContainer.new()
		keypad_panel.add_child(keypad_grid)
		optional_keys=HFlowContainer.new()
		keypad_panel.add_child(optional_keys)
		if configuration.has("body"):
			for field in Config.BODY_LIMITS:
				var row:=HBoxContainer.new()
				row.add_child(Widgets.text({"width":"Body width (m)","height":"Body height (m)","weight":"Body weight (kg)"}[field]))
				var limits: Vector2=Config.BODY_LIMITS[field]
				var amount:=SpinBox.new()
				amount.min_value=limits.x
				amount.max_value=limits.y
				amount.step=.001
				amount.value=configuration.body[field]
				amount.value_changed.connect(func(value: float):configuration.body[field]=value;_update_quote())
				row.add_child(amount)
				keypad_panel.add_child(row)
		_rebuild_keypad()
	review.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	options.add_child(review)
	back=add_button("Back",true,"back")
	custom_action.connect(func(action: StringName):
		if action==&"back":_show_stage(stage-1))
	confirmed.connect(_advance)
	canceled.connect(queue_free)
	_show_stage(0 if editing_key.is_empty() else 1)
	_update_quote()

func present() -> void:
	var available: Vector2=get_parent().get_viewport().get_visible_rect().size
	popup_centered(Vector2i(minf(880,available.x-72),minf(580,available.y-104)))

func _refresh_preview() -> void:
	preview.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE if screen_demo!=null else SubViewport.UPDATE_ONCE

func _build_preview(parent: Control, model_builder: Callable) -> void:
	var frame:=PanelContainer.new()
	frame.theme_type_variation="CardPanel"
	frame.custom_minimum_size=Vector2(260,220)
	frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var preview_controls:=VBoxContainer.new()
	frame.add_child(preview_controls)
	var display:=SubViewportContainer.new()
	display.stretch=true
	display.size_flags_vertical=Control.SIZE_EXPAND_FILL
	preview_controls.add_child(display)
	preview=SubViewport.new()
	preview.own_world_3d=true
	preview.transparent_bg=true
	preview.msaa_3d=Viewport.MSAA_2X
	display.add_child(preview)
	phone=Node3D.new()
	preview.add_child(phone)
	if kind==Config.PHONE:
		screen_demo=Display.demo(Handset.build(phone),true)
		rendered_product=phone
	elif kind in [Config.CALCULATOR,Config.BACKPACK,Config.KIT,Config.POWER_BANK]:
		rendered_product=Node3D.new()
		phone.add_child(rendered_product)
	else:
		rendered_product=model_builder.call(kind,phone)
		if kind==Config.LAPTOP and rendered_product.has_meta("equipment_screen"):
			screen_demo=Display.demo(rendered_product.get_meta("equipment_screen"),false)
	phone.rotation=Vector3(-.85 if kind in [Config.NOTEBOOK,Config.POWER_BANK] else .28 if kind in [Config.LAPTOP,Config.KIT] else -.12,-.38,.09)
	preview_rotation=phone.rotation
	camera=Camera3D.new()
	preview_distance={Config.PHONE:.36,Config.LAPTOP:.98,Config.USB:.21,Config.NOTEBOOK:.91,Config.BACKPACK:.89,Config.CALCULATOR:.43,Config.KIT:1.65,Config.POWER_BANK:.32}[kind]
	camera.position=Vector3(0,0,preview_distance)
	camera.fov=42
	preview.add_child(camera)
	for setup in [[Vector3(-26,-30,0),1.4],[Vector3(15,63,0),.8]]:
		var light:=DirectionalLight3D.new()
		light.rotation_degrees=setup[0]
		light.light_energy=setup[1]
		preview.add_child(light)
	display.tooltip_text="Drag to orbit · Right-drag to pan · Scroll to zoom"
	display.gui_input.connect(_preview_input)
	display.resized.connect(_refresh_preview)
	var viewbar:=HBoxContainer.new()
	preview_controls.add_child(viewbar)
	var views:=OptionButton.new()
	var view_data: Array[Vector3]=[preview_rotation,Vector3.ZERO,Vector3(0,PI,0),Vector3(PI/2,0,0),Vector3(-PI/2,0,0),Vector3(0,PI/2,0),Vector3(0,-PI/2,0)]
	for label in ["Orbit view","Front","Back","Top","Bottom","Left","Right"]:views.add_item(label)
	views.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	views.item_selected.connect(func(index: int):_view(view_data[index]))
	viewbar.add_child(views)
	viewbar.add_child(Widgets.action("Reset","",func():views.select(0);_view(preview_rotation)))

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		phone.rotate_y(event.relative.x*.013)
		phone.rotation.x=clampf(phone.rotation.x+event.relative.y*.012,-PI,PI)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		camera.position.x-=event.relative.x*preview_distance*.003
		camera.position.y+=event.relative.y*preview_distance*.003
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var direction:=.90 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.11
		camera.position.z=clampf(camera.position.z*direction,preview_distance*.42,preview_distance*2.5)
	else:return
	_refresh_preview()

func _view(rotation: Vector3) -> void:
	phone.rotation=rotation
	camera.position=Vector3(0,0,preview_distance)
	_refresh_preview()

func _set_decoration(design: Array) -> void:
	if design.is_empty():configuration.erase("decoration")
	else:configuration.decoration=design
	_update_quote()

func _show_decoration_surface() -> void:
	match kind:
		Config.PHONE,Config.LAPTOP,Config.CALCULATOR,Config.KIT:_view(Vector3(.07,PI,0))
		Config.NOTEBOOK:
			notebook_cover_view=true
			preload("res://scripts/campus/items/notebook_model.gd").update(rendered_product,configuration)
			_view(Vector3(1.18,-.14,0))
		Config.USB,Config.POWER_BANK:_view(Vector3(1.18,-.14,0))
		_:_view(Vector3.ZERO)

func _select(index: int, group: String, key: String) -> void:
	configuration[group][key]=index
	if kind==Config.CALCULATOR and group=="hardware":
		if key=="model":configuration.keypad=Config.Keypad.keys(_calculator_model())
		if configuration.has("body"):
			if key=="equation" and index==0:configuration.hardware.complex=0;feature_selectors.complex.select(0)
			if key=="algebra" and index==0:configuration.hardware.graph=0;feature_selectors.graph.select(0)
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
	var custom:=configuration.has("body")
	var choices:=Config.Keypad.available() if custom else Config.Keypad.OPTIONAL
	for key in choices:
		if not custom and key not in Config.Keypad.keys(_calculator_model()):continue
		var button:=Button.new()
		button.text="%s  +$2"%key if custom else key
		button.toggle_mode=true
		button.button_pressed=key in configuration.keypad
		button.disabled=custom and not button.button_pressed and configuration.keypad.size()>=36
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
	var cost:=int(quoted.get("price",base_price))
	if not editing_key.is_empty():cost=maxi(0,cost-int(Config.quote(kind,base_price,original_configuration).price))
	price.text="$%d"%cost if cost>0 or editing_key.is_empty() else "No charge"
	if configuration.has("body"):
		feature_selectors.complex.disabled=configuration.hardware.equation==0
		feature_selectors.graph.disabled=configuration.hardware.algebra==0
	if screen_demo!=null:
		screen_demo.set_shader_parameter("resolution",float(Config.value(kind,configuration,"hardware","display",1.0)))
		screen_demo.set_shader_parameter("grain",Config.screen_noise(kind,configuration))
		screen_demo.set_shader_parameter("fps",float(Config.phone_or_laptop_fps(kind,configuration)))
	if kind==Config.PHONE:Handset.apply_appearance(phone,Config.phone_appearance({"configuration":configuration}))
	elif kind==Config.NOTEBOOK:preload("res://scripts/campus/items/notebook_model.gd").update(rendered_product,configuration,not notebook_cover_view)
	elif kind==Config.BACKPACK:
		var model: String=Config.value(kind,configuration,"hardware","size","backpack_small")
		preload("res://scripts/campus/items/backpack_model.gd").update(rendered_product,model,configuration)
	elif kind in [Config.CALCULATOR,Config.KIT,Config.POWER_BANK]:
		for child in rendered_product.get_children():
			rendered_product.remove_child(child)
			child.queue_free()
		preview_builder.call(kind,rendered_product,configuration)
	else:Finish.apply_finish(rendered_product,kind,configuration)
	_refresh_preview()

func _show_stage(index: int) -> void:
	stage=clampi(index,0 if editing_key.is_empty() else 1,2)
	notebook_cover_view=false
	headings.text=["Specifications","Appearance","Review purchase"][stage]
	ok_button_text=["Continue to appearance","Review purchase","Buy equipment"][stage]
	back.visible=stage>(0 if editing_key.is_empty() else 1)
	if not editing_key.is_empty() and stage==2:
		headings.text="Review decoration"
		ok_button_text="Save decoration"
	for i in sections.size():sections[i].visible=i==stage
	decoration_editor.visible=stage==1
	if is_instance_valid(keypad_panel):keypad_panel.visible=stage==0
	review.visible=stage==2
	if is_instance_valid(fields_scroll):fields_scroll.set_deferred("scroll_vertical",0)
	if kind==Config.NOTEBOOK and is_instance_valid(rendered_product):
		preload("res://scripts/campus/items/notebook_model.gd").update(rendered_product,configuration,not notebook_cover_view)
		_refresh_preview()
	if stage==2:
		var lines:=PackedStringArray()
		for group in ["hardware","appearance"] if editing_key.is_empty() else ["appearance"]:
			for key in Config.definitions(kind,int(configuration.version))[group]:
				var option: Dictionary=Config.definitions(kind,int(configuration.version))[group][key]
				lines.append("%s  ·  %s"%[option.label,option.labels[configuration[group][key]]])
		if kind==Config.CALCULATOR:lines.append("Keypad  ·  %d keys"%configuration.keypad.size())
		if configuration.has("decoration"):lines.append("Decoration layers  ·  %d"%configuration.decoration.size())
		review.text="\n".join(lines)

func _advance() -> void:
	if stage<2:
		_show_stage(stage+1)
		return
	get_ok_button().disabled=true
	if not editing_key.is_empty():
		var result: String=profile.decorate_equipment(kind,editing_key,configuration,original_configuration)
		hide()
		queue_free()
		bought.call(result)
		return
	var message: String
	match kind:
		Config.PHONE:message=profile.buy_smartphone("basic",6,"",configuration)
		Config.LAPTOP:message=profile.buy_portable_laptop("basic",6,"",configuration)
		Config.NOTEBOOK:message=profile.buy_study_tool(Config.NOTEBOOK,6,configuration)
		Config.BACKPACK:message=profile.buy_study_tool(Config.BACKPACK,6,configuration)
		Config.CALCULATOR:message=profile.buy_study_tool(Config.CALCULATOR,6,configuration)
		Config.POWER_BANK:message=profile.buy_study_tool(Config.POWER_BANK,6,configuration)
		Config.KIT:
			var size: String=Config.value(kind,configuration,"hardware","size","compact")
			message=profile.create_kit(size,6,configuration)
		Config.USB:
			var capacity:=int(Config.value(Config.USB,configuration,"hardware","storage",8))
			message=profile.buy_usb(capacity,6,"",configuration)
	hide()
	queue_free()
	bought.call(message)
