extends CanvasLayer

signal command_requested(action: Dictionary)
signal dismissed

const WorkspaceTheme = preload("res://scripts/ui/design_system/theme.gd")
const DEFAULT_COLOR := "294658"
const DEFAULT_WIDTH := 5.0
var board_id := 0
var board_aspect := 3.2
var paths: Array = []
var current := PackedVector2Array()
var paint_color := Color("294658")
var brush_size := 5.0
var gesture := MOUSE_BUTTON_NONE
var last_eraser_point := Vector2.ZERO
var last_erase_ms := -1000
var surface := Control.new()
var toolbar := HBoxContainer.new()
var board_cache: SubViewport
var cached_ink: Control

static func points(path: Variant) -> PackedVector2Array:
	return PackedVector2Array(path.get("points",[]) if path is Dictionary else path)

static func aspect_for(paper: Dictionary) -> float:
	var board_size: Vector2=paper.get("board_size",Vector2(1.35,.78))
	return board_size.x/maxf(board_size.y,.1)

static func texture_size(paper: Dictionary) -> Vector2i:
	return Vector2i(800,roundi(800.0/aspect_for(paper)))

static func paint(canvas: Control, paths_to_draw: Array) -> void:
	for path in paths_to_draw:
		var local := points(path)
		if local.is_empty():continue
		for i in local.size():local[i] *= canvas.size
		var color := Color(str(path.get("color",DEFAULT_COLOR))) if path is Dictionary else Color(DEFAULT_COLOR)
		var width := float(path.get("width",DEFAULT_WIDTH)) if path is Dictionary else DEFAULT_WIDTH
		width *= canvas.size.x / 800.0
		if local.size()>1 and (local.size()>2 or local[0]!=local[1]):canvas.draw_polyline(local,color,width,true)
		for i in local.size():
			if i==0 or local[i]!=local[i-1]:canvas.draw_circle(local[i],width*.5,color,true,-1,true)

func _ready() -> void:
	layer=62
	var backdrop := ColorRect.new()
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color=Color("132422e8")
	var margin := MarginContainer.new()
	backdrop.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	var column := VBoxContainer.new()
	column.theme=WorkspaceTheme.create()
	margin.add_child(column)
	column.add_child(toolbar)
	var title := Label.new()
	title.text="Whiteboard"
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	var color := ColorPickerButton.new()
	color.color=paint_color
	color.edit_alpha=false
	color.accessibility_name="Ink color"
	color.custom_minimum_size=Vector2(100,34)
	color.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	for state in ["normal","hover","pressed"]:color.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var swatch := Panel.new()
	swatch.mouse_filter=Control.MOUSE_FILTER_IGNORE
	color.add_child(swatch)
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill := StyleBoxFlat.new()
	fill.bg_color=paint_color
	fill.border_color=Color("8ca7a4")
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(6)
	swatch.add_theme_stylebox_override("panel",fill)
	color.color_changed.connect(func(value: Color):
		paint_color=value
		fill.bg_color=value)
	toolbar.add_child(color)
	var size_label := Label.new()
	size_label.text="Size"
	toolbar.add_child(size_label)
	var slider := HSlider.new()
	slider.custom_minimum_size.x=116
	slider.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	slider.min_value=2
	slider.max_value=24
	slider.step=1
	slider.value=brush_size
	slider.accessibility_name="Brush size slider"
	toolbar.add_child(slider)
	var size_field := SpinBox.new()
	size_field.accessibility_name="Exact brush size"
	var field := size_field.get_line_edit()
	field.add_theme_font_size_override("font_size",15)
	var field_style := column.theme.get_stylebox("normal","LineEdit").duplicate() as StyleBox
	field_style.content_margin_top=4
	field_style.content_margin_bottom=4
	field.add_theme_stylebox_override("normal",field_style)
	size_field.min_value=2
	size_field.max_value=24
	size_field.step=1
	size_field.value=brush_size
	size_field.share(slider)
	slider.value_changed.connect(func(value: float):brush_size=value)
	toolbar.add_child(size_field)
	_button("Undo",func():command_requested.emit({"op":"board_edit","id":board_id,"edit":"undo"}))
	var confirm := ConfirmationDialog.new()
	confirm.theme=column.theme
	confirm.title="Clear whiteboard"
	confirm.dialog_text="Erase all drawing on this board?"
	confirm.ok_button_text="Clear board"
	confirm.confirmed.connect(func():command_requested.emit({"op":"board_edit","id":board_id,"edit":"clear"}))
	add_child(confirm)
	_button("Clear",func():confirm.popup_centered())
	_button("Close",func():dismissed.emit())
	var aspect := AspectRatioContainer.new()
	aspect.ratio=board_aspect
	aspect.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(aspect)
	aspect.add_child(surface)
	surface.clip_contents=true
	surface.mouse_filter=Control.MOUSE_FILTER_STOP
	surface.gui_input.connect(_draw_input)
	board_cache=SubViewport.new()
	board_cache.disable_3d=true
	board_cache.render_target_update_mode=SubViewport.UPDATE_DISABLED
	surface.add_child(board_cache)
	cached_ink=Control.new()
	board_cache.add_child(cached_ink)
	cached_ink.draw.connect(func():
		cached_ink.draw_rect(Rect2(Vector2.ZERO,cached_ink.size),Color("e9eee8"))
		paint(cached_ink,paths))
	var snapshot:=TextureRect.new()
	snapshot.texture=board_cache.get_texture()
	snapshot.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	snapshot.mouse_filter=Control.MOUSE_FILTER_IGNORE
	snapshot.show_behind_parent=true
	surface.add_child(snapshot)
	snapshot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.resized.connect(_refresh_cache)
	_refresh_cache.call_deferred()
	surface.draw.connect(func():
		if not current.is_empty():paint(surface,[{"points":current,"color":paint_color.to_html(false),"width":brush_size}]))

