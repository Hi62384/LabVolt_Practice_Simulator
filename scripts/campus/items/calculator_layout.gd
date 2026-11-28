extends RefCounted

const MODELS := ["calculator_basic","calculator","calculator_financial"]
const REQUIRED := ["7","8","9","4","5","6","1","2","3","0","RUN","AC"]
const NUMERIC_PAD := ["7","8","9","4","5","6","1","2","3","0","."]
const CURSOR_KEYS := ["←","→","↑","↓"]
const OPTIONAL := ["Ans","±","ⁿ√"]
const ARITHMETIC := ["7","8","9","÷","4","5","6","×","1","2","3","−","0",".","RUN","+","AC","DEL"]
const SCIENTIFIC := ["°","MC","MR","M+","M−","sin","cos","tan","(",")","asin","acos","atan","ln","log","√","x²","xʸ","ⁿ√","1/x","π","7","8","9","DEL","AC","4","5","6","×","÷","1","2","3","+","−","0",".","±","Ans","RUN"]
const FINANCIAL := ["N","I%","PV","PMT","FV","NPV","IRR","EFF","NOM","%CHG","MU","MAR","SL","BEP",",","7","8","9","÷","DEL","4","5","6","×","AC","1","2","3","−","(","0",".","RUN","+",")"]

static func keys(model: String) -> Array:
	if model=="calculator_basic":return ARITHMETIC.duplicate()
	if model=="calculator_financial":return FINANCIAL.duplicate()
	return SCIENTIFIC+CURSOR_KEYS

static func model_for(item: String) -> String:
	var model := item.get_slice(":",0)
	if model not in MODELS:return ""
	if item==model:return model
	var uid := item.trim_prefix(model+":")
	return model if uid.length()==32 and uid==uid.to_lower() and not uid.begins_with("-") and uid.is_valid_hex_number(false) else ""

static func valid(model: String, layout: Variant) -> bool:
	if layout is Array:layout=updated_keys(layout)
	var supported := keys(model)
	if not layout is Array or layout.size()>supported.size():return false
	var seen := {}
	for key in layout:
		if not key is String or key not in supported or seen.has(key):return false
		seen[key]=true
	for key in supported:
		if key not in OPTIONAL and key not in CURSOR_KEYS and not seen.has(key):return false
	return true

static func available() -> Array:
	var catalog:=keys("calculator")
	for key in FINANCIAL+["e","τ","φ","x","y","z","i","%","⁻¹","Equality","∠","Convert","∫","d/dx","Factor"]:
		if key not in catalog:catalog.append(key)
	return catalog

static func valid_custom(layout: Variant) -> bool:
	if layout is Array:layout=updated_keys(layout)
	if not layout is Array or layout.filter(func(key):return key not in REQUIRED).size()>36:return false
	var supported:=available()
	var seen:={}
	for key in layout:
		if not key is String or key not in supported or seen.has(key):return false
		seen[key]=true
	return true

static func with_required(layout: Array) -> Array:
	var normalized := updated_keys(layout)
	for key in REQUIRED:
		if key not in normalized:normalized.append(key)
	return normalized

static func updated_keys(layout: Array) -> Array:
	var updated:=layout.duplicate()
	if "=" in updated:updated[updated.find("=")]="RUN"
	if "DEG" in updated:updated[updated.find("DEG")]="" if "°" in updated else "°"
	return updated

static func caption(symbol: String) -> String:
	return {"Equality":"=","x":"𝑥"}.get(symbol,symbol)

static func clean_colors(raw: Variant, layout: Array) -> Variant:
	if not raw is Dictionary or raw.size()>SLOTS:return null
	var colors:={}
	for key in raw:
		var hex: Variant=raw[key]
		if not key is String or key.is_empty() or key not in layout or not hex is String or hex.length()!=6 or not Color.html_is_valid(hex):return null
		colors[key]=hex.to_lower()
	return colors

