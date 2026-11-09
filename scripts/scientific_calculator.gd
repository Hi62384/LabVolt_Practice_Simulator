extends PanelContainer
signal close_requested
const Supplies = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Finance = preload("res://scripts/financial_calculator.gd")
var finance_help: Label
var model := "calculator"
var show_close := false
var display: LineEdit
var result: Label
var mode: Button
var degrees := true
var answer := 0.0
var memory := 0.0
var memory_label: Label
func _ready() -> void:
	theme=preload("res://scripts/ui/design_system/theme.gd").create()
	var basic := model=="calculator_basic"
	var financial := model=="calculator_financial"
	custom_minimum_size.x=260 if basic else 280
	var shell := StyleBoxFlat.new();shell.bg_color=Color("15171a") if basic else Color("39473c") if financial else Color("29333e");shell.set_corner_radius_all(18);shell.set_content_margin_all(12);add_theme_stylebox_override("panel",shell)
	var body := VBoxContainer.new();body.add_theme_constant_override("separation",6);add_child(body)
	var header := HBoxContainer.new();body.add_child(header)
	var brand := Label.new();brand.text=Supplies.TOOLS.get(model,"Scientific calculator");brand.add_theme_font_size_override("font_size",16);header.add_child(brand)
	brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if show_close:
		var close := preload("res://scripts/ui/design_system/widgets.gd").action("Close","close",func():close_requested.emit())
		header.add_child(close)
	var lcd := PanelContainer.new();var lcd_style := StyleBoxFlat.new();lcd_style.bg_color=Color("d5dfcf");lcd_style.set_content_margin_all(10);lcd_style.set_corner_radius_all(5);lcd.add_theme_stylebox_override("panel",lcd_style);body.add_child(lcd)
	var lines := VBoxContainer.new();lcd.add_child(lines)
	memory_label=Label.new();memory_label.text="DEG";memory_label.visible=not basic and not financial;memory_label.add_theme_color_override("font_color",Color("385044"));memory_label.add_theme_font_size_override("font_size",12);lines.add_child(memory_label)
	display=LineEdit.new();display.placeholder_text="0";display.max_length=180;display.add_theme_font_size_override("font_size",18);display.add_theme_color_override("font_color",Color("162c24"));display.add_theme_color_override("font_placeholder_color",Color("617367"));display.add_theme_stylebox_override("normal",StyleBoxEmpty.new());display.add_theme_stylebox_override("focus",StyleBoxEmpty.new());display.text_submitted.connect(func(_text):evaluate());lines.add_child(display)
	result=Label.new();result.text="0";result.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;result.add_theme_font_size_override("font_size",21);result.add_theme_color_override("font_color",Color("162c24"));result.clip_text=true;lines.add_child(result)
	var grid := GridContainer.new();grid.columns=4 if basic else 5;grid.add_theme_constant_override("h_separation",6);grid.add_theme_constant_override("v_separation",4);body.add_child(grid)
	if basic or financial:grid.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var keys := keypad_keys(model)
	if financial:
		finance_help=Label.new()
		finance_help.text="Choose a finance key for its inputs"
		finance_help.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		finance_help.add_theme_font_size_override("font_size",12)
		body.add_child(finance_help)
		body.move_child(finance_help,2)
	for key in keys:
		var button := Button.new();button.text=key;button.custom_minimum_size=Vector2(44,32 if show_close else 40);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.add_theme_font_size_override("font_size",15);button.tooltip_text={"DEG":"Toggle degrees / radians","AC":"Clear expression","DEL":"Delete previous character","=":"Evaluate expression","MR":"Recall memory","MC":"Clear memory"}.get(key,key)
		if basic or financial:button.size_flags_vertical=Control.SIZE_EXPAND_FILL
		if financial and Finance.ARGUMENTS.has(key):button.tooltip_text=Finance.ARGUMENTS[key]
		var style := StyleBoxFlat.new();style.bg_color=Color("647781") if key.is_valid_int() or key=="." else Color("3e4b59")
		if key=="=":style.bg_color=Color("408873")
		if key in ["DEL","AC"]:style.bg_color=Color("925d52")
		style.set_corner_radius_all(6);button.add_theme_stylebox_override("normal",style);var hover: StyleBoxFlat=style.duplicate();hover.bg_color=hover.bg_color.lightened(.15);button.add_theme_stylebox_override("hover",hover);button.add_theme_stylebox_override("pressed",hover)
		button.pressed.connect(func():press(key));grid.add_child(button)
		if key=="DEG":mode=button
