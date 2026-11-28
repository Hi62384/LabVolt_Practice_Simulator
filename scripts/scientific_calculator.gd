extends PanelContainer
signal close_requested
const Supplies = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Finance = preload("res://scripts/financial_calculator.gd")
const Equipment = preload("res://scripts/campus/items/equipment_configuration.gd")
const KeyGrid = preload("res://scripts/campus/items/calculator_key_grid.gd")
const MathEngine=preload("res://scripts/campus/computers/CalculatorMath.cs")
const Equation=preload("res://scripts/campus/items/calculator_equation_view.gd")
const EquationEditor=preload("res://scripts/ui/paper_workspace/equations/editor.gd")
const Parser=preload("res://scripts/ui/paper_workspace/equations/parser.gd")
const Graph=preload("res://scripts/campus/items/calculator_graph_view.gd")
var math_engine: RefCounted
var performance: Node
var busy_label: Label
var queued_controls:=0
var advanced_app:=false
var equation_enabled:=false
var algebra_enabled:=false
var complex_enabled:=false
var graph_level:=0
var configured:=false
var result_equation: Control
var graph: Control
var functions: VBoxContainer
var isolate_picker: OptionButton
var answer_source := "0"
var pending_number:=0.0
var pending_operator:=""
var replace_number:=true
var finance_help: Label
var model := "calculator"
var equipment_options: Dictionary={}
var show_close := false
var campus_style := false
var display
var result: Label
var answer := 0.0
var memory := 0.0
var memory_label: Label
func _ready() -> void:
	theme=preload("res://scripts/ui/design_system/theme.gd").create()
	configured=equipment_options.has("body")
	equation_enabled=advanced_app or bool(Equipment.value(Equipment.CALCULATOR,equipment_options,"hardware","equation",false))
	algebra_enabled=advanced_app or bool(Equipment.value(Equipment.CALCULATOR,equipment_options,"hardware","algebra",false))
	equation_enabled=equation_enabled or algebra_enabled
	complex_enabled=advanced_app or bool(Equipment.value(Equipment.CALCULATOR,equipment_options,"hardware","complex",false))
	graph_level=2 if advanced_app else int(Equipment.value(Equipment.CALCULATOR,equipment_options,"hardware","graph",0))
	if equation_enabled or algebra_enabled:math_engine=MathEngine.new()
	var basic := model=="calculator_basic"
	var financial := model=="calculator_financial"
	custom_minimum_size.x=260 if basic else 280
	var shell := StyleBoxFlat.new();shell.bg_color=Color("15171a") if basic else Color("39473c") if financial else Color("29333e")
	if not equipment_options.is_empty():
		shell.bg_color=Color(Equipment.value(Equipment.CALCULATOR,equipment_options,"appearance","shell","29333e")).darkened(.28)
	if campus_style:
		shell.bg_color=Color("062738")
		shell.border_color=Color("1c5669")
		shell.set_border_width_all(1)
	shell.set_corner_radius_all(18);shell.set_content_margin_all(12);add_theme_stylebox_override("panel",shell)
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",4 if show_close else 6);add_child(body)
	var header := HBoxContainer.new();body.add_child(header)
	var brand := Label.new();brand.text=Supplies.TOOLS.get(model,"Scientific calculator");brand.add_theme_font_size_override("font_size",16);header.add_child(brand)
	brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if show_close:
		var close := preload("res://scripts/ui/design_system/widgets.gd").action("Close","close",func():close_requested.emit())
		header.add_child(close)
	var lcd := PanelContainer.new();var lcd_style := StyleBoxFlat.new();lcd_style.bg_color=Color("0d4553") if campus_style else Color("d5dfcf");lcd_style.set_content_margin_all(10);lcd_style.set_corner_radius_all(5);lcd.add_theme_stylebox_override("panel",lcd_style);body.add_child(lcd)
	if not equipment_options.is_empty():
		lcd_style.bg_color=Color(Equipment.value(Equipment.CALCULATOR,equipment_options,"appearance","screen_color","d5dfcf"))
		var display_scale: float=Equipment.value(Equipment.CALCULATOR,equipment_options,"hardware","screen",1.0)
		lcd.custom_minimum_size.y=72.0*display_scale
	if campus_style:
		lcd_style.set_corner_radius_all(10)
		lcd_style.border_color=Color("358598")
		lcd_style.set_border_width_all(1)
	var lines := VBoxContainer.new();lcd.add_child(lines)
	memory_label=Label.new();memory_label.text="M";memory_label.hide();memory_label.add_theme_color_override("font_color",Color("91d9de") if campus_style else Color("385044"));memory_label.add_theme_font_size_override("font_size",12);lines.add_child(memory_label)
	var lcd_ink:=Color("e6fbff") if lcd_style.bg_color.get_luminance()<.35 else Color("102218")
	if equation_enabled:
		var editor:=EquationEditor.new()
		editor.follow_caret=true
		editor.empty_source=""
		editor.ink=lcd_ink
		editor.caret_ink=lcd_ink
		editor.caret_width=2.6
		editor.highlight_empty_caret=false
		editor.font_size=21 if show_close else 24
		editor.clip_contents=true
		editor.accessibility_name="Equation"
		editor.finish_requested.connect(func(save):
			if save:_schedule(evaluate))
		display=editor
	else:
		var entry:=LineEdit.new()
		entry.placeholder_text="0"
		entry.max_length=180
		entry.add_theme_font_size_override("font_size",18)
		entry.add_theme_color_override("font_color",lcd_ink)
		entry.add_theme_color_override("caret_color",lcd_ink)
		entry.add_theme_color_override("font_placeholder_color",lcd_ink.lerp(lcd_style.bg_color,.4))
		entry.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
		entry.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		entry.text_submitted.connect(func(_text):_schedule(evaluate))
		display=entry
	lines.add_child(display)
	result=Label.new();result.text="" if equation_enabled else "0";result.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;result.add_theme_font_size_override("font_size",20);result.add_theme_color_override("font_color",lcd_ink);result.clip_text=true;lines.add_child(result)
	if equation_enabled:result.hide()
	if campus_style and not equation_enabled:result.add_theme_font_size_override("font_size",34)
	if _number_mode():
		display.alignment=HORIZONTAL_ALIGNMENT_RIGHT
		display.add_theme_font_size_override("font_size",26)
		display.gui_input.connect(_number_keyboard_input)
		display.text_changed.connect(func(_text):replace_number=false)
		result.add_theme_font_size_override("font_size",14)
		result.text=""
		lines.move_child(result,1)
	if equation_enabled:
		result_equation=Equation.new()
		result_equation.ink=lcd_ink
		lines.add_child(result_equation)
		result_equation.hide()
	if algebra_enabled or graph_level>0:
		var tools:=HBoxContainer.new()
		body.add_child(tools)
		if algebra_enabled:
			isolate_picker=OptionButton.new()
			isolate_picker.accessibility_name="Variable to isolate"
			isolate_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			tools.add_child(isolate_picker)
			isolate_picker.hide()
			display.text_changed.connect(_refresh_isolation)
		if graph_level>0:tools.add_child(_action("Graph",func():functions.visible=not functions.visible))
	if graph_level>0:_build_graph(body)
	var grid := KeyGrid.new()
	grid.name="Keypad"
	grid.columns=Equipment.value(Equipment.CALCULATOR,equipment_options,"hardware","columns",6 if advanced_app else 4 if basic else 5)
	grid.cell_size=Vector2(38 if advanced_app else 44,32 if show_close else 40)
	grid.gap=Vector2(6,4)
	body.add_child(grid)
	if basic or financial or campus_style:grid.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var keys: Array=equipment_options.get("keypad",keypad_keys(model)).duplicate()
	if advanced_app and not configured:
		keys.append_array(["Equality","x","y","z","i","∠","Convert","∫","d/dx","Factor"])
	var spatial:=configured and int(equipment_options.get("version",1))>=Equipment.DESIGN_VERSION
	if configured and not spatial:keys=Equipment.Keypad.with_required(keys)
	keys=Equipment.Keypad.display_slots(keys,grid.columns,spatial)
	keys=keys.slice(0,Equipment.Keypad.occupied_rows(keys,grid.columns)*grid.columns)
	var round_keys: bool=Equipment.value(Equipment.CALCULATOR,equipment_options,"appearance","key_style",false)
	var key_colors: Dictionary=equipment_options.get("key_colors",{})
	var material_tint:=Color(equipment_options.get("materials",{}).get("keys",{}).get("color","ffffff"))
	if financial or (configured and keys.any(func(key):return Finance.ARGUMENTS.has(key))):
		finance_help=Label.new()
		finance_help.text="Choose a finance key for its inputs"
		finance_help.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		finance_help.add_theme_font_size_override("font_size",12)
		body.add_child(finance_help)
		body.move_child(finance_help,2)
	for index in keys.size():
		var key: String=keys[index]
		if key.is_empty():
			var blank:=Panel.new()
			blank.visible=not Equipment.Keypad.continuation(keys,index,grid.columns)
			var recess:=StyleBoxFlat.new()
			recess.bg_color=Color("172d38")
			recess.set_corner_radius_all(5)
			blank.add_theme_stylebox_override("panel",recess)
			grid.add_child(blank)
			continue
		var button := Button.new()
		button.text=Equipment.Keypad.caption(key)
		button.clip_text=true
		button.set_meta("keypad_span",Equipment.Keypad.span(key))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",15)
		var key_info:=Equipment.Keypad.catalog(key)
		button.accessibility_name=key_info.get("name",key)
		button.tooltip_text=key_info.get("description",key)
		if basic or financial or campus_style:button.size_flags_vertical=Control.SIZE_EXPAND_FILL
		if financial and Finance.ARGUMENTS.has(key):button.tooltip_text=Finance.ARGUMENTS[key]
		var style := StyleBoxFlat.new();style.bg_color=(Color("2e5267") if campus_style else Color("647781")) if key.is_valid_int() or key=="." else (Color("103c55") if campus_style else Color("3e4b59"))
		if not equipment_options.is_empty():
			style.bg_color=Color(Equipment.value(Equipment.CALCULATOR,equipment_options,"appearance","keys","60747e"))
			if not key.is_valid_int() and key!=".":style.bg_color=style.bg_color.darkened(.18)
		if key=="RUN":style.bg_color=Color("068f84") if campus_style else Color("408873")
		if key in ["DEL","AC"]:style.bg_color=Color("a94749") if campus_style else Color("925d52")
		if key_colors.has(key):style.bg_color=Color(key_colors[key])
		style.bg_color*=material_tint
		if campus_style:
			style.border_color=style.bg_color.lightened(.14)
			style.set_border_width_all(1)
		style.set_corner_radius_all(20 if round_keys else 6);button.add_theme_stylebox_override("normal",style);var hover: StyleBoxFlat=style.duplicate();hover.bg_color=hover.bg_color.lightened(.15);button.add_theme_stylebox_override("hover",hover);button.add_theme_stylebox_override("pressed",hover)
		if style.bg_color.get_luminance()>.45:
			for state in ["font_color","font_hover_color","font_pressed_color"]:button.add_theme_color_override(state,Color("192934"))
		button.pressed.connect(func():_schedule(press.bind(key)));grid.add_child(button)
