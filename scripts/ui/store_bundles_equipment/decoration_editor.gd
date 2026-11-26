extends VBoxContainer

const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Document = preload("res://scripts/campus/items/decoration_document.gd")
const Canvas = preload("res://scripts/ui/store_bundles_equipment/surface_canvas.gd")
const USB = preload("res://scripts/campus/computers/usb_archive.gd")
const Materials = preload("res://scripts/campus/items/material_segments.gd")
const Photos = preload("res://scripts/campus/phones/photo_library.gd")
signal design_changed(design: Array, materials: Dictionary)
signal focus_surface
signal selection_changed

var profile: RefCounted
var product_kind: String
var design: Array=[]
var active := -1
var undo: Array=[]
var redo: Array=[]
var list: VBoxContainer
var materials: Dictionary = {}
var segment_reader: Callable
var segment: String
var layer_scroll: ScrollContainer
var thumbnail_cache := {}
var tracking_material := false
var material_before: Dictionary
var details: VBoxContainer
var notice: Label
var canvas: Control
var brush_tool: OptionButton
var brush_size: SpinBox
var brush_data: Dictionary={"ink":Color("e8fbec"),"size":4,"hardness":.8,"spacing":.45,"opacity":1.0}
var paint_mode:=0
var undo_button: Button
var redo_button: Button

func build(owner: RefCounted, kind: String) -> void:
	profile=owner
	product_kind=kind
	segment=Materials.labels(kind).keys()[0]
	add_theme_constant_override("separation", 8)
	var layers:=_panel(self,"Decoration layers")
	var additions:=HFlowContainer.new()
	layers.add_child(additions)
	for entry in [["Drawing Layer","paint"],["Image Layer","image"]]:
		var add:=UI.action(entry[0],"plus",_add.bind(entry[1],""))
		_compact(add)
		additions.add_child(add)
	layer_scroll=ScrollContainer.new()
	layer_scroll.custom_minimum_size.y=108
	layer_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_RESERVE
	layer_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	layers.add_child(layer_scroll)
	list=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	layer_scroll.add_child(list)
	var tools:=HFlowContainer.new()
	layers.add_child(tools)
	undo_button=UI.action("Undo","",_undo)
	redo_button=UI.action("Redo","",_redo)
	_compact(undo_button)
	_compact(redo_button)
	tools.add_child(undo_button)
	tools.add_child(redo_button)
	var design_menu:=MenuButton.new()
	design_menu.text="Design"
	tools.add_child(design_menu)
	var menu:=design_menu.get_popup()
	for label in ["Save design","Load design","Reset design"]: menu.add_item(label)
	menu.id_pressed.connect(func(id: int):
		match id:
			0: _save()
			1: _confirm("Replace this design with the saved design?",_load)
			2: _confirm("Reset all layers and material changes?",_reset)
	)
	details=VBoxContainer.new()
	add_child(details)
	notice=UI.text("","MutedLabel")
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(notice)
	_refresh()

func _panel(parent: Node,title: String) -> VBoxContainer:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UI.T.surface(Color("142e3d"),Color("365564"),8))
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",6)
	panel.add_child(body)
	body.add_child(UI.text(title,"SubtitleLabel"))
	return body

func restore(layers: Array, segments: Dictionary = {}) -> void:
	design=layers.duplicate(true)
	materials=segments.duplicate(true)
	active=-1
	_refresh()

func _snapshot() -> Dictionary:
	return {"layers":design.duplicate(true),"materials":materials.duplicate(true)}

func _push_history(previous: Dictionary) -> void:
	undo.append(previous)
	if undo.size()>24: undo.pop_front()
	redo.clear()

func _commit(next: Array, rebuild := true, next_materials: Variant = null) -> bool:
	var cleaned: Variant=Document.clean(next)
	var normalized: Variant=Materials.clean(product_kind,materials if next_materials==null else next_materials)
	if cleaned==null or normalized==null:
		notice.text="This design exceeds the layer or image size limit."
		return false
	if cleaned==design and normalized==materials: return true
	if not tracking_material: _push_history(_snapshot())
	design=cleaned
	materials=normalized
	notice.text=""
	_emit(rebuild)
	return true

