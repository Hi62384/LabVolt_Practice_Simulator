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
var erasing := false
var pressed := false
var last_erase_ms := -1000
var surface := Control.new()
var toolbar := HBoxContainer.new()

static func points(path: Variant) -> PackedVector2Array:
	return PackedVector2Array(path.get("points",[]) if path is Dictionary else path)

static func paint(canvas: Control, paths_to_draw: Array) -> void:
	for path in paths_to_draw:
		var local := points(path)
		if local.is_empty():continue
		for i in local.size():local[i] *= canvas.size
		var color := Color(str(path.get("color",DEFAULT_COLOR))) if path is Dictionary else Color(DEFAULT_COLOR)
		var width := float(path.get("width",DEFAULT_WIDTH)) if path is Dictionary else DEFAULT_WIDTH
		width *= canvas.size.x / 800.0
		if local.size()>1 and (local.size()>2 or local[0]!=local[1]):canvas.draw_polyline(local,color,width,true)
		canvas.draw_circle(local[0],width*.5,color,true,-1,true)
		if local[-1]!=local[0]:canvas.draw_circle(local[-1],width*.5,color,true,-1,true)

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
	_button("Pencil",func():erasing=false)
	_button("Eraser",func():erasing=true)
	var color := ColorPickerButton.new()
	color.color=paint_color
	color.edit_alpha=false
	color.accessibility_name="Pencil color"
	color.color_changed.connect(func(value: Color):paint_color=value)
	toolbar.add_child(color)
	var size_field := SpinBox.new()
	size_field.accessibility_name="Brush size"
	size_field.min_value=2
	size_field.max_value=24
	size_field.value=brush_size
	size_field.value_changed.connect(func(value: float):brush_size=value)
	toolbar.add_child(size_field)
	_button("Undo",func():command_requested.emit({"op":"board_edit","id":board_id,"edit":"undo"}))
	var confirm := ConfirmationDialog.new()
	confirm.title="Clear whiteboard"
	confirm.dialog_text="Erase all drawing on this board?"
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
	surface.draw.connect(func():
		surface.draw_rect(Rect2(Vector2.ZERO,surface.size),Color("e9eee8"))
		paint(surface,paths)
		if not current.is_empty():paint(surface,[{"points":current,"color":paint_color.to_html(false),"width":brush_size}]))

func _button(label: String, action: Callable) -> void:
	var control := Button.new()
	control.text=label
	control.pressed.connect(action)
	toolbar.add_child(control)

func refresh(paper: Dictionary) -> void:
	paths=paper.get("board_lines",[]).duplicate()
	surface.queue_redraw()

func _draw_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		pressed=event.pressed
		if pressed:_sample(event.position)
		else:_flush_path()
		surface.accept_event()
	elif event is InputEventMouseMotion and pressed:
		_sample(event.position)
		surface.accept_event()

func _sample(local: Vector2) -> void:
	var point := (local/surface.size).clamp(Vector2.ZERO,Vector2.ONE)
	if erasing:
		var now := Time.get_ticks_msec()
		if now-last_erase_ms<55:return
		last_erase_ms=now
		command_requested.emit({"op":"board_mark","id":board_id,"from":point,"point":point,"erase":true,"radius":brush_size/200.0})
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
