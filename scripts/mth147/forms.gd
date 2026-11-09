extends RefCounted
const E = preload("res://scripts/mth147/exact.gd")
const N = preload("res://scripts/mth147/numeric.gd")
const P = preload("res://scripts/mth147/parser.gd")

static func has_op(ast: Dictionary,op: String) -> bool:
	if ast.get("op","")==op:return true
	for child in ast.get("args",[]):
		if has_op(child,op):return true
	return false

static func positive(ast: Dictionary) -> bool:
	if ast.get("op","")=="pow":
		var exponent := N.evaluate(ast.args[1])
		if not is_finite(exponent) or exponent<0:return false
	for child in ast.get("args",[]):
		if not positive(child):return false
	return true

static func degree(poly: Dictionary) -> int:
	var d := 0
	for key in poly:
		var total := 0
		for exponent in E.powers(key).values():total+=int(exponent)
		d=maxi(d,total)
	return d

static func expanded(ast: Dictionary) -> bool:
	var op := str(ast.get("op",""))
	if op=="div":
		var denominator := E.normalize(ast.args[1])
		if denominator.is_empty() or E.scalar(denominator).is_empty():return false
	if op in ["mul","pow"]:
		for child in ast.args:
			if has_op(child,"add") or has_op(child,"sub"):return false
	for child in ast.get("args",[]):
		if not expanded(child):return false
	return positive(ast)

static func additive_terms(ast: Dictionary) -> Array:
	if ast.get("op","") in ["add","sub"]:return additive_terms(ast.args[0])+additive_terms(ast.args[1])
	if ast.get("op","")=="neg":return additive_terms(ast.args[0])
	return [ast]

static func collected(ast: Dictionary) -> bool:
	var seen := {}
	for term in additive_terms(ast):
		var normalized := E.normalize(term)
		if normalized.is_empty() or normalized.n.size()!=1:return false
		var key := str(normalized.n.keys()[0])
		if seen.has(key):return false
		seen[key]=true
	return true

static func symbol_counts(ast: Dictionary,out: Dictionary) -> void:
	var op := str(ast.get("op",""))
	if op=="symbol":out[str(ast.name)]=int(out.get(str(ast.name),0))+1;return
	if op not in ["add","sub","mul","div","pow","neg"]:return
	for child in ast.get("args",[]):symbol_counts(child,out)

static func consolidated_monomials(ast: Dictionary) -> bool:
	for term in additive_terms(ast):
		var counts := {};symbol_counts(term,counts)
		for count in counts.values():
			if int(count)>1:return false
	return true

static func radical_count(ast: Dictionary) -> int:
	var count := 1 if ast.get("op","") in ["sqrt","cbrt","root"] else 0
	for child in ast.get("args",[]):count+=radical_count(child)
	return count

static func consolidated_radicals(ast: Dictionary) -> bool:
	for term in additive_terms(ast):
		if radical_count(term)>1:return false
	return true

static func factor_leaves(ast: Dictionary) -> Array:
	var op := str(ast.get("op",""))
	if op=="mul":return factor_leaves(ast.args[0])+factor_leaves(ast.args[1])
	if op=="neg":return factor_leaves(ast.args[0])
	if op=="pow":
		var exponent := N.evaluate(ast.args[1])
		if is_finite(exponent) and exponent==floor(exponent) and exponent>0 and exponent<=12:
			var out: Array=[]
			for _i in range(int(exponent)):out+=factor_leaves(ast.args[0])
			return out
	return [ast]