func _emit(rebuild: bool) -> void:
	if rebuild:
		_refresh()
	else:
		undo_button.disabled=undo.is_empty()
		redo_button.disabled=redo.is_empty()
	design_changed.emit(design.duplicate(true), materials.duplicate(true))

func _refresh() -> void:
	_refresh_list()
	_show_details()

func _refresh_list() -> void:
	for node in list.get_children():
		list.remove_child(node)
		node.queue_free()
	active=clampi(active,-1,design.size()-1)
	_add_row(-1)
	for index in range(design.size()-1,-1,-1):
		_add_row(index)
	undo_button.disabled=undo.is_empty()
	redo_button.disabled=redo.is_empty()

func _add_row(index: int) -> void:
	var row:=HBoxContainer.new()
	list.add_child(row)
	var layer: Dictionary=design[index] if index>=0 else {}
	if index>=0:
		var handle:=Label.new()
		handle.text="⠿"
		handle.tooltip_text="Drag to reorder the layer"
		handle.mouse_filter=Control.MOUSE_FILTER_STOP
		handle.set_drag_forwarding(func(_position: Vector2): return index if not layer.locked else null,
			func(_position: Vector2,data: Variant): return data is int and data>=0 and data<design.size() and not design[data].locked,
			func(_position: Vector2,data: Variant): _move_layer(data,index))
		row.add_child(handle)
	var select:=UI.action(str(layer.get("name","Base Material")),"",_select_layer.bind(index))
	_compact(select)
	select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	select.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	select.toggle_mode=true
	select.set_pressed_no_signal(index==active)
	select.add_theme_stylebox_override("pressed",UI.T.surface(Color("1b4959"),UI.T.ACCENT,4))
	select.alignment=HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(select)
	if index<0: return
	select.icon=_thumbnail(layer)
	select.expand_icon=true
	select.add_theme_constant_override("icon_max_width",24)
	var visibility:=Button.new()
	visibility.pressed.connect(_set_flag.bind(index,"visible",not layer.visible))
	visibility.text="Hide" if layer.visible else "Show"
	visibility.tooltip_text="Toggle layer visibility"
	row.add_child(visibility)
	var more:=MenuButton.new()
	more.text="⋯"
	more.tooltip_text="Layer options"
	row.add_child(more)
	var popup:=more.get_popup()
	for label in ["Duplicate","Unlock" if layer.locked else "Lock","Move up","Move down"]: popup.add_item(label)
	popup.set_item_disabled(2,layer.locked or index==design.size()-1)
	popup.set_item_disabled(3,layer.locked or index==0)
	popup.id_pressed.connect(func(id: int):
		active=index
		match id:
			0: _duplicate()
			1: _set_flag(index,"locked",not layer.locked)
			2: _move_layer(index,index+1)
			3: _move_layer(index,index-1)
	)
	var remove:=Button.new()
	remove.icon=UI.icon("trash")
	remove.expand_icon=true
	remove.add_theme_constant_override("icon_max_width",18)
	remove.custom_minimum_size.x=32
	remove.pressed.connect(func():active=index;_delete())
	remove.tooltip_text="Delete layer"
	remove.disabled=layer.locked
	row.add_child(remove)

func _compact(button: Button) -> void:
	button.custom_minimum_size.y=29
	button.add_theme_font_size_override("font_size",14)
	button.add_theme_stylebox_override("normal",UI.T.surface(UI.T.RAISED,UI.T.BORDER,4))
	button.add_theme_stylebox_override("hover",UI.T.surface(Color("24495a"),UI.T.BORDER,4))
	button.add_theme_stylebox_override("pressed",UI.T.surface(Color("1b4959"),UI.T.ACCENT,4))
	button.add_theme_stylebox_override("disabled",UI.T.surface(UI.T.SURFACE,Color("365564"),4))

