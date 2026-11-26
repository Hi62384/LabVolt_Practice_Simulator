extends ConfirmationDialog

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Handset = preload("res://scripts/campus/phones/phone_handset.gd")
const Finish = preload("res://scripts/campus/items/equipment_finish.gd")
const Display = preload("res://scripts/campus/items/device_display.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
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
const MeshArtwork = preload("res://scripts/campus/items/mesh_decoration.gd")
const MeshEditor = preload("res://scripts/ui/store_bundles_equipment/mesh_editor.gd")
var surface_editor: Control
var preview: SubViewport
var phone: Node3D
var rendered_product: Node3D
var keypad_panel: VBoxContainer
var keypad_designer: VBoxContainer
var pricing: Dictionary={}
var screen_demo: ShaderMaterial
var notebook_cover_view:=false
var feature_selectors: Dictionary={}
var fields_scroll: ScrollContainer
var preview_builder: Callable
var decoration_editor: Control
var camera: Camera3D
var preview_distance: float
var orbit_camera=preload("res://scripts/ui/store_bundles_equipment/product_orbit.gd").new()
var camera_views: OptionButton
var editing_key := ""
var original_configuration: Dictionary={}
var requested_bounds:=Vector2i.ZERO
var fit_scheduled:=false
var backlight_controls: VBoxContainer
var backlight_summary: Label
var continue_button: Button
var footer: HBoxContainer

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
	theme=Widgets.UISkin.create()
	var layout:=VBoxContainer.new()
	layout.custom_minimum_size=Vector2(620,300)
	layout.add_theme_constant_override("separation",12)
	add_child(layout)
	var header:=HBoxContainer.new()
	layout.add_child(header)
	header.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	headings=Widgets.text("","Title")
	headings.autowrap_mode=TextServer.AUTOWRAP_OFF
	headings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(headings)
	price=Widgets.text("","SubtitleLabel")
	price.size_flags_horizontal=Control.SIZE_SHRINK_END
	price.autowrap_mode=TextServer.AUTOWRAP_OFF
	price.custom_minimum_size.x=94
	price.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(price)
	var workbench:=HBoxContainer.new()
	workbench.size_flags_vertical=Control.SIZE_EXPAND_FILL
	workbench.add_theme_constant_override("separation",16)
	layout.add_child(workbench)
	_build_preview(workbench,model_builder)
	var options:=VBoxContainer.new()
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	options.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var scroll:=ScrollContainer.new()
	fields_scroll=scroll
	scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio=1.15
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x=515 if _has_keypad_designer() else 305
	workbench.add_child(scroll)
	scroll.add_child(options)
	options.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	size_changed.connect(_queue_fit)
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
	if kind==Config.LAPTOP:_build_backlighting(options)
	decoration_editor=preload("res://scripts/ui/store_bundles_equipment/decoration_editor.gd").new()
	options.add_child(decoration_editor)
	decoration_editor.segment_reader=func(segment: String):return Config.Materials.from_model(rendered_product,segment)
	decoration_editor.build(profile,kind)
	decoration_editor.restore(configuration.get("decoration",[]),configuration.get("materials",{}))
	decoration_editor.design_changed.connect(_set_decoration)
	decoration_editor.focus_surface.connect(_show_decoration_surface)
	surface_editor.editor=decoration_editor
	decoration_editor.selection_changed.connect(surface_editor.selection_changed)
	review=Widgets.text("")
	if _has_keypad_designer():
		keypad_panel=VBoxContainer.new()
		options.add_child(keypad_panel)
		for field in Config.BODY_LIMITS:
			var row:=HBoxContainer.new()
			row.add_child(Widgets.text({"width":"Body width (cm)","height":"Body height (cm)","weight":"Weight (kg)"}[field]))
			var limits: Vector2=Config.BODY_LIMITS[field]
			var scale:=100.0 if field!="weight" else 1.0
			var amount:=SpinBox.new()
			amount.min_value=limits.x*scale;amount.max_value=limits.y*scale;amount.step=.001*scale
			amount.value=configuration.body[field]*scale
			amount.value_changed.connect(func(value: float):configuration.body[field]=value/scale;_update_quote())
			row.add_child(amount)
			keypad_panel.add_child(row)
		keypad_designer=preload("res://scripts/ui/store_bundles_equipment/keypad_designer.gd").new()
		options.add_child(keypad_designer)
		keypad_designer.size_flags_vertical=Control.SIZE_EXPAND_FILL
		keypad_designer.build(configuration.keypad,configuration.hardware)
		keypad_designer.design_changed.connect(_keypad_changed)
		_build_pricing(layout)
	review.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	options.add_child(review)
	get_ok_button().hide()
	get_cancel_button().hide()
	footer=HBoxContainer.new()
	footer.add_theme_constant_override("separation",8)
	layout.add_child(footer)
	back=Widgets.action("Back","back",func():_show_stage(stage-1))
	footer.add_child(back)
	footer.add_child(Widgets.action("Cancel","close",func():canceled.emit()))
	var spacer:=Control.new()
	spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	continue_button=Widgets.action("Continue","check",func():confirmed.emit(),true)
	footer.add_child(continue_button)
	confirmed.connect(_advance)
	canceled.connect(queue_free)
	_show_stage(0 if editing_key.is_empty() else 1)
	_update_quote()

func present() -> void:
	var available: Vector2=get_parent().get_viewport().get_visible_rect().size
	requested_bounds=Vector2i(minf(1090,available.x-72),minf(710,available.y-104))
	max_size=requested_bounds
	popup_centered(requested_bounds)
	_queue_fit()

func _queue_fit() -> void:
	if fit_scheduled:return
	fit_scheduled=true
	_fit_window.call_deferred()

func _fit_window() -> void:
	fit_scheduled=false
	if not visible or requested_bounds==Vector2i.ZERO:return
	# Showing a different dialog page can trigger a native minimum-size update.
	if size!=requested_bounds:size=requested_bounds
	var bounds:=Vector2i(get_parent().get_viewport().get_visible_rect().size)
	position=position.clamp(Vector2i(12,38),(bounds-size-Vector2i(12,12)).max(Vector2i(12,38)))

func _refresh_preview() -> void:
	preview.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE if screen_demo!=null else SubViewport.UPDATE_ONCE

func _build_preview(parent: Control, model_builder: Callable) -> void:
	var frame:=PanelContainer.new()
	frame.theme_type_variation="CardPanel"
	frame.custom_minimum_size=Vector2(208 if _has_keypad_designer() else 260,200)
	frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio=.95
	parent.add_child(frame)
	var preview_controls:=VBoxContainer.new()
	frame.add_child(preview_controls)
	var display:=SubViewportContainer.new()
	display.stretch=true
	display.clip_contents=true
	display.size_flags_vertical=Control.SIZE_EXPAND_FILL
	preview_controls.add_child(display)
	preview=SubViewport.new()
	preview.own_world_3d=true
	preview.transparent_bg=true
	preview.msaa_3d=Viewport.MSAA_2X
	display.add_child(preview)
	var lighting:=WorldEnvironment.new()
	lighting.environment=Environment.new()
	lighting.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	lighting.environment.ambient_light_color=Color("f5f5f5")
	lighting.environment.ambient_light_energy=.62
	preview.add_child(lighting)
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
	camera=Camera3D.new()
	preview_distance={Config.PHONE:.36,Config.LAPTOP:.98,Config.USB:.21,Config.NOTEBOOK:.91,Config.BACKPACK:.89,Config.CALCULATOR:.36,Config.KIT:1.65,Config.POWER_BANK:.32}[kind]
	camera.fov=42
	preview.add_child(camera)
	orbit_camera.setup(camera,Vector3(.85 if kind in [Config.NOTEBOOK,Config.POWER_BANK] else .32 if kind in [Config.LAPTOP,Config.KIT] else .12,.38,0),preview_distance)
	for setup in [[Vector3(-26,-30,0),1.25],[Vector3(15,63,0),.65],[Vector3(-18,157,0),.55]]:
		var light:=DirectionalLight3D.new()
		light.rotation_degrees=setup[0]
		light.light_energy=setup[1]
		preview.add_child(light)
	var hint:=Widgets.text("Shift + drag to orbit · Shift + right-drag to pan · Shift + scroll to zoom","MutedLabel")
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size",12)
	preview_controls.add_child(hint)
	preview_controls.move_child(hint,0)
	surface_editor=MeshEditor.new()
	display.add_child(surface_editor)
	surface_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface_editor.camera=camera
	surface_editor.render_preview=_refresh_preview
	display.mouse_exited.connect(func():surface_editor.hover=Vector2.INF;surface_editor.queue_redraw())
	display.gui_input.connect(_preview_input)
	display.resized.connect(_refresh_preview)
	var viewbar:=HBoxContainer.new()
	preview_controls.add_child(viewbar)
	camera_views=OptionButton.new()
	for label in ["Orbit","Front","Back","Left","Right","Top","Bottom"]:camera_views.add_item(label)
	camera_views.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	camera_views.item_selected.connect(_camera_view)
	viewbar.add_child(camera_views)
	viewbar.add_child(Widgets.action("Reset Camera","",func():_camera_view(0);camera_views.select(0)))

func _preview_input(event: InputEvent) -> void:
	if surface_editor.input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and event.shift_pressed and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		orbit_camera.orbit(event.relative)
	elif event is InputEventMouseMotion and event.shift_pressed and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		orbit_camera.pan(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		orbit_camera.zoom(.90 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.11)
	else:return
	surface_editor.queue_redraw()
	_refresh_preview()

func _camera_view(index: int) -> void:
	orbit_camera.preset(index)
	surface_editor.queue_redraw()
	_refresh_preview()

func _set_decoration(design: Array,materials: Dictionary) -> void:
	var previous: Array=configuration.get("decoration",[])
	var layer_changed: bool=design!=previous
	var legacy_changed: bool=_legacy_layers(previous)!=_legacy_layers(design)
	if materials.is_empty():configuration.erase("materials")
	else:configuration.materials=materials
	if design.is_empty():configuration.erase("decoration")
	else:configuration.decoration=design
	_update_quote(legacy_changed)
	if not legacy_changed:
		Config.Materials.apply(rendered_product,configuration)
		if layer_changed:MeshArtwork.apply(rendered_product,design)
		_refresh_preview()

func _legacy_layers(design: Array) -> Dictionary:
	var legacy: Dictionary={}
	for index in design.size():
		var layer: Dictionary=design[index]
		if layer.has("projection") or str(layer.data).is_empty():continue
		legacy[index]=layer.duplicate()
		legacy[index].erase("mesh_paint")
	return legacy

func _show_decoration_surface() -> void:
	if kind==Config.NOTEBOOK:
		notebook_cover_view=true
		preload("res://scripts/campus/items/notebook_model.gd").update(rendered_product,configuration,false)
	surface_editor.refresh_geometry(rendered_product)
	_refresh_preview()

func _has_keypad_designer() -> bool:
	return kind==Config.CALCULATOR and editing_key.is_empty()

func _select(index: int, group: String, key: String) -> void:
	configuration[group][key]=index
	if _has_keypad_designer() and group=="hardware":
		if key=="equation" and index==0:configuration.hardware.complex=0
		if key=="algebra" and index==0:configuration.hardware.graph=0
		keypad_designer.change_hardware(configuration.hardware)
	_update_quote()

func _keypad_changed(slots: Array, hardware: Dictionary) -> void:
	configuration.keypad=slots
	configuration.hardware=hardware
	for key in hardware:feature_selectors[key].select(int(hardware[key]))
	_update_quote()

func _build_pricing(layout: VBoxContainer) -> void:
	var bar:=PanelContainer.new()
	bar.add_theme_stylebox_override("panel",Tokens.surface(Color("142e40"),Color("3b6378"),8))
	layout.add_child(bar)
	var values:=GridContainer.new()
	values.columns=5
	bar.add_child(values)
	for key in ["Base","Hardware","Keypad","Appearance","Total"]:
		var field:=VBoxContainer.new()
		field.add_theme_constant_override("separation",2)
		field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		values.add_child(field)
		var caption:=Widgets.text(key,"MutedLabel")
		caption.add_theme_font_size_override("font_size",12)
		field.add_child(caption)
		var amount:=Widgets.text("$0","SubtitleLabel")
		if key=="Total":amount.add_theme_color_override("font_color",Tokens.ACCENT)
		field.add_child(amount)
		pricing[key]=amount

func _build_backlighting(options: VBoxContainer) -> void:
	backlight_controls=VBoxContainer.new()
	options.add_child(backlight_controls)
	backlight_controls.add_child(Widgets.text("Keyboard backlighting","SubtitleLabel"))
	backlight_controls.add_child(Widgets.text("Select colors in the order they should cycle.","MutedLabel"))
	var swatches:=HFlowContainer.new()
	backlight_controls.add_child(swatches)
	for index in Config.BACKLIGHT_NAMES.size():
		var button:=CheckButton.new()
		button.text="%s  +$%d"%[Config.BACKLIGHT_NAMES[index],Config.BACKLIGHT_PRICE]
		button.add_theme_color_override("font_color",Color(Config.BACKLIGHT_COLORS[index]))
		button.button_pressed=index in configuration.get("backlight",[])
		button.toggled.connect(_change_backlight.bind(index))
		swatches.add_child(button)
	backlight_summary=Widgets.text("")
	backlight_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	backlight_controls.add_child(backlight_summary)
	_update_backlight_summary()

func _change_backlight(selected_color: bool, index: int) -> void:
	var colors: Array=configuration.get_or_add("backlight",[])
	if selected_color:colors.append(index)
	else:colors.erase(index)
	_update_backlight_summary()
	_update_quote()

func _update_backlight_summary() -> void:
	backlight_summary.text=_backlight_description()

func _backlight_description() -> String:
	var names:=PackedStringArray()
	for index in configuration.get("backlight",[]):names.append(Config.BACKLIGHT_NAMES[index])
	return "Off" if names.is_empty() else " → ".join(names)

func _quote() -> Dictionary:
	return Config.quote(kind,base_price,configuration)

func _update_quote(rebuild_model := true) -> void:
	var quoted:=_quote()
	if not pricing.is_empty():
		pricing.Base.text="$%d"%base_price
		pricing.Hardware.text="$%d"%int(quoted.get("hardware_cost",0))
		pricing.Keypad.text="$%d"%int(quoted.get("keypad_cost",0))
		pricing.Appearance.text="$%d"%int(quoted.get("appearance_cost",0))
		pricing.Total.text="$%d"%int(quoted.get("price",base_price))
	var cost:=int(quoted.get("price",base_price))
	if not editing_key.is_empty():cost=maxi(0,cost-int(Config.quote(kind,base_price,original_configuration).price))
	price.text="$%d"%cost if cost>0 or editing_key.is_empty() else "No charge"
	if _has_keypad_designer():
		feature_selectors.complex.disabled=configuration.hardware.equation==0
		feature_selectors.graph.disabled=configuration.hardware.algebra==0
	if not rebuild_model:return
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
	if decoration_editor.visible:surface_editor.refresh_geometry(rendered_product)
	_refresh_preview()

func _show_stage(index: int) -> void:
	var custom:=_has_keypad_designer()
	var appearance_stage:=2 if custom else 1
	var review_stage:=appearance_stage+1
	stage=clampi(index,0 if editing_key.is_empty() else 1,review_stage)
	notebook_cover_view=false
	var labels:=["Specifications","Keypad designer","Appearance","Review purchase"] if custom else ["Specifications","Appearance","Review purchase"]
	var actions:=["Continue to keypad","Continue to appearance","Review purchase","Buy equipment"] if custom else ["Continue to appearance","Review purchase","Buy equipment"]
	headings.text=labels[stage]
	price.visible=not _has_keypad_designer() or stage==appearance_stage
	ok_button_text=actions[stage]
	back.visible=stage>(0 if editing_key.is_empty() else 1)
	if not editing_key.is_empty() and stage==review_stage:
		headings.text="Review decoration"
		ok_button_text="Save decoration"
	continue_button.text=ok_button_text
	sections[0].visible=stage==0
	sections[1].hide()
	decoration_editor.visible=stage==appearance_stage
	if stage==appearance_stage:surface_editor.refresh_geometry(rendered_product)
	if is_instance_valid(backlight_controls):backlight_controls.visible=stage==appearance_stage
	if is_instance_valid(keypad_panel):keypad_panel.visible=stage==0
	if is_instance_valid(keypad_designer):keypad_designer.visible=stage==1
	review.visible=stage==review_stage
	if is_instance_valid(fields_scroll):fields_scroll.set_deferred("scroll_vertical",0)
	_queue_fit()
	if kind==Config.NOTEBOOK and is_instance_valid(rendered_product):
		preload("res://scripts/campus/items/notebook_model.gd").update(rendered_product,configuration,not notebook_cover_view)
		_refresh_preview()
	if stage==review_stage:
		var lines:=PackedStringArray()
		for group in ["hardware","appearance"] if editing_key.is_empty() else ["appearance"]:
			for key in Config.definitions(kind,int(configuration.version))[group]:
				var option: Dictionary=Config.definitions(kind,int(configuration.version))[group][key]
				lines.append("%s  ·  %s"%[option.label,option.labels[configuration[group][key]]])
		if kind==Config.LAPTOP:lines.append("Keyboard backlighting  ·  "+_backlight_description())
		if kind==Config.CALCULATOR:
			lines.append("Keypad  ·  %d installed"%[configuration.keypad.size()-configuration.keypad.count("")])
			var omitted:=PackedStringArray()
			for key in Config.Keypad.REQUIRED:
				if key not in configuration.keypad:omitted.append(key)
			if not omitted.is_empty():lines.append("Missing common keys  ·  "+", ".join(omitted))
		if configuration.has("decoration"):lines.append("Decoration layers  ·  %d"%configuration.decoration.size())
		review.text="\n".join(lines)

func _advance() -> void:
	if stage<(3 if _has_keypad_designer() else 2):
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