func _schedule(action: Callable) -> void:
	if not is_instance_valid(performance) or performance.quality==performance.MAX:
		action.call()
		return
	if not is_instance_valid(busy_label):
		busy_label=Label.new()
		busy_label.text="Processing…"
		busy_label.theme_type_variation="MutedLabel"
		var body:=get_child(0)
		body.add_child(busy_label)
		body.move_child(busy_label,1)
	if performance.submit(func():
		if not is_instance_valid(self) or not is_inside_tree():return
		queued_controls-=1
		busy_label.visible=queued_controls>0
		action.call()):
		queued_controls+=1
		busy_label.show()

static func keypad_keys(model_id: String) -> Array:
	return Equipment.Keypad.keys(model_id)

func press(key: String) -> void:
	if (model=="calculator_financial" or configured) and Finance.ARGUMENTS.has(key):
		pending_operator=""
		display.text=key+"("
		if not equation_enabled:display.caret_column=display.text.length()
		if is_instance_valid(finance_help):
			finance_help.text=key+" · "+Finance.ARGUMENTS[key]
			finance_help.tooltip_text=finance_help.text
		return
	if _number_mode() and (not _finance_input() or key=="AC"):
		_press_number(key)
		return
	if equation_enabled:display.grab_focus()
	match key:
		"RUN":evaluate()
		"Equality","=":
			if equation_enabled:_insert("=")
			else:evaluate()
		"AC":
			display.text=""
			result.text="0"
			pending_operator=""
			if equation_enabled:
				result.hide()
				result_equation.hide()
				_refresh_isolation()
		"←","→":
			if equation_enabled:display.move_horizontal(-1 if key=="←" else 1)
		"↑","↓":
			if equation_enabled:display.move_vertical(-1 if key=="↑" else 1)
		"DEL":
			if equation_enabled:
				display.delete_at_caret(true,true)
			else:
				var caret: int=display.caret_column
				if caret>0:display.text=display.text.left(caret-1)+display.text.substr(caret);display.caret_column=caret-1
		"Convert":evaluate("convert")
		"∫":evaluate("integrate")
		"d/dx":evaluate("differentiate")
		"Factor":evaluate("factor")
		"MC":memory=0
		"MR":_insert(str(memory))
		"M+","M−":
			if evaluate():memory+=answer*(1 if key=="M+" else -1)
		"Ans":
			if equation_enabled:display.insert_expression_at_caret(answer_source)
			else:_insert(str(answer))
		"±":
			display.text="-("+display.text+")"
			if not equation_enabled:display.caret_column=display.text.length()
		"sin","cos","tan","asin","acos","atan","ln","log":_insert(key+"(")
		"√":_insert("√" if equation_enabled else "sqrt(")
		"x²":_insert_completed_field("^2")
		"xʸ":_insert("^")
		"ⁿ√":_insert("ⁿ√")
		"1/x","⁻¹":
			display.text="1/("+display.text+")"
			if not equation_enabled:display.caret_column=display.text.length()
		"%":_insert_completed_field("/100") if equation_enabled else _divide_percent()
		_:_insert({"×":"*","÷":"/","−":"-"}.get(key,key))
	memory_label.visible=memory!=0