func _thumbnail(layer: Dictionary) -> Texture2D:
	if layer.kind not in ["paint","image"]:return null
	var data: String=layer.data
	var painted: Dictionary=layer.get("mesh_paint",{})
	if data.is_empty() and not painted.is_empty():data=painted.values()[0]
	if data.is_empty():return null
	var key: String=data.sha256_text()
	if not thumbnail_cache.has(key):
		var image:=Document.decode(data)
		if image==null: return null
		image.resize(24,24,Image.INTERPOLATE_BILINEAR)
		if thumbnail_cache.size()>=16: thumbnail_cache.erase(thumbnail_cache.keys()[0])
		thumbnail_cache[key]=ImageTexture.create_from_image(image)
	return thumbnail_cache[key]

func _select_layer(index: int) -> void:
	if active==index:
		_refresh_list()
		return
	active=index
	_refresh()
	if index>=0: focus_surface.emit()

func _show_details() -> void:
	selection_changed.emit()
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	canvas=null
	var layer: Dictionary=design[active] if active>=0 else {}
	var type: String={"paint":"Drawing Layer","image":"Image Layer","text":"Text Layer","shape":"Shape Layer"}.get(layer.get("kind",""),"Base Material")
	var heading:=HBoxContainer.new()
	heading.add_child(UI.text("Editing · "+type,"MutedLabel"))
	details.add_child(heading)
	if active>=0:
		var name_field:=LineEdit.new()
		name_field.text=layer.name
		name_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		name_field.max_length=28
		name_field.editable=not layer.locked
		var rename:=func():
			if not name_field.text.strip_edges().is_empty():
				_set_layer("name",name_field.text.strip_edges(),false)
				_refresh_list()
		name_field.text_submitted.connect(func(_value: String):rename.call())
		name_field.focus_exited.connect(func():
			if name_field.is_inside_tree() and is_ancestor_of(name_field):rename.call())
		heading.add_child(name_field)
	var context:=HBoxContainer.new()
	context.add_theme_constant_override("separation",8)
	details.add_child(context)
	if active<0:
		var selector_box:=_panel(context,"Material segments")
		var segment_select:=OptionButton.new()
		for key in Materials.labels(product_kind):
			segment_select.add_item(Materials.labels(product_kind)[key])
			segment_select.set_item_metadata(segment_select.item_count-1,key)
			if key==segment: segment_select.select(segment_select.item_count-1)
		selector_box.add_child(segment_select)
		segment_select.item_selected.connect(func(i: int): segment=segment_select.get_item_metadata(i);_show_details())
		var base:=_panel(context,"Finish")
		var reset:=UI.action("Reset selected material","",func():
			var next:=materials.duplicate(true)
			next.erase(segment)
			_commit(design,true,next))
		reset.disabled=not materials.has(segment)
		base.add_child(reset)
	elif layer.kind=="image":
		var source:=_panel(context,"Image source")
		var photo:=TextureRect.new()
		photo.texture=_thumbnail(layer)
		photo.custom_minimum_size=Vector2(52,52)
		photo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if photo.texture!=null:source.add_child(photo)
		else:photo.free()
		for action in [["Import from Computer",_pick_image],["Inventory Images",_pick_inventory]]:
			var button:=UI.action(action[0],"folder",action[1])
			button.disabled=layer.locked
			source.add_child(button)
		source.add_child(UI.text("Click the model to place the image. Drag its handles to size or rotate it.","MutedLabel"))
		var transform:=_panel(context,"Transform")
		_transform(transform,layer)
	elif layer.kind=="paint":
		var tools:=_panel(context,"Painting tools")
		var brush:=_panel(context,"Brush settings")
		_add_canvas(tools,brush,layer)
	else:
		var legacy:=_panel(context,"Saved decoration")
		legacy.add_child(UI.text(str(layer.data)))
		_transform(_panel(context,"Transform"),layer)
	var properties:=_panel(details,"Material properties" if active<0 else "Layer material")
	_add_properties(properties,layer)