const SLOTS := 70
const COLUMNS := 7
const PREVIOUS_SLOTS := 49
const LEGACY_SLOTS := 36
const LEGACY_COLUMNS := 6
const WIDE_KEYS := ["asin","acos","atan","d/dx","Factor","Convert","%CHG"]
const CATEGORIES := ["Numbers and decimal","Basic arithmetic","Calculation controls","Memory","Powers and roots","Trigonometry","Logarithms","Constants","Algebra and variables","Complex numbers","Financial functions","Other supported functions"]
# Name, description, example, category index, price, required hardware.
const BUTTONS := {
	".":["Decimal point","Enter the fractional part of a number.","1.25",0,1,""],
	"+":["Addition","Add two values.","2 + 3 = 5",1,2,""],
	"−":["Subtraction","Find the difference between two values.","7 − 4 = 3",1,2,""],
	"×":["Multiplication","Multiply two values.","4 × 3 = 12",1,3,""],
	"÷":["Division","Divide a value by another.","12 ÷ 3 = 4",1,3,""],
	"RUN":["Run","Evaluate an expression or solve an equation.","5x + 4 = 2x",2,2,""],
	"Equality":["Equals sign","Enter an equality to solve with RUN.","5x + 4 = 2x",8,2,"algebra"],
	"AC":["All clear","Clear the input, result, and pending operation.","AC clears 42",2,1,""],
	"DEL":["Delete","Remove the character before the cursor.","123 → 12",2,1,""],
	"←":["Move cursor left","Move left through the equation and its fields.","Move into a fraction or exponent",2,1,"equation"],
	"→":["Move cursor right","Move right through the equation and its fields.","Leave a fraction or exponent to continue",2,1,"equation"],
	"↑":["Move cursor up","Move to the numerator, exponent, or root degree.","Denominator → numerator",2,1,"equation"],
	"↓":["Move cursor down","Move to the denominator, base, or radicand.","Numerator → denominator",2,1,"equation"],
	"(":[ "Open parenthesis","Start a grouped expression.","(2 + 4) × 3",2,2,"equation"],
	")":[ "Close parenthesis","End a grouped expression.","(2 + 4) × 3",2,2,"equation"],
	"±":["Change sign","Change a positive number to negative or the reverse.","5 → −5",2,2,""],
	"%":["Percentage","Divide a value by 100.","25% = 0.25",2,3,""],
	"Ans":["Previous answer","Insert the last successful result.","Ans × 2",2,4,""],
	"MC":["Memory clear","Reset the stored value to zero.","MC clears memory",3,4,""],
	"MR":["Memory recall","Insert the stored value.","MR + 4",3,4,""],
	"M+":["Memory add","Add the current result to memory.","12 M+ stores 12",3,6,""],
	"M−":["Memory subtract","Subtract the current result from memory.","12 M− subtracts 12",3,6,""],
	"x²":["Square","Raise a value to the second power.","5² = 25",4,4,"equation"],
	"√":["Square root","Find the principal square root.","√(81) = 9",4,5,"equation"],
	"1/x":["Reciprocal","Divide one by the current value.","1/4 = 0.25",4,5,"equation"],
	"⁻¹":["Inverse power","Raise a value to the power of negative one.","4⁻¹ = 0.25",4,5,"equation"],
	"xʸ":["General exponent","Raise a value to a chosen power.","2³ = 8",4,7,"equation"],
	"ⁿ√":["Nth root","Press ⁿ√, enter the degree, then press → or ↓ to enter the number under the root. You can also enter that number first.","ⁿ√ 3 → 27 = 3",4,7,"equation"],
	"sin":["Sine","Find the sine of an angle.","sin(30°) = 0.5",5,6,"equation"],
	"cos":["Cosine","Find the cosine of an angle.","cos(60°) = 0.5",5,6,"equation"],
	"tan":["Tangent","Find the tangent of an angle.","tan(45°) = 1",5,6,"equation"],
	"asin":["Inverse sine","Find the angle in radians with the given sine.","asin(0.5) = π/6",5,8,"equation"],
	"acos":["Inverse cosine","Find the angle in radians with the given cosine.","acos(0.5) = π/3",5,8,"equation"],
	"atan":["Inverse tangent","Find the angle in radians with the given tangent.","atan(1) = π/4",5,8,"equation"],
	"°":["Degrees","Mark an angle in degrees. Unmarked angles are radians.","sin(30°) = 0.5",5,4,"equation"],
	"log":["Common logarithm","Find the base-ten logarithm.","log(1000) = 3",6,7,"equation"],
	"ln":["Natural logarithm","Find the logarithm to base e.","ln(1) = 0",6,7,"equation"],
	"π":["Pi","Insert the ratio of circumference to diameter.","2 × π ≈ 6.283",7,3,"equation"],
	"e":["Euler’s number","Insert the base of the natural logarithm.","ln(e) = 1",7,3,"equation"],
	"τ":["Tau","Insert the radians in one complete turn.","τ = 2 × π",7,3,"equation"],
	"φ":["Golden ratio","Insert the ratio (1 + √5) ÷ 2.","φ² = φ + 1",7,3,"equation"],
	"x":["Variable x","Insert the main symbolic variable.","x + 4 = 10",8,5,"algebra"],
	"y":["Variable y","Enter y in an equation or graph.","x² + y²",8,5,"algebra"],
	"z":["Variable z","Enter z in an equation or graph.","z = x² + y²",8,5,"algebra"],
	"∫":["Integrate symbolically","Find an antiderivative.","∫ x² → x³/3",8,6,"algebra"],
	"d/dx":["Differentiate","Find the symbolic derivative.","d/dx x² → 2x",8,6,"algebra"],
	"Factor":["Factor","Write the expression as a product using supported factors.","x² − 9 → (x − 3)(x + 3)",8,6,"algebra"],
	"i":["Imaginary unit","Insert the square root of negative one.","i² = −1",9,8,"complex"],
	"∠":["Polar angle","Enter magnitude followed by angle. Add ° for degrees.","5∠30°",9,3,"complex"],
	"Convert":["Convert complex number","Convert one number between rectangular and polar form.","3 + 4i → 5∠0.9273",9,5,"complex"],
	"N":["Number of periods","Find how long payments or growth take.","N(1, −100, 1000, 0)",10,10,""],
	"I%":["Interest rate","Solve for the interest rate per period.","I%(12, −100, 1100, 0)",10,12,""],
	"PV":["Present value","Find today's value of a future amount.","PV(5, 2, 1100)",10,9,""],
	"PMT":["Periodic payment","Find the payment amount per period.","PMT(1, 12, 1000)",10,10,""],
	"FV":["Future value","Find the accumulated value after growth.","FV(5, 2, 1000)",10,9,""],
	"NPV":["Net present value","Discount and sum a series of cash flows.","NPV(5, −100, 60, 60)",10,15,""],
	"IRR":["Internal rate of return","Find the rate where net present value is zero.","IRR(−100, 60, 60)",10,18,""],
	"EFF":["Effective annual rate","Convert a nominal rate to an effective rate.","EFF(6, 12)",10,12,""],
	"NOM":["Nominal annual rate","Convert an effective rate to a nominal rate.","NOM(6, 12)",10,12,""],
	"%CHG":["Percentage change","Find the relative change between values.","%CHG(50, 60) = 20",10,8,""],
	"MU":["Markup","Find profit as a share of cost.","MU(80, 100) = 25",10,8,""],
	"MAR":["Margin","Find profit as a share of selling price.","MAR(80, 100) = 20",10,8,""],
	"SL":["Straight-line depreciation","Find the depreciation per period.","SL(1000, 100, 3) = 300",10,12,""],
	"BEP":["Break-even point","Find the units needed to cover fixed costs.","BEP(100, 10, 5) = 20",10,12,""],
	",":["Argument separator","Separate arguments in financial functions.","PV(5, 2, 1100)",10,1,""],
}
const CAPABILITIES := {"equation":"Equation entry","algebra":"Symbolic algebra","complex":"Complex numbers","graph":"Graphing"}