func _button(label: String, action: Callable) -> void:
	var control := Button.new()
	control.text=label
	control.add_theme_font_size_override("font_size",15)
	for state in ["normal","hover","pressed"]:
		var style := toolbar.get_theme_stylebox(state,"Button").duplicate() as StyleBox
		style.content_margin_top=6
		style.content_margin_bottom=6
		control.add_theme_stylebox_override(state,style)
	control.pressed.connect(action)
	toolbar.add_child(control)

func refresh(paper: Dictionary) -> void:
	var updated: Array=paper.get("board_lines",[])
	if updated==paths:return
	paths=updated.duplicate()
	_refresh_cache()

func _refresh_cache() -> void:
	if not is_instance_valid(board_cache) or surface.size.x<2 or surface.size.y<2:return
	var resolution:=surface.size*minf(1.0,2048.0/surface.size.x)
	board_cache.size=Vector2i(resolution).max(Vector2i(2,2))
	cached_ink.size=Vector2(board_cache.size)
	cached_ink.queue_redraw()
	board_cache.render_target_update_mode=SubViewport.UPDATE_ONCE

func _draw_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.pressed and gesture==MOUSE_BUTTON_NONE:
			gesture=event.button_index
			if gesture==MOUSE_BUTTON_RIGHT:
				last_eraser_point=_point(event.position)
				last_erase_ms=-1000
			_sample(event.position,true)
		elif not event.pressed and gesture==event.button_index:
			_sample(event.position,true)
			if gesture==MOUSE_BUTTON_LEFT:_flush_path()
			gesture=MOUSE_BUTTON_NONE
		surface.accept_event()
	elif event is InputEventMouseMotion and gesture!=MOUSE_BUTTON_NONE:
		_sample(event.position)
		surface.accept_event()

func _point(local: Vector2) -> Vector2:
	return (local/surface.size).clamp(Vector2.ZERO,Vector2.ONE)

func _sample(local: Vector2, force := false) -> void:
	var point := _point(local)
	if gesture==MOUSE_BUTTON_RIGHT:
		var now := Time.get_ticks_msec()
		if not force and now-last_erase_ms<55:return
		last_erase_ms=now
		command_requested.emit({"op":"board_mark","id":board_id,"from":last_eraser_point,"point":point,"erase":true,"radius":brush_size/800.0})
		last_eraser_point=point
	elif current.is_empty() or point.distance_squared_to(current[-1])>.000001:
		current.append(point)
		if current.size()>=240:
			_flush_path()
			current.append(point)
		surface.queue_redraw()

func _flush_path() -> void:
	if current.is_empty():return
	if current.size()==1:current.append(current[0])
	var path := current
	current=PackedVector2Array()
	command_requested.emit({"op":"board_path","id":board_id,"points":path,"color":paint_color.to_html(false),"width":brush_size})
	surface.queue_redraw()