func _add_canvas(tools: VBoxContainer,settings: VBoxContainer,layer: Dictionary) -> void:
	brush_tool=OptionButton.new()
	for label in ["Select","Draw","Eraser"]:brush_tool.add_item(label)
	brush_tool.select(paint_mode)
	brush_tool.disabled=layer.locked
	brush_tool.item_selected.connect(func(index: int):paint_mode=index;selection_changed.emit())
	tools.add_child(brush_tool)
	tools.add_child(UI.text("Draw on the model. Right-drag erases. Scroll changes brush size. Hold Shift to move the camera.","MutedLabel"))
	var clear:=UI.action("Clear drawing","",func():
		_confirm("Clear the drawing on this layer?",func():
			var empty: Dictionary=design[active].duplicate(true)
			empty.data=""
			empty.erase("mesh_paint")
			replace_active(empty)))
	clear.disabled=layer.locked
	tools.add_child(clear)
	# Keep the original canvas available for drawings made with the old editor.
	if not layer.data.is_empty():
		canvas=Canvas.new()
		canvas.custom_minimum_size.y=104
		canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE if layer.locked else Control.MOUSE_FILTER_STOP
		tools.add_child(UI.text("Original drawing","MutedLabel"))
		tools.add_child(canvas)
		canvas.load_pixels(layer.data)
		canvas.finished.connect(func(image: Image):
			_set_layer("data",Document.encode(image),false)
			_refresh_list())
	var grid:=GridContainer.new()
	grid.columns=2
	settings.add_child(grid)
	grid.add_child(UI.text("Size"))
	brush_size=_number(1,14,1,brush_data.size)
	brush_size.editable=not layer.locked
	grid.add_child(brush_size)
	brush_size.value_changed.connect(func(value: float):brush_data.size=value;selection_changed.emit())
	for field in [["Hardness","hardness",0.],["Spacing","spacing",.1],["Opacity","opacity",0.]]:
		var key: String=field[1]
		_scalar(grid,field[0],field[2],1.,.05,brush_data[key],layer.locked,func(value: float):brush_data[key]=value)
	_color(grid,"Color",brush_data.ink.to_html(false),layer.locked,func(value: String):brush_data.ink=Color(value),false)

func brush_settings() -> Dictionary:
	var values:=brush_data.duplicate()
	values.ink.a=values.opacity
	values.erase=paint_mode==2
	return values

func replace_active(layer: Dictionary, rebuild := true) -> bool:
	if active<0 or design[active].locked:return false
	var next:=design.duplicate(true)
	next[active]=layer
	var committed:=_commit(next,rebuild)
	if committed and not rebuild:_refresh_list()
	return committed

func _transform(parent: VBoxContainer,layer: Dictionary) -> void:
	var grid:=GridContainer.new()
	grid.columns=2
	parent.add_child(grid)
	var fields:=[["Horizontal","x",0,1,.01],["Vertical","y",0,1,.01],["Scale","size",.1,1,.01],["Rotation","angle",-180,180,1]]
	if layer.kind=="image":
		var aspect:=CheckBox.new()
		aspect.text="Lock aspect ratio"
		aspect.button_pressed=layer.get("lock_aspect",true)
		aspect.disabled=layer.locked
		aspect.toggled.connect(func(value: bool):_set_layer("lock_aspect",value,true))
		parent.add_child(aspect)
		if not aspect.button_pressed:
			fields.append_array([["Width","width",.25,4,.01],["Height","height",.25,4,.01]])
		var crop:=Button.new()
		crop.text="Crop image"
		crop.toggle_mode=true
		parent.add_child(crop)
		var crop_grid:=GridContainer.new()
		crop_grid.columns=2
		parent.add_child(crop_grid)
		crop_grid.hide()
		crop.toggled.connect(func(expanded: bool):crop_grid.visible=expanded)
		for edge in ["left","right","top","bottom"]:
			var crop_key: String="crop_"+edge
			_scalar(crop_grid,edge.capitalize(),0,.4,.02,layer[crop_key],layer.locked,_set_value.bind(crop_key))
	for entry in fields:
		var key: String=entry[1]
		_scalar(grid,entry[0],entry[2],entry[3],entry[4],layer.get(key,1.0),layer.locked,_set_value.bind(key))

