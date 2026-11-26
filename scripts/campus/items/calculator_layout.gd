extends RefCounted

const MODELS := ["calculator_basic","calculator","calculator_financial"]
const OPTIONAL := ["Ans","±"]
const ARITHMETIC := ["7","8","9","÷","4","5","6","×","1","2","3","−","0",".","=","+","AC","DEL"]
const SCIENTIFIC := ["DEG","MC","MR","M+","M−","sin","cos","tan","(",")","asin","acos","atan","ln","log","√","x²","xʸ","1/x","π","7","8","9","DEL","AC","4","5","6","×","÷","1","2","3","+","−","0",".","±","Ans","="]
const FINANCIAL := ["N","I%","PV","PMT","FV","NPV","IRR","EFF","NOM","%CHG","MU","MAR","SL","BEP",",","7","8","9","÷","DEL","4","5","6","×","AC","1","2","3","−","(","0",".","=","+",")"]

static func keys(model: String) -> Array:
	if model=="calculator_basic":return ARITHMETIC.duplicate()
	if model=="calculator_financial":return FINANCIAL.duplicate()
	return SCIENTIFIC.duplicate()

static func model_for(item: String) -> String:
	var model := item.get_slice(":",0)
	if model not in MODELS:return ""
	if item==model:return model
	var uid := item.trim_prefix(model+":")
	return model if uid.length()==32 and uid==uid.to_lower() and not uid.begins_with("-") and uid.is_valid_hex_number(false) else ""

static func valid(model: String, layout: Variant) -> bool:
	var supported := keys(model)
	if not layout is Array or layout.size()>supported.size():return false
	var seen := {}
	for key in layout:
		if not key is String or key not in supported or seen.has(key):return false
		seen[key]=true
	for key in supported:
		if key not in OPTIONAL and not seen.has(key):return false
	return true
