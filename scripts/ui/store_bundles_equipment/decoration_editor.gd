extends VBoxContainer

const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Document = preload("res://scripts/campus/items/decoration_document.gd")
const Canvas = preload("res://scripts/ui/store_bundles_equipment/surface_canvas.gd")
const USB = preload("res://scripts/campus/computers/usb_archive.gd")
signal design_changed(design: Array)
signal focus_surface

var profile: RefCounted
var product_kind: String
var design: Array=[]
var active := -1
var undo: Array=[]
var redo: Array=[]
var list: ItemList
var details: VBoxContainer
var notice: Label
var canvas: Control
var undo_button: Button
var redo_button: Button

func build(owner: RefCounted, kind: String) -> void:
	profile=owner
	product_kind=kind
	var head:=HBoxContainer.new()
	add_child(head)
	head.add_child(UI.text("Decoration layers","SubtitleLabel"))
	head.add_child(UI.action("Show surface","",func():focus_surface.emit()))
	var additions:=HFlowContainer.new()
	add_child(additions)
	for item in [["Paint","paint"],["Text","text"],["Shape","shape"]]:
		additions.add_child(UI.action(item[0],"plus",_add.bind(item[1],"")))
	additions.add_child(UI.action("Import image","folder",_pick_image))
	additions.add_child(UI.action("USB image","",_pick_usb))
	list=ItemList.new()
	list.custom_minimum_size.y=99
	add_child(list)
	list.item_selected.connect(func(index: int):active=index;_show_details())
	var controls:=HFlowContainer.new()
	add_child(controls)
	controls.add_child(UI.action("Move up","",_move.bind(-1)))
	controls.add_child(UI.action("Move down","",_move.bind(1)))
	controls.add_child(UI.action("Duplicate","",_duplicate))
	controls.add_child(UI.action("Delete","",_delete))
	controls.add_child(UI.action("Merge paint","",_merge_paint))
	undo_button=UI.action("Undo","",_undo)
	redo_button=UI.action("Redo","",_redo)
	controls.add_child(undo_button)
	controls.add_child(redo_button)
	details=VBoxContainer.new()
	add_child(details)
	var presets:=HFlowContainer.new()
	add_child(presets)
	presets.add_child(UI.action("Save design","",_save))
	presets.add_child(UI.action("Load design","",_load))
	presets.add_child(UI.action("Reset design","",_reset))
	notice=UI.text("","MutedLabel")
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(notice)
	_refresh()

func restore(layers: Array) -> void:
	design=layers.duplicate(true)
	active=0 if not design.is_empty() else -1
	_refresh()

func _commit(next: Array, rebuild := true) -> bool:
	var cleaned: Variant=Document.clean(next)
	if cleaned==null:
		notice.text="This design exceeds the layer or image size limit."
		return false
	if cleaned==design:return true
	undo.append(design.duplicate(true))
	if undo.size()>24:undo.pop_front()
	redo.clear()
	design=cleaned
	notice.text=""
	_emit(rebuild)
	return true

func _emit(rebuild: bool) -> void:
	_refresh_list()
	if rebuild:_show_details()
	design_changed.emit(design.duplicate(true))

func _refresh() -> void:
	_refresh_list()
	_show_details()

func _refresh_list() -> void:
	list.clear()
	for index in design.size():
		var layer: Dictionary=design[index]
		list.add_item("%s   %s%s" % [layer.name," · hidden" if not layer.visible else ""," · locked" if layer.locked else ""])
	active=clampi(active,0,design.size()-1) if not design.is_empty() else -1
	if active>=0:list.select(active)
	undo_button.disabled=undo.is_empty()
	redo_button.disabled=redo.is_empty()

func _show_details() -> void:
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	canvas=null
	if active<0:return
	var layer: Dictionary=design[active]
	var banner:=HFlowContainer.new()
	details.add_child(banner)
	var name_field:=LineEdit.new()
	name_field.text=layer.name
	name_field.placeholder_text="Layer name"
	name_field.custom_minimum_size.x=125
	name_field.max_length=28
	name_field.editable=not layer.locked
	name_field.text_submitted.connect(func(value: String):
		if not value.strip_edges().is_empty():_set_layer("name",value.strip_edges(),false))
	banner.add_child(name_field)
	for key in ["visible","locked"]:
		var toggle:=CheckButton.new()
		toggle.text="Visible" if key=="visible" else "Lock"
		toggle.button_pressed=layer[key]
		toggle.toggled.connect(_toggle_flag.bind(key))
		banner.add_child(toggle)
	if layer.kind=="paint":_add_canvas(layer)
	elif layer.kind=="text":
		var text:=LineEdit.new()
		text.text=layer.data
		text.placeholder_text="Text on the surface"
		text.max_length=48
		text.editable=not layer.locked
		text.text_changed.connect(func(value: String):_set_layer("data",value,false))
		details.add_child(text)
	elif layer.kind=="shape":
		var shapes:=OptionButton.new()
		for value in Document.SHAPES:shapes.add_item(value)
		shapes.select(Document.SHAPES.find(layer.data))
		shapes.disabled=layer.locked
		shapes.item_selected.connect(func(index: int):_set_layer("data",Document.SHAPES[index],false))
		details.add_child(shapes)
	_add_properties(layer)

