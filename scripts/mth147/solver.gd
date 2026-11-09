extends RefCounted
const E = preload("res://scripts/mth147/exact.gd")
const N = preload("res://scripts/mth147/numeric.gd")
const P = preload("res://scripts/mth147/parser.gd")

static func coefficients(poly: Dictionary,variable: String="x") -> Array:
	if poly.is_empty():return []
	var out: Array=[]
	for _i in range(13):out.append(E.q(0))
	for key in poly:
		var powers := E.powers(key)
		for name in powers:
			if name!=variable:return []
		var degree := int(powers.get(variable,0))
		if degree>12:return []
		out[degree]=E.add(out[degree],poly[key])
	while out.size()>1 and out[-1][0]==0:out.pop_back()
	return out

static func equation(left: String,right: String,variable: String="x",excluded: Array=[]) -> Dictionary:
	var a := E.parse_normal(left);var b := E.parse_normal(right)
	if a.is_empty() or b.is_empty():return {"ok":false,"error":"Unsupported equation."}
	var numerator := E.padd(E.pmul(a.n,b.d),E.pmul(b.n,a.d),true)
	var c := coefficients(numerator,variable)
	if c.is_empty() or c.size()>3:return {"ok":false,"error":"Equation exceeds quadratic solver."}
	if c.size()==1:return {"ok":true,"classification":"infinite" if c[0][0]==0 else "none","values":[]}
	var roots: Array=[]
	if c.size()==2:roots=[E.text(E.divq(E.neg(c[0]),c[1]))]
	else:
		var discriminant := E.add(E.mul(c[1],c[1]),E.neg(E.mul(E.q(4),E.mul(c[2],c[0]))))
		if discriminant.is_empty():return {"ok":false,"error":"Arithmetic bound."}
		if discriminant[0]>=0:
			var center := E.text(E.neg(c[1]));var denom := E.text(E.mul(E.q(2),c[2]));var radical := "sqrt("+E.text(discriminant)+")"
			roots=["(("+center+")+"+radical+")/("+denom+")"]
			if discriminant[0]!=0:roots.append("(("+center+")-"+radical+")/("+denom+")")
	var values: Array=[]
	for root in roots:
		var x := N.from_text(root)
		if not is_finite(x):return {"ok":false,"error":"Invalid root."}
		var invalid := false
		for restriction in excluded:
			if N.close(x,N.from_text(str(restriction))):invalid=true
		var av := N.from_text(left,{variable:x});var bv := N.from_text(right,{variable:x})
		if not invalid and N.close(av,bv,1e-7,1e-8):values.append(root)
	return {"ok":true,"classification":"unique" if values.size()==1 else ("none" if values.is_empty() else "finite"),"values":values,"coefficients":c}

static func substitute(ast: Dictionary,variable: String,replacement: Dictionary) -> Dictionary:
	if ast.get("op","")=="symbol" and ast.name==variable:return replacement.duplicate(true)
	var out := ast.duplicate(true)
	if out.has("args"):
		for i in range(out.args.size()):out.args[i]=substitute(out.args[i],variable,replacement)
	return out

static func verify_rearrangement(left: String,right: String,target: String,answer: String) -> bool:
	var a := P.new().parse(left);var b := P.new().parse(right);var replacement := P.new().parse(answer)
	if not a.ok or not b.ok or not replacement.ok:return false
	return E.equivalent(substitute(a.ast,target,replacement.ast),substitute(b.ast,target,replacement.ast))

static func radical_equation(a: int,b: int,c: int,d: int) -> Dictionary:
	# sqrt(a*x+b)=c*x+d. Squaring supplies candidates, original equation removes extras.
	var result := equation("%d*x+%d"%[a,b],"(%d*x+%d)^2"%[c,d])
	if not result.get("ok",false):return result
	var values: Array=[];var extraneous: Array=[]
	for candidate in result.values:
		var x := N.from_text(str(candidate));var lhs := float(a)*x+b;var rhs := float(c)*x+d
		if lhs>=-1e-9 and rhs>=-1e-9 and N.close(sqrt(maxf(0,lhs)),rhs):values.append(candidate)
		else:extraneous.append(candidate)
	return {"ok":true,"values":values,"extraneous":extraneous}