func _number_mode() -> bool:
	return configured and not equation_enabled

func _finance_input() -> bool:
	return "(" in display.text and Finance.ARGUMENTS.has(display.text.get_slice("(",0).to_upper())

func _number_keyboard_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed or _finance_input():
		return
	var character:=String.chr(event.unicode) if event.unicode>=32 else ""
	var key: String={"*":"×","/":"÷","-":"−"}.get(character,character)
	if event.keycode==KEY_BACKSPACE:
		key="DEL"
	elif event.keycode==KEY_DELETE:
		if replace_number:
			display.accept_event()
		return
	if key in ["+","−","×","÷",".","=","DEL"] or (key.length()==1 and key.is_valid_int()):
		display.accept_event()
		_schedule(press.bind(key))
	elif not character.is_empty():
		display.accept_event()

func _press_number(key: String) -> void:
	if key.length()==1 and (key.is_valid_int() or key=="."):
		if replace_number:
			_set_number_text("")
		replace_number=false
		if key==".":
			var remaining: String=display.text
			if display.has_selection():
				var from: int=display.get_selection_from_column()
				remaining=remaining.left(from)+remaining.substr(display.get_selection_to_column())
			if "." in remaining or "e" in remaining.to_lower():return
			if remaining.is_empty():key="0."
		_insert(key)
	elif key in ["+","−","-","×","÷"]:
		if (pending_operator.is_empty() or not replace_number) and not _evaluate_number():
			return
		pending_number=answer
		pending_operator="−" if key=="-" else key
		_show_pending_number()
	else:
		match key:
			"RUN","=":
				if pending_operator.is_empty() or not replace_number:_evaluate_number()
				return
			"AC":
				answer=0.0
				pending_number=0.0
				pending_operator=""
				replace_number=true
				_set_number_text("")
			"DEL":
				if not pending_operator.is_empty() and replace_number:return
				if display.has_selection():
					display.delete_text(display.get_selection_from_column(),display.get_selection_to_column())
				elif display.caret_column>0:
					var column: int=display.caret_column
					display.delete_text(column-1,column)
					display.caret_column=column-1
				replace_number=false
			"±","%":
				var current:=_current_number()
				if is_finite(current):_enter_number(-current if key=="±" else current*.01)
			"Ans":_enter_number(answer)
			"MC":memory=0.0
			"MR":_enter_number(memory)
			"M+","M−":
				var current:=_current_number()
				if is_finite(current):memory+=current*(1 if key=="M+" else -1)
		memory_label.visible=memory!=0
		_show_pending_number()