func _add_canvas(layer: Dictionary) -> void:
	canvas=Canvas.new()
	canvas.custom_minimum_size.y=170
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE if layer.locked else Control.MOUSE_FILTER_STOP
	details.add_child(canvas)
	canvas.load_pixels(layer.data)
	canvas.finished.connect(func(image: Image):_set_layer("data",Document.encode(image),false))
	var tools:=HFlowContainer.new()
	details.add_child(tools)
	var tool:=OptionButton.new()
	for value in ["Brush","Eraser","Fill","Line","Rectangle","Ellipse"]:tool.add_item(value)
	tool.item_selected.connect(func(index: int):canvas.tool=tool.get_item_text(index))
	tools.add_child(tool)
	var ink:=ColorPickerButton.new()
	ink.color=canvas.brush
	ink.custom_minimum_size=Vector2(45,28)
	ink.tooltip_text="Brush color and opacity"
	ink.color_changed.connect(func(value: Color):canvas.brush=value)
	tools.add_child(ink)
	var radius:=_number(1,14,1,4)
	radius.tooltip_text="Brush radius"
	radius.value_changed.connect(func(value: float):canvas.radius=int(value))
	tools.add_child(radius)
	var edge:=_number(0,1,.05,.8)
	edge.tooltip_text="Brush hardness"
	edge.value_changed.connect(func(value: float):canvas.hardness=value)
	tools.add_child(edge)
	var clear:=UI.action("Clear paint","",func():_set_layer("data","",true))
	tools.add_child(clear)
	for control in tools.get_children():
		if control is BaseButton:control.disabled=layer.locked

func _add_properties(layer: Dictionary) -> void:
	var grid:=GridContainer.new()
	grid.columns=2
	details.add_child(grid)
	for entry in [["Horizontal","x",0,1,.01],["Vertical","y",0,1,.01],["Scale","size",.1,1,.01],["Rotation","angle",-180,180,1],
		["Opacity","opacity",0,1,.05],["Metallic","metallic",0,1,.05],["Roughness","roughness",0,1,.05],["Glow","glow",0,2,.05]]:
		if layer.kind=="text" and entry[1] in ["metallic","roughness"]:continue
		grid.add_child(UI.text(entry[0]))
		var spin:=_number(entry[2],entry[3],entry[4],layer[entry[1]])
		spin.editable=not layer.locked
		spin.value_changed.connect(_set_value.bind(entry[1]))
		grid.add_child(spin)
	if layer.kind=="image":
		for edge in ["left","right","top","bottom"]:
			var key: String="crop_"+edge
			grid.add_child(UI.text("Crop "+edge))
			var crop:=_number(0,.4,.02,layer[key])
			crop.editable=not layer.locked
			crop.value_changed.connect(_set_value.bind(key))
			grid.add_child(crop)
	grid.add_child(UI.text("Tint"))
	var color:=ColorPickerButton.new()
	color.color=Color(layer.color)
	color.edit_alpha=false
	color.disabled=layer.locked
	color.color_changed.connect(func(value: Color):_set_layer("color",value.to_html(false),false))
	grid.add_child(color)
	if layer.kind!="text":
		grid.add_child(UI.text("Glow color"))
		var glow_color:=ColorPickerButton.new()
		glow_color.color=Color(layer.glow_color)
		glow_color.edit_alpha=false
		glow_color.disabled=layer.locked
		glow_color.color_changed.connect(func(value: Color):_set_layer("glow_color",value.to_html(false),false))
		grid.add_child(glow_color)
		grid.add_child(UI.text("Blend"))
		var blend:=OptionButton.new()
		for option in Document.BLENDS:blend.add_item(option)
		blend.select(layer.blend)
		blend.disabled=layer.locked
		blend.item_selected.connect(func(index: int):_set_layer("blend",index,false))
		grid.add_child(blend)

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

func _toggle_flag(value: bool,key: String) -> void:
	_set_layer(key,value,true)

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
	layer.data="Panel" if kind=="shape" else "LabVolt" if kind=="text" else data
	next.append(layer)
	active=next.size()-1
	if _commit(next):focus_surface.emit()

func _move(direction: int) -> void:
	if active<0 or design[active].locked:return
	var destination:=active+direction
	if destination<0 or destination>=design.size():return
	var next:=design.duplicate(true)
	var moving: Dictionary=next.pop_at(active)
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