func _add_properties(parent: VBoxContainer,layer: Dictionary) -> void:
	var base:=active<0
	var values: Dictionary=materials.get(segment,segment_reader.call(segment) if segment_reader.is_valid() else Materials.defaults()) if base else layer
	var lock: bool=layer.get("locked",false)
	var grid:=GridContainer.new()
	grid.columns=2
	parent.add_child(grid)
	_color(grid,"Base color",values.color,lock,_change_property.bind("color",base))
	_scalar(grid,"Roughness",0,1,.01,values.roughness,lock,_change_property.bind("roughness",base))
	_scalar(grid,"Metallic",0,1,.01,values.metallic,lock,_change_property.bind("metallic",base))
	_color(grid,"Emission color",values.emission if base else values.glow_color,lock,_change_property.bind("emission" if base else "glow_color",base))
	_scalar(grid,"Emission strength",0,4 if base else 2,.01,values.strength if base else values.glow,lock,_change_property.bind("strength" if base else "glow",base))
	if not base: _scalar(grid,"Layer opacity",0,1,.05,layer.opacity,lock,_set_value.bind("opacity"))

func _scalar(grid: GridContainer,label: String,low: float,high: float,step: float,value: float,locked: bool,change: Callable) -> void:
	grid.add_child(UI.text(label))
	var row:=HBoxContainer.new()
	row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_child(row)
	var slider:=HSlider.new()
	slider.min_value=low
	slider.max_value=high
	slider.step=step
	slider.value=value
	slider.editable=not locked
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var spin:=_number(low,high,step,value)
	spin.custom_minimum_size.x=72
	spin.editable=not locked
	row.add_child(spin)
	slider.drag_started.connect(_begin_edit)
	slider.drag_ended.connect(func(_changed: bool): _end_edit())
	slider.value_changed.connect(func(amount: float): spin.set_value_no_signal(amount);change.call(amount))
	spin.value_changed.connect(func(amount: float): slider.set_value_no_signal(amount);change.call(amount))

func _color(grid: GridContainer,label: String,value: String,locked: bool,change: Callable,track_history := true) -> void:
	grid.add_child(UI.text(label))
	var row:=HBoxContainer.new()
	grid.add_child(row)
	var picker:=ColorPickerButton.new()
	picker.color=Color(value)
	picker.edit_alpha=false
	picker.custom_minimum_size.x=38
	picker.disabled=locked
	row.add_child(picker)
	var hex:=LineEdit.new()
	hex.text="#"+value
	hex.max_length=7
	hex.editable=not locked
	hex.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(hex)
	if track_history:
		picker.pressed.connect(_begin_edit)
		picker.popup_closed.connect(_end_edit)
	picker.color_changed.connect(func(color: Color): hex.text="#"+color.to_html(false);change.call(color.to_html(false)))
	hex.text_submitted.connect(func(raw: String):
		var code:=raw.strip_edges().trim_prefix("#")
		if code.length()==6 and Color.html_is_valid(code):
			picker.color=Color(code)
			change.call(code.to_lower())
		hex.text="#"+picker.color.to_html(false))

func _begin_edit() -> void:
	if tracking_material: return
	material_before=_snapshot()
	tracking_material=true

func _end_edit() -> void:
	if not tracking_material: return
	tracking_material=false
	if _snapshot()!=material_before:
		_push_history(material_before)
		undo_button.disabled=false
		redo_button.disabled=true
	material_before={}

func _change_property(value: Variant,field: String,base: bool) -> void:
	if not base:
		_set_layer(field,value,false)
		return
	var next:=materials.duplicate(true)
	var seeded: Dictionary=next.get(segment,segment_reader.call(segment) if segment_reader.is_valid() else Materials.defaults())
	next[segment]=seeded
	seeded[field]=value
	_commit(design,false,next)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ESCAPE and paint_mode!=0 and active>=0 and design[active].kind=="paint":
		paint_mode=0
		brush_tool.select(0)
		selection_changed.emit()
		get_viewport().set_input_as_handled()
		return
	if not event.ctrl_pressed or get_viewport().gui_get_focus_owner() is LineEdit:return
	if event.keycode==KEY_Z and not event.shift_pressed:_undo()
	elif event.keycode==KEY_Y or (event.keycode==KEY_Z and event.shift_pressed):_redo()
	else:return
	get_viewport().set_input_as_handled()