func _current_number() -> float:
	var entered: String=display.text.strip_edges()
	if entered.is_empty():return 0.0
	return float(entered) if entered.is_valid_float() else NAN

func _set_number_text(value: String) -> void:
	display.text=value
	display.caret_column=value.length()

func _enter_number(value: float) -> void:
	_set_number_text(str(value))
	replace_number=false

func _show_pending_number() -> void:
	var expression:="" if pending_operator.is_empty() else "%s %s"%[pending_number,pending_operator]
	_display_calculation({"text":expression})

func _evaluate_number() -> bool:
	if not pending_operator.is_empty() and replace_number:return true
	var value:=_current_number()
	if not is_finite(value):
		return _display_calculation({"error":"Enter a valid number."})
	match pending_operator:
		"+":value=pending_number+value
		"−":value=pending_number-value
		"×":value=pending_number*value
		"÷":
			if value==0.0:return _display_calculation({"error":"Cannot divide by zero."})
			value=pending_number/value
	if not is_finite(value):return _display_calculation({"error":"Result out of range."})
	answer=value
	pending_operator=""
	replace_number=true
	_set_number_text(str(value))
	_show_pending_number()
	return true

func _insert(value: String) -> void:
	display.insert_text_at_caret(value)
func _insert_completed_field(value: String) -> void:
	var previous_depth: int=display.path.size() if equation_enabled else 0
	_insert(value)
	if equation_enabled and display.path.size()>previous_depth:display.move_horizontal(1)