func _merge_paint() -> void:
	if active<1:return
	var top: Dictionary=design[active]
	var below: Dictionary=design[active-1]
	if top.kind!="paint" or below.kind!="paint" or top.locked or below.locked or not top.visible or not below.visible:
		notice.text="Select a visible, unlocked paint layer above another paint layer."
		return
	for key in ["x","y","size","angle","metallic","roughness","glow","glow_color","color"]:
		if top[key]!=below[key]:
			notice.text="Align the layers and match their material settings before merging."
			return
	if top.opacity!=1.0 or below.opacity!=1.0 or top.blend!=0 or below.blend!=0:
		notice.text="Merging requires Normal blend and full opacity on both layers."
		return
	var lower:=Document.decode(below.data)
	var upper:=Document.decode(top.data)
	if lower==null:lower=Image.create_empty(Document.PIXELS,Document.PIXELS,false,Image.FORMAT_RGBA8)
	if upper!=null:
		lower.convert(Image.FORMAT_RGBA8)
		upper.convert(Image.FORMAT_RGBA8)
		upper.resize(lower.get_width(),lower.get_height(),Image.INTERPOLATE_BILINEAR)
		lower.blend_rect(upper,Rect2i(Vector2i.ZERO,upper.get_size()),Vector2i.ZERO)
	var next:=design.duplicate(true)
	next[active-1].data=Document.encode(lower)
	next.remove_at(active)
	active-=1
	_commit(next)

func _reset() -> void:
	_commit([])

func _undo() -> void:
	if undo.is_empty():return
	redo.append(design.duplicate(true))
	design=undo.pop_back()
	_emit(true)

func _redo() -> void:
	if redo.is_empty():return
	undo.append(design.duplicate(true))
	design=redo.pop_back()
	_emit(true)

func _save() -> void:
	var path: String="user://equipment-design-"+product_kind+".json"
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:
		notice.text="Could not save this design."
		return
	file.store_string(JSON.stringify(design))
	file.close()
	notice.text="Design saved for this product." if DirAccess.rename_absolute(path+".tmp",path)==OK else "Could not save this design."

func _load() -> void:
	var file:=FileAccess.open("user://equipment-design-"+product_kind+".json",FileAccess.READ)
	if file==null or file.get_length()>Document.MAX_DOCUMENT+4096:
		notice.text="There is no loadable saved design for this product."
		return
	var data: Variant=JSON.parse_string(file.get_as_text())
	if not data is Array:
		notice.text="Could not load this design."
		return
	_commit(data)

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
	_add("image",data)

func _pick_usb() -> void:
	var dorm: Dictionary=profile.data.get("dorm",{})
	var drives: Dictionary=dorm.get("usb_drives",{})
	if drives.is_empty():
		notice.text="You need an owned USB drive to import a Campus OS image."
		return
	var picker:=AcceptDialog.new()
	picker.title="Import from a Campus OS USB drive"
	var body:=VBoxContainer.new()
	body.custom_minimum_size=Vector2(460,300)
	picker.add_child(body)
	var choices:=OptionButton.new()
	body.add_child(choices)
	var files:=ItemList.new()
	files.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(files)
	var archive:={}
	var select:=func(index: int):
		files.clear()
		archive.clear()
		var id: String=choices.get_item_metadata(index)
		var opened:=USB.load(str(dorm.owner),id,int(drives[id].capacity_mb))
		if opened.has("error"):return
		archive["drive"]=opened.drive
		for path in opened.drive.entries:
			var entry: Dictionary=opened.drive.entries[path]
			if path.get_extension().to_lower() in ["png","jpg","jpeg","webp"] and entry.type=="file" and entry.data.size()<=Document.MAX_IMPORT:
				files.add_item(path)
	for id in drives:
		var drive: Dictionary=drives[id]
		if drive.location not in ["hotbar","cabinet"]:continue
		choices.add_item(drive.name)
		choices.set_item_metadata(choices.item_count-1,id)
	if choices.item_count==0:
		picker.free()
		notice.text="Disconnect or collect an owned USB drive before importing."
		return
	choices.item_selected.connect(select)
	add_child(picker)
	select.call(0)
	picker.ok_button_text="Import selected image"
	picker.dialog_hide_on_ok=false
	var accept:=func():
		if files.get_selected_items().is_empty() or not archive.has("drive"):return
		var path:=files.get_item_text(files.get_selected_items()[0])
		_import(archive.drive.entries[path].data,path)
		picker.queue_free()
	picker.confirmed.connect(accept)
	files.item_activated.connect(func(_index: int):accept.call())
	picker.canceled.connect(picker.queue_free)
	picker.popup_centered()
