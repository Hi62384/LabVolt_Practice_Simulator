extends Control

signal text_changed
signal finish_requested(save: bool)

const Layout = preload("res://scripts/ui/paper_workspace/equations/layout.gd")
const Parser = preload("res://scripts/ui/paper_workspace/equations/parser.gd")
const EMPTY := "□"

var font: Font = ThemeDB.fallback_font
var font_size := 24
var ink := Color.BLACK
var caret_ink := Color("14778b")
var caret_width := 1.8
var follow_caret := false
var empty_source := EMPTY
var offset := Vector2.ZERO
var expression: Array = []
var field: Array = expression
var cursor := 0
var path: Array[Dictionary] = []
var stops: Array[Dictionary] = []
var undo_stack: Array[String] = []
var redo_stack: Array[String] = []
var plan: Dictionary={}
var loaded_source := ""
var structure_edited := false
var text: String:
	get: return (_serialize(expression) if not expression.is_empty() else empty_source) if structure_edited else loaded_source
	set(value): _load(value)

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_IBEAM
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	refresh()

func _get_minimum_size() -> Vector2:
	if not follow_caret:return Vector2.ZERO
	return Vector2(0,maxf(font.get_height(font_size),plan.get("size",Vector2.ZERO).y)+4.0)

func _load(value: String) -> void:
	loaded_source = value
	structure_edited = false
	var parsed := Parser.new().parse(value)
	expression = _import(parsed.tree) if parsed.ok else Array(value.split(""))
	field = expression
	path.clear()
	cursor = field.size()
	refresh()

func _import(node: Dictionary) -> Array:
	match node.op:
		"atom":
			return [] if node.text == EMPTY else Array(str(node.text).split(""))
		"/", "^", "_", "ⁿ√":
			var left: Dictionary = node.left
			var right: Dictionary = node.right
			return [{"op":node.op, "left":_import(left.child if left.op == "group" else left),
				"right":_import(right.child if right.op == "group" else right)}]
		"group": return ["("] + _import(node.child) + [")"]
		"prefix": return [node.sign] + _import(node.child)
		"function":
			if node.name == "sqrt": return [{"op":"sqrt","left":_import(node.child)}]
			return Array(str(node.name).split("")) + ["("] + _import(node.child) + [")"]
		"matrix":
			var matrix := ["["]
			for row in node.rows:
				if matrix.size() > 1: matrix.append(";")
				for index in row.size():
					if index > 0: matrix.append(",")
					matrix.append_array(_import(row[index]))
			matrix.append("]")
			return matrix
		_:
			var between := [] if node.get("implicit", false) else [node.op]
			return _import(node.left) + between + _import(node.right)

func _serialize(row: Array) -> String:
	var source := ""
	for token in row:
		if token is String:
			source += token
		elif token.op == "sqrt":
			source += "sqrt(%s)" % _serialize(token.left)
		else:
			source += "(%s)%s(%s)" % [_serialize(token.left), token.op, _serialize(token.right)]
	return source if not source.is_empty() else EMPTY

func _model(row: Array, trail: Array) -> Dictionary:
	var parts := []
	for index in row.size() + 1:
		parts.append({"op":"caret", "trail":trail, "index":index, "empty":row.is_empty()})
		if index == row.size(): break
		var token: Variant = row[index]
		if token is String:
			var glyph: String={"*":"×","-":"−"}.get(token,token) if follow_caret else token
			parts.append({"op":"atom","text":glyph})
		elif token.op == "sqrt":
			parts.append({"op":"function","name":"sqrt","child":_model(token.left, trail + [{"index":index,"key":"left"}])})
		else:
			parts.append({"op":token.op,
				"left":_model(token.left, trail + [{"index":index,"key":"left"}]),
				"right":_model(token.right, trail + [{"index":index,"key":"right"}])})
	return {"op":"sequence","parts":parts}

func refresh() -> void:
	plan = Layout._layout(_model(expression, []), font, font_size, 0)
	stops.clear()
	for command in plan.commands:
		if command.kind == "caret": stops.append(command)
	if follow_caret:update_minimum_size()
	queue_redraw()

func _draw() -> void:
	if plan.is_empty(): return
	if follow_caret:
		var farthest := minf(0.0,size.x-float(plan.size.x)-6.0)
		for stop in stops:
			if stop.trail!=path or stop.index!=cursor:continue
			offset.x=clampf(offset.x,farthest,0.0)
			if offset.x+stop.pos.x<4.0:offset.x=minf(0.0,4.0-stop.pos.x)
			elif offset.x+stop.pos.x>size.x-6.0:offset.x=maxf(farthest,size.x-6.0-stop.pos.x)
			break
		offset.y=maxf(0.0,(size.y-float(plan.size.y))*.5)
	Layout.draw(self, plan, offset, font, ink)
	if not has_focus() and not follow_caret: return
	for stop in stops:
		if stop.trail == path and stop.index == cursor:
			var caret_pos: Vector2=offset+stop.pos+Vector2(1.5,0)
			if stop.empty: draw_rect(Rect2(caret_pos, Vector2(stop.height * .55, stop.height)), Color("49b7c152"))
			draw_line(caret_pos, caret_pos + Vector2(0,stop.height), caret_ink, caret_width)
			break