static func proportional(a: Dictionary,b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or a.size()!=b.size():return false
	var ratio: Array=[]
	for key in a:
		if not b.has(key) or b[key][0]==0:return false
		var r := E.divq(a[key],b[key])
		if r.is_empty():return false
		if ratio.is_empty():ratio=r
		elif ratio!=r:return false
	return true

static func fully_factored(ast: Dictionary,reference: Dictionary) -> bool:
	# Match irreducible generated factors up to rational units, order and powers.
	# Equality is separately checked; a product containing an expanded reducible
	# factor cannot match the irreducible degree/signature multiset.
	var expected: Array=[]
	for leaf in factor_leaves(reference):
		var value := E.normalize(leaf)
		if value.is_empty():return false
		if degree(value.n)>0:expected.append(value)
	for leaf in factor_leaves(ast):
		var value := E.normalize(leaf)
		if value.is_empty() or degree(value.d)>0:return false
		if degree(value.n)==0:continue
		var found := -1
		for i in range(expected.size()):
			if proportional(value.n,expected[i].n):found=i;break
		if found<0:return false
		expected.remove_at(found)
	return expected.is_empty()

static func simplified_radicals(ast: Dictionary,in_denominator: bool=false) -> bool:
	var op := str(ast.get("op",""))
	if op in ["sqrt","cbrt","root"]:
		if in_denominator:return false
		var index := 2 if op=="sqrt" else 3
		var radicand: Dictionary=ast.args[0]
		if op=="root":
			index=int(N.evaluate(ast.args[0]));radicand=ast.args[1]
		if index<2 or index>6:return false
		var v := E.scalar(E.normalize(radicand))
		if v.is_empty() or v[1]!=1 or v[0]<=1:return false
		var n := int(v[0])
		var remaining := n;var prime := 2;var common := index
		while prime*prime<=remaining:
			var exponent := 0
			while remaining%prime==0:remaining=int(remaining/prime);exponent+=1
			if exponent>0:common=E.gcd(common,exponent)
			prime+=1
		if remaining>1:common=1
		if common>1:return false
		for k in range(2,int(pow(float(n),1.0/index))+2):
			var divisor := int(pow(k,index))
			if divisor>1 and n%divisor==0:return false
	if op=="pow":
		var exponent := N.evaluate(ast.args[1])
		if not is_finite(exponent) or exponent<0 or exponent!=floor(exponent):return false
	if op=="div":return simplified_radicals(ast.args[0],in_denominator) and simplified_radicals(ast.args[1],true)
	for child in ast.get("args",[]):
		if not simplified_radicals(child,in_denominator):return false
	return true

static func significant_digits(raw: String) -> int:
	var mantissa := raw.to_lower().split("e")[0].trim_prefix("-").trim_prefix("+")
	if not mantissa.is_valid_float():return -1
	var decimal_point := "." in mantissa
	var digits := mantissa.replace(".","").trim_prefix("0")
	while digits.begins_with("0"):digits=digits.substr(1)
	if digits.is_empty():return 1
	if not decimal_point:
		while digits.ends_with("0"):digits=digits.left(-1)
	return digits.length()

static func notation(raw: String,engineering: bool) -> bool:
	var s := raw.strip_edges().to_lower().replace(" ","").replace("×","*")
	var mantissa := "";var exponent := ""
	if "e" in s:
		var pieces := s.split("e")
		if pieces.size()!=2:return false
		mantissa=pieces[0];exponent=pieces[1]
	elif "*10^" in s:
		var pieces := s.split("*10^")
		if pieces.size()!=2:return false
		mantissa=pieces[0].trim_prefix("(").trim_suffix(")");exponent=pieces[1].trim_prefix("(").trim_suffix(")")
	else:return false
	if not mantissa.is_valid_float() or not exponent.is_valid_int():return false
	var m := absf(float(mantissa));var e := int(exponent)
	return m>=1.0 and m<(1000.0 if engineering else 10.0) and (not engineering or e%3==0)

static func notation_ast(ast: Dictionary,engineering: bool) -> bool:
	if ast.get("op","")!="mul" or ast.args[1].get("op","")!="pow":return false
	var mantissa := N.evaluate(ast.args[0]);var base := N.evaluate(ast.args[1].args[0]);var exponent := N.evaluate(ast.args[1].args[1])
	return is_finite(mantissa) and is_finite(exponent) and base==10 and absf(mantissa)>=1 and absf(mantissa)<(1000 if engineering else 10) and exponent==floor(exponent) and (not engineering or int(exponent)%3==0)

static func check(form: String,raw: String,ast: Dictionary,reference: Dictionary,rubric: Dictionary) -> Dictionary:
	var ok := true;var reason := "Correct."
	match form:
		"expanded":ok=expanded(ast) and collected(ast) and consolidated_monomials(ast);reason="Expand all products and powers, combine like terms, and combine repeated bases."
		"factored":ok=fully_factored(ast,reference);reason="Factor completely; preserve every irreducible factor."
		"positive_exponents":ok=positive(ast);reason="Use positive exponents."
		"scientific":ok=notation(raw,false) or notation_ast(ast,false);reason="Use a normalized mantissa and an explicit power of ten."
		"engineering":ok=notation(raw,true) or notation_ast(ast,true);reason="Use a mantissa from 1 to below 1000 and an exponent divisible by three."
		"significant":ok=significant_digits(raw)==int(rubric.get("digits",3));reason="Show the requested significant figures, including meaningful trailing zeros."
		"radical":ok=simplified_radicals(ast) and collected(ast) and consolidated_radicals(ast);reason="Extract perfect powers, reduce root indices, combine radical products/like terms, and rationalize the denominator."
	return {"ok":ok,"reason":"Correct." if ok else reason}
