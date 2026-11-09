extends RefCounted
## Numeric fields inherit the printed unit when no suffix is supplied.
## Explicit suffixes must have the same physical dimension. All comparisons use SI.
const UNITS = {
	"": ["ratio",1.0], "1": ["ratio",1.0], "%": ["ratio",0.01], "V": ["voltage",1.0], "A": ["current",1.0],
	"Ω": ["resistance",1.0], "ohm": ["resistance",1.0], "ohms": ["resistance",1.0],
	"W": ["power",1.0], "J": ["energy",1.0], "s": ["time",1.0], "Hz": ["frequency",1.0],
	"F": ["capacitance",1.0], "H": ["inductance",1.0], "var": ["reactive_power",1.0],
	"VA": ["apparent_power",1.0], "degrees": ["angle",PI/180.0], "deg": ["angle",PI/180.0],
	"°": ["angle",PI/180.0], "rad": ["angle",1.0], "rpm": ["speed",TAU/60.0],
	"N·m": ["torque",1.0], "T": ["flux_density",1.0], "Wb": ["flux",1.0], "A·turns": ["mmf",1.0]
}
const PREFIX = {"p":1e-12,"n":1e-9,"u":1e-6,"µ":1e-6,"μ":1e-6,"m":1e-3,"k":1e3,"M":1e6,"G":1e9}
static func unit_info(unit: String) -> Array:
	unit=unit.replace("Ω","Ω").replace("Ohms","ohms").replace("Ohm","ohm")
	if UNITS.has(unit): return UNITS[unit]
	if unit.length()>1 and PREFIX.has(unit[0]) and UNITS.has(unit.substr(1)):
		var base: Array=UNITS[unit.substr(1)]
		if base[0] in ["ratio","angle","speed","torque","mmf"]: return []
		return [base[0],float(base[1])*float(PREFIX[unit[0]])]
	return []
static func parse(raw: String, printed_unit: String) -> Dictionary:
	raw=raw.replace("−","-")
	var regex := RegEx.new()
	regex.compile("^\\s*([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?)\\s*(.*?)\\s*$")
	var found := regex.search(raw)
	if found==null:return {"ok":false,"reason":"Enter a finite number and an optional compatible unit."}
	var suffix := found.get_string(2)
	if suffix=="":suffix=printed_unit
	var expected := unit_info(printed_unit)
	var actual := unit_info(suffix)
	if expected.is_empty() or actual.is_empty() or expected[0]!=actual[0]:return {"ok":false,"reason":"Unit has the wrong dimension or prefix."}
	var token := found.get_string(1).to_lower()
	if token.length()>160:return {"ok":false,"reason":"Number is outside supported finite precision."}
	if token.contains("e"):
		var exponent := token.split("e")[1]
		if exponent.trim_prefix("+").trim_prefix("-").length()>4 or int(exponent)>308 or int(exponent)<-308:return {"ok":false,"reason":"Exponent is outside supported finite precision."}
	var value := float(token)*float(actual[1])
	if not is_finite(value):return {"ok":false,"reason":"Value must be finite."}
	# Leading zeros do not count; trailing decimal zeros do. Integer trailing zeros
	# are ambiguous and count as supplied digits; use scientific notation to be explicit.
	var mantissa := found.get_string(1).to_lower().split("e")[0].replace("+","").replace("-","").replace(".","")
	while mantissa.begins_with("0") and mantissa.length()>1:mantissa=mantissa.substr(1)
	return {"ok":true,"value_si":value,"significant_figures":mantissa.length()}
static func check(question: Dictionary, raw: String) -> Dictionary:
	var parsed := parse(raw,str(question.get("unit","")))
	if not parsed.ok:return {"correct":false,"reason":parsed.reason}
	var info := unit_info(str(question.get("unit","")))
	var target := float(question.answer)*float(info[1])
	var tolerance := maxf(float(question.get("absolute_tolerance_si",1e-9)),absf(target)*float(question.get("relative_tolerance",0.02)))
	var required := int(question.get("min_significant_figures",0))
	# Significant figures are undefined for an exact zero; its configured absolute
	# tolerance controls acceptance. Nonzero quantities retain the declared minimum.
	var precision_ok: bool=target==0.0 or int(parsed.significant_figures)>=required
	var correct: bool=absf(float(parsed.value_si)-target)<=tolerance and precision_ok
	return {"correct":correct,"reason":"Accepted" if correct else "Check value, sign, units and required significant figures."}