func _divide_percent() -> void:
	if display.text.is_valid_float():display.text=str(float(display.text)*.01)

func _display_calculation(outcome: Dictionary) -> bool:
	var message:=str(outcome.get("text",outcome.get("error","Math error")))
	var successful:=not outcome.has("error")
	result.text=message
	result.tooltip_text=message
	result.theme_type_variation="Label" if successful else "ErrorLabel"
	if outcome.has("real"):answer=float(outcome.real)
	if is_instance_valid(result_equation):
		var source:=str(outcome.get("answer",message))
		if successful and not source.is_empty() and source not in ["True","False"] and not source.begins_with("No ") and not source.begins_with("All ") and not "," in source and Parser.new().parse(source).ok:
			answer_source=source
		var show_formula:=successful and not message.is_empty() and message not in ["True","False"] and not message.begins_with("No ") and not message.begins_with("All ")
		result.visible=not show_formula
		result_equation.visible=show_formula
		if show_formula:result_equation.set_expression(message)
	return successful

func _refresh_isolation() -> void:
	if not is_instance_valid(isolate_picker):return
	var variables: Array[String]=[]
	if "=" in display.text:
		var parsed: Dictionary=Parser.new().parse(close_parentheses(display.text))
		if parsed.ok and parsed.tree.op=="=":
			_collect_variables(parsed.tree,variables)
	variables.sort()
	var previous:=str(isolate_picker.get_selected_metadata()) if isolate_picker.selected>=0 else ""
	isolate_picker.clear()
	isolate_picker.visible=variables.size()>1
	if not isolate_picker.visible:return
	for variable in variables:
		isolate_picker.add_item("Isolate "+variable)
		isolate_picker.set_item_metadata(isolate_picker.item_count-1,variable)
	isolate_picker.select(maxi(0,variables.find(previous)))

func _collect_variables(node: Dictionary, variables: Array[String]) -> void:
	if node.get("op")=="atom" and node.text in ["x","y","z"] and node.text not in variables:
		variables.append(node.text)
	for branch in ["left","right","child"]:
		if node.get(branch) is Dictionary:
			_collect_variables(node[branch],variables)

func evaluate(action := "auto") -> bool:
	if _number_mode() and not _finance_input():return _evaluate_number()
	var input:=close_parentheses(display.text)
	if equation_enabled and "□" in input:
		return _display_calculation({"error":"Fill in the empty part of the equation."})
	if not equation_enabled:
		display.text=input
		display.caret_column=input.length()
	if (configured or advanced_app) and Finance.ARGUMENTS.has(input.get_slice("(",0).to_upper()):
		var operation_name:=input.get_slice("(",0).to_upper()
		var financial_result:=Finance.evaluate(operation_name,input.substr(input.find("(")+1).trim_suffix(")"))
		if financial_result.get("ok",false):
			if _number_mode():
				_enter_number(float(financial_result.value))
				return _evaluate_number()
			return _display_calculation({"real":financial_result.value,"text":str(financial_result.value)})
		return _display_calculation({"error":financial_result.get("error","Math error")})
	if equation_enabled or algebra_enabled:
		var expression: Dictionary=Parser.new().parse(input)
		if action=="auto":
			_refresh_isolation()
			if not algebra_enabled:action="evaluate"
			elif isolate_picker.visible:action="isolate:"+str(isolate_picker.get_selected_metadata())
		return _display_calculation(math_engine.Calculate(expression.tree,action,complex_enabled,"rad") if expression.ok else {"error":expression.error})
	var legacy := calculate(input,false,"rad") if model=="calculator" else _limited_calculate(input)
	if not legacy.ok:
		result.text=legacy.error;result.tooltip_text=str(legacy.error);display.theme_type_variation="ErrorLineEdit";return false
	display.theme_type_variation="LineEdit";result.tooltip_text="Calculated result"
	answer=legacy.value;result.text=str(snappedf(answer,.000000001))
	return true