func _number(low: float,high: float,step: float,value: float) -> SpinBox:
	var spin:=SpinBox.new()
	spin.min_value=low
	spin.max_value=high
	spin.step=step
	spin.value=value
	spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return spin

func _set_value(value: float,key: String) -> void:
	_set_layer(key,value,false)

func _set_flag(index: int,key: String,value: bool) -> void:
	var next:=design.duplicate(true)
	next[index][key]=value
	_commit(next)

func _set_layer(key: String,value: Variant,rebuild: bool) -> void:
	if active<0 or (design[active].locked and key not in ["locked","visible"]):return
	var next:=design.duplicate(true)
	next[active][key]=value
	_commit(next,rebuild)

func _add(kind: String,data: String) -> void:
	if design.size()>=Document.LAYERS:
		notice.text="A design can have up to %d layers."%Document.LAYERS
		return
	var next:=design.duplicate(true)
	var layer:=Document.layer(kind)
	layer.name="Drawing Layer" if kind=="paint" else "Image Layer"
	layer.data=data
	next.append(layer)
	active=next.size()-1
	if _commit(next):focus_surface.emit()

func _move_layer(source: int,destination: int) -> void:
	if source==destination or design[source].locked:return
	var next:=design.duplicate(true)
	var moving: Dictionary=next.pop_at(source)
	next.insert(destination,moving)
	active=destination
	_commit(next)

func _duplicate() -> void:
	if active<0 or design.size()>=Document.LAYERS:return
	var next:=design.duplicate(true)
	var copy: Dictionary=next[active].duplicate(true)
	copy.name=copy.name.left(23)+" copy"
	copy.locked=false
	next.insert(active+1,copy)
	active+=1
	_commit(next)

func _delete() -> void:
	if active<0 or design[active].locked:return
	var next:=design.duplicate(true)
	next.remove_at(active)
	_commit(next)