func _select_stop(stop: Dictionary) -> void:
	path.assign(stop.trail)
	field = expression
	for step in path:
		field = field[step.index][step.key]
	cursor = stop.index
	queue_redraw()

func _move_vertical(direction: int) -> void:
	var current: Dictionary
	for stop in stops:
		if stop.trail == path and stop.index == cursor: current = stop; break
	if current.is_empty(): return
	var nearest: Dictionary
	var distance := INF
	for stop in stops:
		var difference: Vector2 = (stop.pos + Vector2.DOWN * stop.height * .5) - (current.pos + Vector2.DOWN * current.height * .5)
		if difference.y * direction <= 3: continue
		var cost := absf(difference.y) * 2.0 + absf(difference.x)
		if cost < distance: nearest = stop; distance = cost
	if not nearest.is_empty(): _select_stop(nearest)

func move_horizontal(direction: int) -> void:
	for index in stops.size():
		var stop := stops[index]
		if stop.trail == path and stop.index == cursor:
			_select_stop(stops[clampi(index + direction, 0, stops.size() - 1)])
			return

func _record() -> String:
	return text

func _commit(before: String) -> void:
	structure_edited = true
	if text.length() > 256:
		_load(before)
		return
	undo_stack.append(before)
	if undo_stack.size() > 64: undo_stack.pop_front()
	redo_stack.clear()
	refresh()
	text_changed.emit()

func insert_text_at_caret(value: String) -> void:
	var before := _record()
	var symbols := PackedStringArray(["ⁿ√"]) if value=="ⁿ√" else value.split("")
	for symbol in symbols:
		if symbol in ["\n", "\r", EMPTY]: continue
		if symbol in ["/", "^", "_", "√", "ⁿ√"] and path.size() < 10:
			var left := [] if symbol == "√" else _take_left_operand()
			var node := {"op":"sqrt","left":[]} if symbol == "√" else {"op":symbol,"left":left,"right":[]}
			var key := "left" if symbol == "√" or left.is_empty() else "right"
			field.insert(cursor, node)
			path.append({"index":cursor,"key":key})
			field = node[key]
			cursor = 0
		else:
			field.insert(cursor, symbol)
			cursor += 1
	_commit(before)

func _take_left_operand() -> Array:
	var left: Array=[]
	var groups:=0
	while cursor>0:
		var preceding: Variant=field[cursor-1]
		if preceding is String:
			if preceding in [")","]"]:groups+=1
			elif preceding in ["(","["]:
				if groups==0:break
				groups-=1
			elif groups==0 and preceding in [" ","+","-","−","=","*","×","÷",","]:
				break
		cursor-=1
		left.push_front(field.pop_at(cursor))
		if groups==0 and preceding is Dictionary:break
	return left

func delete_at_caret(backwards: bool) -> void:
	var index := cursor - int(backwards)
	if index >= 0 and index < field.size():
		var before := _record()
		field.remove_at(index)
		cursor = index
		_commit(before)
	elif not path.is_empty():
		move_horizontal(-1 if backwards else 1)

func caret_state() -> Dictionary:
	return {"trail":path.duplicate(true),"index":cursor}

func restore_caret(state: Dictionary) -> void:
	for stop in stops:
		if stop.trail==state.get("trail") and stop.index==state.get("index"):
			_select_stop(stop)
			return

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		var distance := INF
		var nearest: Dictionary
		for stop in stops:
			var point: Vector2 = stop.pos + Vector2.DOWN * stop.height * .45
			var cost := point.distance_squared_to(event.position-offset)
			if cost < distance: nearest = stop; distance = cost
		if not nearest.is_empty(): _select_stop(nearest)
		accept_event()
		return
	if not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_ESCAPE: finish_requested.emit(false)
		KEY_ENTER, KEY_KP_ENTER: finish_requested.emit(true)
		KEY_LEFT: move_horizontal(-1)
		KEY_RIGHT: move_horizontal(1)
		KEY_UP: _move_vertical(-1)
		KEY_DOWN: _move_vertical(1)
		KEY_HOME: cursor = 0; queue_redraw()
		KEY_END: cursor = field.size(); queue_redraw()
		KEY_BACKSPACE, KEY_DELETE: delete_at_caret(event.keycode == KEY_BACKSPACE)
		KEY_Z, KEY_Y:
			if event.ctrl_pressed:
				var redo: bool = event.keycode == KEY_Y or event.shift_pressed
				var source := redo_stack if redo else undo_stack
				var target := undo_stack if redo else redo_stack
				if not source.is_empty():
					target.append(text)
					_load(source.pop_back())
					text_changed.emit()
			elif event.unicode >= 32: insert_text_at_caret(String.chr(event.unicode))
		_:
			if event.ctrl_pressed or event.alt_pressed or event.unicode < 32: return
			insert_text_at_caret(String.chr(event.unicode))
	accept_event()