func _limited_calculate(input: String) -> Dictionary:
	var text := input.strip_edges()
	var operation := text.get_slice("(",0).to_upper()
	if model=="calculator_financial" and Finance.ARGUMENTS.has(operation) and text.contains("("):
		return Finance.evaluate(operation,text.substr(text.find("(")+1).trim_suffix(")"))
	var allowed := "0123456789.+-*/ ()" if model=="calculator_financial" else "0123456789.+-*/ "
	for character in text:
		if character not in allowed:return {"ok":false,"error":"Use +, −, × or ÷"}
	if text.contains("**"):return {"ok":false,"error":"Use +, −, × or ÷"}
	return calculate(text)
func _action(title: String,callback: Callable) -> Button:
	var button:=Button.new()
	button.text=title
	button.pressed.connect(func():_schedule(callback))
	return button

func _build_graph(body: VBoxContainer) -> void:
	functions=VBoxContainer.new()
	body.add_child(functions)
	functions.hide()
	var mode_choice:=OptionButton.new()
	for name_text in ["2D grid","Polar grid","3D graph"].slice(0,3 if graph_level==2 else 2):mode_choice.add_item(name_text)
	functions.add_child(mode_choice)
	var expressions:=TextEdit.new()
	expressions.placeholder_text="Enter one equation per line, up to six."
	expressions.custom_minimum_size.y=64
	functions.add_child(expressions)
	graph=Graph.new()
	functions.add_child(graph)
	var measurements:=HBoxContainer.new()
	functions.add_child(measurements)
	var a:=SpinBox.new()
	var b:=SpinBox.new()
	for value in [a,b]:
		value.min_value=-100
		value.max_value=100
		value.step=.01
		value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		measurements.add_child(value)
	a.prefix="From x "
	b.prefix="To x "
	b.value=1.0
	var selected_curve:=OptionButton.new()
	selected_curve.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	functions.add_child(selected_curve)
	var feedback:=Label.new()
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var trees: Array[Dictionary]=[]
	var plot:=func():
		trees.clear()
		selected_curve.clear()
		graph.kind=mode_choice.selected
		graph.data.clear()
		feedback.text=""
		for line in expressions.text.split("\n",false).slice(0,6):
			var parsed: Dictionary=Parser.new().parse(line)
			if not parsed.ok:
				feedback.text=parsed.error
				continue
			var points: PackedVector3Array=math_engine.Curve(parsed.tree,graph.kind,"rad",graph.extent)
			if points.is_empty() or not Array(points).any(func(point: Vector3):return point.is_finite()):
				feedback.text="No real values to plot for "+line
				continue
			trees.append(parsed.tree)
			selected_curve.add_item(line)
			graph.data.append(points)
		graph.queue_redraw()
	mode_choice.item_selected.connect(func(_index):plot.call())
	mode_choice.item_selected.connect(func(index: int):
		expressions.placeholder_text="Enter one equation per line, up to six. Example: z = x^2 + y^2" if index==2 else "Enter one equation per line, up to six.")
	var actions:=HBoxContainer.new()
	functions.add_child(actions)
	actions.add_child(_action("Plot",plot))
	actions.add_child(_action("Use entry",func():
		if not display.text.strip_edges().is_empty():
			expressions.text+="\n"+display.text if not expressions.text.is_empty() else display.text
			plot.call()))
	for measure in ["Slope at x","Area over range"]:
		var slope: bool=measure.begins_with("Slope")
		actions.add_child(_action(measure,func():
			if selected_curve.selected not in range(trees.size()):return
			if graph.kind!=0:
				feedback.text="Slope and area use a curve on the 2D grid."
				return
			var value: Dictionary=math_engine.Measure(trees[selected_curve.selected],a.value,b.value,"rad",slope)
			feedback.text=str(value.get("text",value.get("error","Calculation failed.")))))
	functions.add_child(feedback)

