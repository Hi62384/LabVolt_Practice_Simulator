extends VBoxContainer
const View = preload("res://scripts/math_ui/expression_view.gd")
const Notation = preload("res://scripts/math_ui/math_notation.gd")
signal changed(value: String)
var tree: Dictionary = {"op":"text","value":""}
var selected_path: Array = []
var preview: Control
var entry: LineEdit
var status: Label
var matrix_grid: GridContainer
var parser: Callable
var editable := true
var undo_stack: Array = []
var redo_stack: Array = []

func _ready() -> void:
	var skin=preload("res://scripts/ui/design_system/theme.gd").create()
	var toolbar := HFlowContainer.new()
	toolbar.theme=skin
	add_child(toolbar)
	for token in ["a/b", "xⁿ", "xₙ", "√", "ⁿ√", "π", "θ", "φ", "ω", "j", "∠", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "ln", "log", "eⁿ", "!", "nCr", "2×2", "3×3", "det", "Undo", "Redo"]:
		var button := Button.new()
		button.text = token
		button.custom_minimum_size=Vector2(42,40)
		button.focus_mode=Control.FOCUS_ALL
		button.tooltip_text = "Wrap selected expression: " + token
		button.disabled = not editable
		button.pressed.connect(func(): insert_template(token))
		toolbar.add_child(button)
	preview = View.new()
	preview.highlight_enabled=true
	add_child(preview)
	preview.node_selected.connect(_select)
	matrix_grid=GridContainer.new()
	add_child(matrix_grid)
	entry = LineEdit.new()
	entry.theme=skin
	entry.custom_minimum_size.y=40
	entry.placeholder_text = "Edit selected value; click notation to choose a part"
	entry.max_length = 512
	entry.editable = editable
	entry.text_changed.connect(_edit_leaf)
	add_child(entry)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Click a value to edit. Ctrl+/ fraction · Ctrl+^ power · Ctrl+R root · Ctrl+Z undo"
	add_child(status)
	_refresh()

func configure(parse_callable: Callable, can_edit: bool = true) -> void:
	parser = parse_callable
	editable = can_edit
	if is_instance_valid(entry): entry.editable = can_edit

func set_value(value: Variant) -> void:
	tree = value.duplicate(true) if value is Dictionary else {"op":"text", "value":str(value)}
	selected_path = []
	_refresh()

func value() -> String:
	return Notation.source(tree)

func _node() -> Dictionary:
	var node := tree
	for index in selected_path:
		var children: Array = node.get("args", [])
		if int(index) >= children.size(): return tree
		node = children[int(index)]
	return node

func _select(path: Array) -> void:
	# Matrices are edited through the dedicated table widget, not ambiguous AST paths.
	if tree.get("op") in ["matrix", "determinant"]: return
	selected_path = path.duplicate()
	_refresh()
	entry.grab_focus()
	entry.select_all()

func _remember() -> void:
	undo_stack.append(tree.duplicate(true))
	if undo_stack.size() > 64: undo_stack.pop_front()
	redo_stack.clear()

func _replace(node: Dictionary) -> void:
	if selected_path.is_empty(): tree = node
	else:
		var target := _node()
		target.clear()
		target.merge(node)

func _edit_leaf(text: String) -> void:
	if not editable: return
	_remember()
	var parsed: Dictionary = parser.call(text) if parser.is_valid() else {}
	_replace(parsed.ast if parsed.get("ok", false) else {"op":"text","value":text})
	preview.set_expression(tree)
	preview.highlight_path=selected_path.duplicate()
	status.text = "" if parsed.get("ok", false) else (str(parsed.get("error", "Expression will be checked by the course engine")))
	changed.emit(value())