static func catalog(symbol: String) -> Dictionary:
	if symbol.length()==1 and symbol.is_valid_int():
		return {"name":"Digit "+symbol,"description":"Enter "+symbol+" in the current number.","example":symbol+"7","category":0,"price":1,"requires":""}
	if not BUTTONS.has(symbol):return {}
	var record: Array=BUTTONS[symbol]
	return {"name":record[0],"description":record[1],"example":record[2],"category":record[3],"price":record[4],"requires":record[5]}

static func unlocked(symbol: String, hardware: Dictionary) -> bool:
	var requirement: String=catalog(symbol).get("requires","")
	if requirement.is_empty():return true
	return int(hardware.get(requirement,0))>=1

static func occupied_rows(layout: Array,columns: int) -> int:
	for index in range(layout.size()-1,-1,-1):
		if not str(layout[index]).is_empty():return ceili(float(index+1)/columns)
	return 0

static func design_columns(layout: Array) -> int:
	return LEGACY_COLUMNS if layout.size()==LEGACY_SLOTS else COLUMNS

static func span(symbol: String) -> int:
	return 2 if symbol in WIDE_KEYS else 1

static func spans_fit(layout: Array, columns: int) -> bool:
	for index in layout.size():
		if layout[index] is String and span(layout[index])==2:
			if index%columns==columns-1 or index+1>=layout.size() or layout[index+1]!="":return false
	return true