static func _functions(text: String,angle_system: String) -> String:
	var output := "";var i := 0
	while i<text.length():
		if text[i]>="a" and text[i]<="z":
			var start := i
			while i<text.length() and text[i]>="a" and text[i]<="z":i+=1
			var name := text.substr(start,i-start)
			if i<text.length() and text[i]=="(":
				var depth := 1;var arg_start := i+1;i+=1
				while i<text.length() and depth>0:
					if text[i]=="(":depth+=1
					elif text[i]==")":depth-=1
					if depth>0:i+=1
				if depth!=0:return "!"
				var argument := _functions(text.substr(arg_start,i-arg_start),angle_system);i+=1
				if name in ["sin","cos","tan"] and angle_system!="rad":argument="("+argument+")*pi/"+("180.0" if angle_system=="deg" else "200.0")
				var call_text := ("log" if name in ["ln","log"] else name)+"("+argument+")"
				if name=="log":call_text="("+call_text+"/log(10.0))"
				if name in ["asin","acos","atan"] and angle_system!="rad":call_text="("+call_text+"*"+("180.0" if angle_system=="deg" else "200.0")+"/pi)"
				output+=call_text
			else:output+=name
		else:output+=text[i];i+=1
	return output
static func close_parentheses(value: String) -> String:
	var balance := 0
	for character in value:
		if character=="(":balance+=1
		elif character==")":balance-=1
		if balance<0:return value
	return value+")".repeat(mini(balance,90))
static func calculate(value: String,degrees_mode := true,angle_system := "") -> Dictionary:
	if value.length()>180 or value.is_empty():return {"ok":false,"error":"Enter a calculation"}
	if "ⁿ√" in value or "°" in value:
		var parsed:=Parser.new().parse(close_parentheses(value))
		if not parsed.ok:return {"ok":false,"error":parsed.error}
		var angles:=angle_system if angle_system in ["deg","rad","grad"] else ("deg" if degrees_mode else "rad")
		var root_result: Dictionary=MathEngine.new().Calculate(parsed.tree,"evaluate",false,angles)
		return {"ok":false,"error":root_result.error} if root_result.has("error") else {"ok":true,"value":root_result.real}
	var safe := close_parentheses(value).to_lower().replace(" ","").replace("π","pi").replace("τ","tau").replace("φ","phi")
	var depth := 0
	for character in safe:
		if character=="(":depth+=1
		elif character==")":depth-=1
		if depth<0:return {"ok":false,"error":"Check brackets"}
	if safe.contains("()"):return {"ok":false,"error":"Enter a value"}
	var scientific := RegEx.new();scientific.compile("([0-9]+(?:\\.[0-9]*)?)[e]([+-]?[0-9]+)");safe=scientific.sub(safe,"($1*10^($2))",true)
	var words := RegEx.new();words.compile("[a-z_][a-z_0-9]*")
	var constants:={"pi":"3.141592653589793","e":"2.718281828459045","tau":"6.283185307179586","phi":"1.618033988749895"}
	for word in words.search_all(safe):
		if word.get_string() not in ["pi","e","tau","phi","sqrt","sin","cos","tan","asin","acos","atan","abs","pow","log","ln","exp"]:return {"ok":false,"error":"Invalid function"}
	safe=_functions(safe,angle_system if angle_system in ["deg","rad","grad"] else ("deg" if degrees_mode else "rad")).replace("^","**")
	var tokens:=words.search_all(safe)
	tokens.reverse()
	for word in tokens:
		if constants.has(word.get_string()):
			safe=safe.substr(0,word.get_start())+constants[word.get_string()]+safe.substr(word.get_end())
	var allowed := RegEx.new();allowed.compile("^[0-9a-z+*/().,_-]+$")
	if not allowed.search(safe):return {"ok":false,"error":"Check brackets"}
	# Force decimal arithmetic: 1/2 should be 0.5, not integer division.
	var integers := RegEx.new();integers.compile("(?<![.0-9a-z])([0-9]+)(?![.0-9])")
	safe=integers.sub(safe,"$1.0",true)
	var expression := Expression.new()
	if expression.parse(safe)!=OK:return {"ok":false,"error":"Syntax error"}
	var answer_value=expression.execute([],null,false,true)
	if expression.has_execute_failed() or not (answer_value is float or answer_value is int) or not is_finite(float(answer_value)):return {"ok":false,"error":"Math error"}
	return {"ok":true,"value":float(answer_value)}