func _confirm(prompt: String,action: Callable) -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.dialog_text=prompt
	add_child(dialog)
	dialog.confirmed.connect(func():action.call();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _reset() -> void:
	active=-1
	_commit([],true,{})

func _undo() -> void:
	_end_edit()
	if undo.is_empty():return
	redo.append(_snapshot())
	_restore_history(undo.pop_back())

func _redo() -> void:
	_end_edit()
	if redo.is_empty():return
	undo.append(_snapshot())
	_restore_history(redo.pop_back())

func _restore_history(previous: Dictionary) -> void:
	design=previous.layers
	materials=previous.materials
	_emit(true)

func _save() -> void:
	var path: String="user://equipment-design-"+product_kind+".json"
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:
		notice.text="Could not save this design."
		return
	file.store_string(JSON.stringify(_snapshot()))
	file.close()
	notice.text="Design saved for this product." if DirAccess.rename_absolute(path+".tmp",path)==OK else "Could not save this design."

func _load() -> void:
	var file:=FileAccess.open("user://equipment-design-"+product_kind+".json",FileAccess.READ)
	if file==null or file.get_length()>Document.MAX_DOCUMENT+4096:
		notice.text="There is no loadable saved design for this product."
		return
	var data: Variant=JSON.parse_string(file.get_as_text())
	if data is Array:
		_commit(data,true,{})
	elif data is Dictionary and data.get("layers") is Array and data.get("materials") is Dictionary:
		_commit(data.layers,true,data.materials)
	else:
		notice.text="Could not load this design."

func _pick_image() -> void:
	var picker:=FileDialog.new()
	picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	picker.access=FileDialog.ACCESS_FILESYSTEM
	picker.use_native_dialog=true
	picker.filters=PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	add_child(picker)
	picker.file_selected.connect(func(path: String):
		var file:=FileAccess.open(path,FileAccess.READ)
		if file!=null and file.get_length()<=Document.MAX_IMPORT:_import(file.get_buffer(file.get_length()),path)
		else:notice.text="Choose an image file under 6 MB."
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered(Vector2i(640,410))

func _import(bytes: PackedByteArray,path: String) -> void:
	var image:=Document.import_image(bytes,path.get_extension().to_lower())
	var data:=Document.encode(image)
	if data.is_empty():
		notice.text="Use a readable PNG, JPEG or WebP image up to 3072 pixels per side."
		return
	_set_layer("data",data,true)

func _pick_inventory() -> void:
	var dorm: Dictionary=profile.data.get("dorm",{})
	var owner: String=dorm.get("owner","")
	var picker:=AcceptDialog.new()
	picker.title="Inventory Images"
	var body:=VBoxContainer.new()
	body.custom_minimum_size=Vector2(480,300)
	picker.add_child(body)
	var filter:=OptionButton.new()
	for label in ["All devices","USB drives","Smartphones"]:filter.add_item(label)
	body.add_child(filter)
	var devices:=OptionButton.new()
	body.add_child(devices)
	var files:=ItemList.new()
	files.size_flags_vertical=Control.SIZE_EXPAND_FILL
	files.fixed_icon_size=Vector2i(32,32)
	body.add_child(files)
	var generation: Array[int]=[0]
	var refresh_files:=func(index: int):
		generation[0]+=1
		var update_id: int=generation[0]
		files.clear()
		if index<0 or index>=devices.item_count:return
		var device: Dictionary=devices.get_item_metadata(index)
		var id: String=device.id
		if device.type==1:
			var opened:=USB.load(owner,id,int(device.record.capacity_mb))
			if opened.has("error"):return
			for path in opened.drive.entries:
				var entry: Dictionary=opened.drive.entries[path]
				if path.get_extension().to_lower() in ["png","jpg","jpeg","webp"] and entry.type=="file" and entry.data.size()<=Document.MAX_IMPORT:
					files.add_item(path)
					files.set_item_metadata(files.item_count-1,{"path":path,"bytes":entry.data})
		else:
			var photos:=Photos.list(owner,id)
			for photo in photos.get("photos",[]):
				var label: String="Photo "+str(photo.id).left(8)+".jpg"
				files.add_item(label)
				files.set_item_metadata(files.item_count-1,{"phone":id,"id":photo.id})
		for row in mini(files.item_count,24):
			if row%4==0:await get_tree().process_frame
			if not is_instance_valid(files) or update_id!=generation[0]:return
			var entry: Dictionary=files.get_item_metadata(row)
			var image: Image
			if entry.has("bytes"):
				image=Document.import_image(entry.bytes,entry.path.get_extension().to_lower())
			else:
				image=Photos.load_photo(owner,entry.phone,entry.id).get("image")
			if image!=null:
				var factor:=32.0/maxi(image.get_width(),image.get_height())
				image.resize(maxi(1,roundi(image.get_width()*factor)),maxi(1,roundi(image.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
				files.set_item_icon(row,ImageTexture.create_from_image(image))
	var refresh_devices:=func(mode: int):
		devices.clear()
		for type in [1,2]:
			if mode!=0 and type!=mode:continue
			var records: Dictionary=dorm.get("usb_drives" if type==1 else "smartphones",{})
			for id in records:
				var record: Dictionary=records[id]
				if record.get("location") not in ["hotbar","cabinet","backpack"]:continue
				var label: String=record.get("name","USB drive" if type==1 else "Smartphone")
				devices.add_item(label+" · "+str(id).left(6))
				devices.set_item_metadata(devices.item_count-1,{"type":type,"id":id,"record":record})
		refresh_files.call(0)
	filter.item_selected.connect(refresh_devices)
	devices.item_selected.connect(refresh_files)
	add_child(picker)
	refresh_devices.call(0)
	picker.ok_button_text="Import selected image"
	picker.dialog_hide_on_ok=false
	var accept:=func():
		if files.get_selected_items().is_empty():return
		var entry: Dictionary=files.get_item_metadata(files.get_selected_items()[0])
		if entry.has("bytes"):_import(entry.bytes,entry.path)
		else:
			var photo:=Photos.load_photo(owner,entry.phone,entry.id)
			if photo.has("image"):_set_layer("data",Document.encode(photo.image),true)
			else:notice.text="Could not open this photo."
		picker.queue_free()
	picker.confirmed.connect(accept)
	files.item_activated.connect(func(_index: int):accept.call())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered()