func insert_template(token: String) -> void:
	if not editable: return
	if token in ["Undo", "Redo"]:
		var src: Array = undo_stack if token == "Undo" else redo_stack
		var dst: Array = redo_stack if token == "Undo" else undo_stack
		if src.is_empty(): return
		dst.append(tree.duplicate(true))
		tree = src.pop_back()
		selected_path = []
	else:
		_remember()
		var old := _node().duplicate(true)
		if old.get("value", "") == "": old = {"op":"symbol","name":"x"}
		var one := {"op":"num","value":"1"}
		var two := {"op":"num","value":"2"}
		var node: Dictionary
		match token:
			"a/b": node = {"op":"div","args":[old, one]}
			"xⁿ": node = {"op":"pow","args":[old, two]}
			"xₙ": node = {"op":"subscript","args":[old, one]}
			"√": node = {"op":"sqrt","args":[old]}
			"ⁿ√": node = {"op":"root","args":[{"op":"num","value":"3"},old]}
			"π", "θ", "φ", "ω", "j": node = {"op":"symbol","name":{"π":"pi","θ":"theta","φ":"phi","ω":"omega","j":"j"}[token]}
			"∠": node = {"op":"complex_polar","args":[old,{"op":"num","value":"0"}]}
			"eⁿ": node = {"op":"exp","args":[old]}
			"!": node = {"op":"factorial","args":[old]}
			"nCr": node = {"op":"choose","args":[old,two]}
			"log": node = {"op":"log","args":[old,{"op":"num","value":"10"}]}
			"2×2", "det":
				node = {"op":"matrix" if token == "2×2" else "determinant","rows":[[old,one],[one,two]]}
			"3×3":node={"op":"matrix","rows":[[old,one,two],[one,two,one],[two,one,two]]}
			"atan2":node={"op":"atan2","args":[old,one]}
			_: node = {"op":token,"args":[old]}
		_replace(node)
	_refresh()
	changed.emit(value())

func _refresh() -> void:
	if not is_instance_valid(preview): return
	preview.set_expression(tree)
	preview.highlight_path=selected_path.duplicate()
	var node := _node()
	entry.text = str(node.get("value", node.get("name", "")))
	entry.placeholder_text = "Edit " + selection_label().to_lower()
	entry.visible=tree.get("op") not in ["matrix","determinant"]
	for child in matrix_grid.get_children():matrix_grid.remove_child(child);child.queue_free()
	if tree.get("op") in ["matrix","determinant"]:
		var rows:Array=tree.get("rows",[])
		matrix_grid.columns=rows[0].size() if not rows.is_empty() else 1
		for r in range(rows.size()):
			for c in range(rows[r].size()):
				var cell:=LineEdit.new();cell.text=Notation.source(rows[r][c]);cell.max_length=128;cell.editable=editable;matrix_grid.add_child(cell)
				cell.text_changed.connect(func(text):
					_remember()
					var parsed:Dictionary=parser.call(text) if parser.is_valid() else {}
					tree.rows[r][c]=parsed.ast if parsed.get("ok",false) else {"op":"text","value":text}
					preview.set_expression(tree);changed.emit(value()))

func selection_label() -> String:
	var current:=tree
	var role:=""
	for index in selected_path:
		var args:Array=current.get("args",[])
		if int(index)<0 or int(index)>=args.size():break
		var parent:=str(current.get("op",""))
		if parent=="div":role="numerator" if int(index)==0 else "denominator"
		elif parent=="pow":role="base" if int(index)==0 else "exponent"
		elif parent=="subscript":role="value" if int(index)==0 else "subscript"
		else:role=""
		current=args[int(index)]
	if not role.is_empty():return role.capitalize()
	return {"div":"Fraction","pow":"Power","num":"Value","symbol":"Value","text":"Value","sqrt":"Square root","cbrt":"Cube root","root":"Root","add":"Sum","sub":"Difference","mul":"Product","neg":"Negative value","exp":"Exponential expression","log":"Logarithm","ln":"Natural logarithm","complex_polar":"Polar expression","subscript":"Subscript","factorial":"Factorial","choose":"Combination","matrix":"Matrix","determinant":"Determinant"}.get(str(current.get("op","")),"Expression")

func _unhandled_key_input(event: InputEvent) -> void:
	if not editable or not event is InputEventKey or not event.pressed or not event.ctrl_pressed: return
	if not is_ancestor_of(get_viewport().gui_get_focus_owner()): return
	var token: String = {KEY_SLASH:"a/b", KEY_ASCIICIRCUM:"xⁿ", KEY_R:"√", KEY_Z:"Undo", KEY_Y:"Redo"}.get(event.keycode, "")
	if not token.is_empty():
		insert_template(token)
		get_viewport().set_input_as_handled()