static func continuation(layout: Array, index: int, columns: int) -> bool:
	return index%columns!=0 and span(layout[index-1])==2

static func pack(keys: Array, columns: int) -> Array:
	var layout: Array=[]
	for key in keys:
		if key=="":continue
		if span(key)==2 and layout.size()%columns==columns-1:layout.append("")
		layout.append(key)
		if span(key)==2:layout.append("")
	return layout

static func display_slots(raw: Array, columns: int, spatial: bool) -> Array:
	var layout:=updated_keys(raw)
	return layout if spatial and spans_fit(layout,columns) else pack(layout,columns)

static func designer_slots(raw: Array) -> Array:
	var layout:=updated_keys(raw)
	if raw.size()==LEGACY_SLOTS:
		for row in range(int(LEGACY_SLOTS/LEGACY_COLUMNS)-1,-1,-1):
			layout.insert((row+1)*LEGACY_COLUMNS,"")
	if not spans_fit(layout,COLUMNS):layout=pack(layout,COLUMNS)
	return new_slots(layout)

static func new_slots(keys: Array) -> Array:
	var layout:=keys.duplicate()
	while layout.size()<SLOTS:layout.append("")
	return layout

static func default_slots() -> Array:
	var layout:=new_slots([])
	var positions:={0:"7",1:"8",2:"9",6:"AC",7:"4",8:"5",9:"6",14:"1",15:"2",16:"3",21:"0",23:"RUN"}
	for index in positions:layout[index]=positions[index]
	return layout

static func design_price(layout: Variant, hardware: Dictionary) -> int:
	if not layout is Array or layout.size() not in [LEGACY_SLOTS,PREVIOUS_SLOTS,SLOTS]:return -1
	if layout.size()==SLOTS and not spans_fit(layout,COLUMNS):return -1
	var price:=0
	var seen:={}
	for symbol in updated_keys(layout):
		if not symbol is String:return -1
		if symbol.is_empty():continue
		var data:=catalog(symbol)
		if data.is_empty() or seen.has(symbol) or not unlocked(symbol,hardware):return -1
		price+=int(data.price)
		seen[symbol]=true
	return price

static func preset(name: String) -> Dictionary:
	var hardware:={"equation":0,"algebra":0,"complex":0,"graph":0}
	var keys: Array=ARITHMETIC.duplicate()
	match name:
		"Basic":
			var layout:=default_slots()
			var operations:={3:"÷",10:"×",13:"DEL",17:"−",22:".",24:"+"}
			for index in operations:layout[index]=operations[index]
			return {"keypad":layout,"hardware":hardware}
		"Scientific":
			hardware.equation=1
			keys=SCIENTIFIC.filter(func(symbol):return symbol not in ["MC","MR","M+","M−"])
		"Financial":
			hardware.equation=1
			keys=FINANCIAL.duplicate()
		"Algebra":
			hardware.equation=1
			hardware.algebra=1
			hardware.complex=1
			keys.append_array(["(",")","x","i","x²","xʸ","ⁿ√","√","±","Ans","π","Equality","y","z","°","∠","Convert","∫","d/dx","Factor"])
		"Graphing":
			hardware.equation=1
			hardware.algebra=1
			hardware.graph=2
			keys.append_array(["(",")","x","y","z","x²","xʸ","ⁿ√","√","±","sin","cos","tan","π","°","Equality","∫","d/dx","Factor"])
	return {"keypad":new_slots(pack(keys,COLUMNS)),"hardware":hardware}