static func keypad_keys(model_id: String) -> Array:
	var arithmetic := ["7","8","9","÷","4","5","6","×","1","2","3","−","0",".","=","+"]
	return arithmetic+["AC","DEL"] if model_id=="calculator_basic" else ["N","I%","PV","PMT","FV",
		"NPV","IRR","EFF","NOM","%CHG",
		"MU","MAR","SL","BEP",",",
		"7","8","9","÷","DEL",
		"4","5","6","×","AC",
		"1","2","3","−","(",
		"0",".","=","+",")"] if model_id=="calculator_financial" else ["DEG","MC","MR","M+","M−","sin","cos","tan","(",")","asin","acos","atan","ln","log","√","x²","xʸ","1/x","π","7","8","9","DEL","AC","4","5","6","×","÷","1","2","3","+","−","0",".","±","Ans","="]

func press(key: String) -> void:
	if model=="calculator_financial" and Finance.ARGUMENTS.has(key):
		display.text=key+"("
		display.caret_column=display.text.length()
		finance_help.text=key+" · "+Finance.ARGUMENTS[key]
		finance_help.tooltip_text=finance_help.text
		return
	match key:
		"=":evaluate()
		"AC":display.text="";result.text="0"
		"DEL":
			var caret := display.caret_column
			if caret>0:display.text=display.text.left(caret-1)+display.text.substr(caret);display.caret_column=caret-1
		"DEG":degrees=not degrees;mode.text="DEG" if degrees else "RAD"
		"MC":memory=0
		"MR":_insert(str(memory))
		"M+","M−":
			if evaluate():memory+=answer*(1 if key=="M+" else -1)
		"Ans":_insert(str(answer))
		"±":display.text="-("+display.text+")";display.caret_column=display.text.length()
		"sin","cos","tan","asin","acos","atan","ln","log":_insert(key+"(")
		"√":_insert("sqrt(")
		"x²":_insert("^2")
		"xʸ":_insert("^")
		"1/x":display.text="1/("+display.text+")";display.caret_column=display.text.length()
		_:_insert({"×":"*","÷":"/","−":"-","π":"pi"}.get(key,key))
	memory_label.text=("DEG" if degrees else "RAD")+("   M" if memory!=0 else "")
func _insert(value: String) -> void:
	display.insert_text_at_caret(value)
func evaluate() -> bool:
	display.text=close_parentheses(display.text)
	display.caret_column=display.text.length()
	var value := calculate(display.text,degrees) if model=="calculator" else _limited_calculate(display.text)
	if not value.ok:
		result.text=value.error;result.tooltip_text=str(value.error);display.theme_type_variation="ErrorLineEdit";return false
	display.theme_type_variation="LineEdit";result.tooltip_text="Calculated result"
	answer=value.value;result.text=str(snappedf(answer,.000000001))
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
static func _functions(text: String,degrees_mode: bool) -> String:
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
				var argument := _functions(text.substr(arg_start,i-arg_start),degrees_mode);i+=1
				if name in ["sin","cos","tan"] and degrees_mode:argument="("+argument+")*pi/180.0"
				var call_text := ("log" if name in ["ln","log"] else name)+"("+argument+")"
				if name=="log":call_text="("+call_text+"/log(10.0))"
				if name in ["asin","acos","atan"] and degrees_mode:call_text="("+call_text+"*180.0/pi)"
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
static func calculate(value: String,degrees_mode := true) -> Dictionary:
	if value.length()>180 or value.is_empty():return {"ok":false,"error":"Enter a calculation"}
	var safe := close_parentheses(value).to_lower().replace(" ","")
	var depth := 0
	for character in safe:
		if character=="(":depth+=1
		elif character==")":depth-=1
		if depth<0:return {"ok":false,"error":"Check brackets"}
	if safe.contains("()"):return {"ok":false,"error":"Enter a value"}
	var scientific := RegEx.new();scientific.compile("([0-9]+(?:\\.[0-9]*)?)[e]([+-]?[0-9]+)");safe=scientific.sub(safe,"($1*10^($2))",true)
	var words := RegEx.new();words.compile("[a-z_][a-z_0-9]*")
	for word in words.search_all(safe):
		if word.get_string() not in ["pi","sqrt","sin","cos","tan","asin","acos","atan","abs","pow","log","ln","exp"]:return {"ok":false,"error":"Invalid function"}
	safe=_functions(safe,degrees_mode).replace("pi","3.141592653589793").replace("^","**")
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
