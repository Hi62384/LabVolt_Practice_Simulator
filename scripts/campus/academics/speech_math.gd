extends RefCounted
## Small display grammar for equations in otherwise plain dialogue.
const SYMBOLS:={
	"alpha":"α","beta":"β","gamma":"γ","delta":"δ","Delta":"Δ","theta":"θ","phi":"φ",
	"omega":"ω","Omega":"Ω","pi":"π","tau":"τ","mu":"μ","lambda":"λ","sigma":"σ",
	"cdot":"·","times":"×","div":"÷","pm":"±","mp":"∓","le":"≤","leq":"≤","ge":"≥","geq":"≥",
	"neq":"≠","approx":"≈","sim":"∼","angle":"∠","degree":"°","circ":"°","infty":"∞",
	"rightarrow":"→","Rightarrow":"⇒","sum":"∑","int":"∫","partial":"∂","left":"","right":""
}
const LOWER:={"0":"₀","1":"₁","2":"₂","3":"₃","4":"₄","5":"₅","6":"₆","7":"₇","8":"₈","9":"₉","n":"ₙ","i":"ᵢ","x":"ₓ","a":"ₐ","e":"ₑ","o":"ₒ","+":"₊","-":"₋"}
const UPPER:={"0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹","n":"ⁿ","i":"ⁱ","+":"⁺","-":"⁻"}
static var math_pattern:=RegEx.create_from_string("(?s)\\\\\\((.+?)\\\\\\)|\\\\\\[(.+?)\\\\\\]|\\$\\$(.+?)\\$\\$|(?<![\\\\\\$])\\$(?![\\s\\$])([^$\\n]*?[^\\s$\\n])\\$(?![\\d\\$])")
static var script_pattern:=RegEx.create_from_string("([_^])(?:\\{([^{}]+)\\}|([+-]?[0-9]+|[A-Za-z]))")
static var root_pattern:=RegEx.create_from_string("\\\\sqrt\\s*\\{([^{}]+)\\}")
static var fraction_pattern:=RegEx.create_from_string("\\\\(?:dfrac|tfrac|frac)\\s*\\{([^{}]+)\\}\\s*\\{([^{}]+)\\}")
static var group_pattern:=RegEx.create_from_string("\\\\(?:text|mathrm|mathbf|operatorname|mathit)\\s*\\{([^{}]+)\\}")
static var symbol_pattern:=RegEx.create_from_string("\\\\([A-Za-z]+)")

static func display(text: String) -> String:
	var result:=text
	for item in _reverse(math_pattern.search_all(text)):
		for index in range(1,5):
			var equation:=item.get_string(index)
			if equation.is_empty():continue
			result=_substitute(result,item,_equation(equation.strip_edges().replace("\n"," ")))
			break
	return result

static func _equation(text: String) -> String:
	var result:=text
	for token in ["\\,","\\;","\\:","\\qquad","\\quad"]:
		result=result.replace(token," ")
	for pass_index in 6:
		var previous:=result
		result=group_pattern.sub(result,"$1",true)
		result=root_pattern.sub(result,"√($1)",true)
		result=fraction_pattern.sub(result,"($1)⁄($2)",true)
		for item in _reverse(script_pattern.search_all(result)):
			var base: String=item.get_string(2) if not item.get_string(2).is_empty() else item.get_string(3)
			var marker: String=item.get_string(1)
			var rendered:=_script(base.replace("−","-"),UPPER if marker=="^" else LOWER)
			if rendered.is_empty():rendered=(" raised to (" if marker=="^" else " subscript (")+base+")"
			result=_substitute(result,item,rendered)
		if previous==result:break
	for item in _reverse(symbol_pattern.search_all(result)):
		var command: String=item.get_string(1)
		result=_substitute(result,item,SYMBOLS.get(command,command))
	return result

static func _script(value: String,alphabet: Dictionary) -> String:
	var result:=""
	for character in value:
		if not alphabet.has(character):return ""
		result+=alphabet[character]
	return result

static func _reverse(values: Array[RegExMatch]) -> Array[RegExMatch]:
	values.reverse()
	return values

static func _substitute(source: String,item: RegExMatch,replacement: String) -> String:
	return source.substr(0,item.get_start())+replacement+source.substr(item.get_end())
