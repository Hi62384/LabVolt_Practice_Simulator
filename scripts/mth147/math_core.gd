extends RefCounted
## Stable extension facade; plugins provide their own domains and set rubrics.
const Parser = preload("res://scripts/mth147/parser.gd")
const Exact = preload("res://scripts/mth147/exact.gd")
const Numeric = preload("res://scripts/mth147/numeric.gd")
const Forms = preload("res://scripts/mth147/forms.gd")

static func parse(source: String) -> Dictionary:
	return Parser.new().parse(source)

static func input_ast(input: Variant) -> Dictionary:
	if input is Dictionary:
		return {"ok":true,"ast":input} if Parser.valid_ast(input) else {"ok":false,"error":"Invalid or excessive AST."}
	if input is String or input is float or input is int:return parse(Numeric.literal(input))
	return {"ok":false,"error":"Expected a scalar expression."}

static func evaluate(input: Variant,variables: Dictionary={},angle_unit: String="degrees") -> Dictionary:
	var parsed := input_ast(input)
	if not parsed.ok:return parsed
	if variables.size()>32:return {"ok":false,"error":"Too many symbol bindings."}
	for v in variables.values():
		if not (v is float or v is int) or not is_finite(float(v)) or absf(float(v))>1e100:return {"ok":false,"error":"Invalid symbol binding."}
	var value := Numeric.evaluate(parsed.ast,variables,0,angle_unit)
	return {"ok":is_finite(value),"value":value if is_finite(value) else 0.0,"error":"" if is_finite(value) else "Undefined, unsupported, or outside bounded real domain."}

static func equivalent(left: Variant,right: Variant) -> Dictionary:
	var a := input_ast(left);var b := input_ast(right)
	if not a.ok or not b.ok:return {"ok":false,"equivalent":false,"reason":"Invalid expression."}
	var an := Exact.normalize(a.ast);var bn := Exact.normalize(b.ast)
	if an.is_empty() or bn.is_empty():return {"ok":false,"equivalent":false,"reason":"Outside supported exact algebra; use a domain-specific deterministic proof, never sample-only equivalence."}
	return {"ok":true,"equivalent":Exact.equivalent(a.ast,b.ast),"reason":"Checked exact rational-function identity; original-domain obligations remain with rubric."}

static func inspect_form(form: String,input: Variant,reference: Variant,rubric: Dictionary={}) -> Dictionary:
	var a := input_ast(input);var b := input_ast(reference)
	if not a.ok or not b.ok:return {"ok":false,"reason":"Invalid expression."}
	return Forms.check(form,format_ascii(a.ast) if input is Dictionary else str(input),a.ast,b.ast,rubric)

static func format_ascii(ast: Dictionary,depth: int=0) -> String:
	if depth>24:return ""
	var op := str(ast.get("op",""))
	if op=="num":return str(ast.get("value",""))
	if op=="symbol":return str(ast.get("name",""))
	var args: Array=ast.get("args",[]);var text: PackedStringArray=[]
	for child in args:text.append(format_ascii(child,depth+1))
	if op=="neg":return "-("+text[0]+")"
	if op in ["add","sub","mul","div","pow"]:return "("+text[0]+str({"add":"+","sub":"-","mul":"*","div":"/","pow":"^"}[op])+text[1]+")"
	return op+"("+",".join(text)+")"

static func domain_constraints(input: Variant) -> Dictionary:
	var parsed := input_ast(input)
	if not parsed.ok:return parsed
	var constraints: Array=[]
	collect_constraints(parsed.ast,constraints)
	return {"ok":true,"constraints":constraints,"policy":"Original AST conditions are retained before any cancellation; bindings must also evaluate finitely."}

static func collect_constraints(ast: Dictionary,out: Array) -> void:
	var op := str(ast.get("op",""));var args: Array=ast.get("args",[])
	match op:
		"div":out.append({"expression":args[1].duplicate(true),"relation":"nonzero"})
		"sqrt":out.append({"expression":args[0].duplicate(true),"relation":"nonnegative"})
		"ln","log":
			out.append({"expression":args[0].duplicate(true),"relation":"positive"})
			if op=="log":out.append({"expression":args[1].duplicate(true),"relation":"positive_not_one"})
		"asin","acos":out.append({"expression":args[0].duplicate(true),"relation":"closed_unit_interval"})
		"tan","sec":out.append({"expression":{"op":"cos","args":[args[0].duplicate(true)]},"relation":"nonzero"})
		"csc","cot":out.append({"expression":{"op":"sin","args":[args[0].duplicate(true)]},"relation":"nonzero"})
		"pow":
			var exponent := Numeric.evaluate(args[1])
			if is_finite(exponent) and exponent<=0:out.append({"expression":args[0].duplicate(true),"relation":"nonzero"})
			if is_finite(exponent) and exponent!=floor(exponent):out.append({"expression":args[0].duplicate(true),"relation":"real_power_domain","exponent":args[1].duplicate(true)})
		"root":
			var index := Numeric.evaluate(args[0])
			if is_finite(index) and int(index)%2==0:out.append({"expression":args[1].duplicate(true),"relation":"nonnegative"})
	for child in args:collect_constraints(child,out)

static func domain_at(input: Variant,variables: Dictionary={},angle_unit: String="degrees") -> Dictionary:
	var value := evaluate(input,variables,angle_unit)
	return {"ok":value.ok,"in_domain":value.ok,"error":value.get("error","")}
