extends RefCounted
const Core = preload("res://scripts/mth147/math_core.gd")
const E = preload("res://scripts/mth147/exact.gd")
const N = preload("res://scripts/mth147/numeric.gd")
const Forms = preload("res://scripts/mth147/forms.gd")
const Solver = preload("res://scripts/mth147/solver.gd")

static func result(fraction: float,reason: String) -> Dictionary:
	return {"correct":fraction>=1.0-1e-9,"fraction":clampf(fraction,0,1),"reason":reason}

static func scalar(expected: Variant,answer: Variant,form: String="expression",rubric: Dictionary={}) -> Dictionary:
	var parsed := Core.input_ast(answer)
	if not parsed.ok:return result(0,str(parsed.get("error","Invalid answer.")))
	var reference := Core.input_ast(expected)
	if not reference.ok:return result(0,"Invalid host key; refuse to grade.")
	var exact := Core.equivalent(parsed.ast,reference.ast)
	var correct := bool(exact.get("equivalent",false))
	if form=="equation_zero":
		var actual := E.normalize(parsed.ast);var target := E.normalize(reference.ast)
		correct=not actual.is_empty() and not target.is_empty() and Forms.degree(actual.d)==0 and Forms.proportional(actual.n,target.n)
	if form in ["numeric","scientific","engineering","significant"] or rubric.get("allow_decimal",false):
		var actual := N.evaluate(parsed.ast,{},0,str(rubric.get("angle_unit","degrees")))
		var target := N.evaluate(reference.ast,{},0,str(rubric.get("angle_unit","degrees")))
		correct=correct or N.close(actual,target,float(rubric.get("absolute_tolerance",1e-8)),float(rubric.get("relative_tolerance",1e-7)))
	if not correct:return result(0,"The expression or value is incorrect, undefined, or outside the supported exact form.")
	var raw := Core.format_ascii(parsed.ast) if answer is Dictionary else N.literal(answer)
	if rubric.has("allowed_denominators") and not allowed_denominators(parsed.ast,rubric.allowed_denominators):return result(0,"This answer introduces an unapproved denominator restriction.")
	if rubric.get("ordinary",false) and (parsed.ast.op!="num" and not (parsed.ast.op=="neg" and parsed.ast.args[0].op=="num") or "e" in raw.to_lower()):return result(0.5,"Use ordinary decimal notation.")
	if rubric.get("single_power",false):
		if parsed.ast.op!="pow" or not N.close(N.evaluate(parsed.ast.args[0]),10,0,0):return result(0.5,"Express the result as one power of ten.")
	var required := Forms.check(form,raw,parsed.ast,reference.ast,rubric)
	if not required.ok:return result(float(rubric.get("value_credit",0.5)),str(required.reason))
	return result(1,"Correct.")

static func values(input: Variant) -> Array:
	if input is Array:return input
	if input is Dictionary and input.get("values",null) is Array:return input.values
	if input is String:
		var s := str(input).strip_edges().trim_prefix("{").trim_suffix("}")
		if s.to_lower() in ["none","no solution",""]:return []
		return Array(s.split(","))
	return []

static func set_match(expected: Array,answer: Variant,rubric: Dictionary={}) -> Dictionary:
	if answer is String and str(answer).strip_edges().is_empty():return result(0,"Enter the solution set; write none explicitly if it is empty.")
	if not (answer is Array or answer is String or answer is Dictionary and answer.get("values",null) is Array):return result(0,"Submit an explicit solution array or set.")
	var submitted := values(answer)
	if submitted.size()>64:return result(0,"Too many solutions.")
	var unique: Array=[]
	for item in submitted:
		var parsed := Core.input_ast(item)
		if not parsed.ok:return result(0,"Invalid solution entry.")
		var duplicate := false
		for existing in unique:
			if scalar(existing,item,"numeric",rubric).correct:duplicate=true
		if not duplicate:unique.append(item)
	var used: Array=[];var matched := 0
	for item in unique:
		var index := -1
		for j in range(expected.size()):
			if j not in used and scalar(expected[j],item,"numeric",rubric).correct:index=j;break
		if index<0:return result(0,"A submitted value is invalid, extraneous, or outside the requested interval.")
		used.append(index);matched+=1
	if expected.is_empty():return result(1 if unique.is_empty() else 0,"No valid solutions." if unique.is_empty() else "Remove invalid roots.")
	return result(float(matched)/expected.size(),"Correct." if matched==expected.size() else "Find every valid solution; the set is incomplete.")

static func graph(expected: Dictionary,answer: Variant,rubric: Dictionary) -> Dictionary:
	if not answer is Dictionary:return result(0,"Submit structured coordinates or a function.")
	if not answer.get("points",[]) is Array:return result(0,"Graph points must be a coordinate array.")
	var points: Array=answer.get("points",[])
	if points.size()>256:return result(0,"Too many graph points.")
	var target: Dictionary=expected.function
	var period := float(target.period);var amplitude := absf(float(target.amplitude))
	var xtol := period*float(rubric.get("x_tolerance",0.01));var ytol := maxf(1e-8,amplitude*float(rubric.get("y_tolerance",0.02)))
	var earned := 0.0;var total := 0.0
	# Match all required critical coordinates exactly within explicit graph tolerance.
	for wanted in expected.get("points",[]):
		total+=1.0;var found := false
		for point in points:
			if not point is Dictionary or not point.get("x",null) is float and not point.get("x",null) is int or not point.get("y",null) is float and not point.get("y",null) is int:continue
			if N.close(float(point.x),float(wanted.x),xtol,0) and N.close(float(point.y),float(wanted.y),ytol,0) and str(point.get("role","critical")) in [str(wanted.get("role","critical")),"critical"]:found=true;break
		if found:earned+=1.0
	# Incorrect extra points are penalized; a dense point cloud cannot game required slots.
	for point in points:
		if not point is Dictionary or not point.has("x") or not point.has("y"):return result(0,"Invalid coordinates.")
		if not (point.x is float or point.x is int) or not (point.y is float or point.y is int):return result(0,"Coordinates must be finite numbers.")
		var x := float(point.x);var y := float(point.y)
		if not is_finite(x) or not is_finite(y):return result(0,"Coordinates must be finite.")
		if x<float(expected.domain[0])-xtol or x>float(expected.domain[1])+xtol or not N.close(y,N.wave(target,x),ytol,0):total+=1.0
	if answer.has("function"):
		if not answer.function is Dictionary:return result(0,"Function parameters must be a structured object.")
		total+=2.0;var submitted: Dictionary=answer.function
		var valid := N.waves_equal(submitted,target,xtol,ytol)
		if valid:earned+=2.0
	if rubric.get("require_period",false):
		total+=1
		if answer.has("period") and scalar(period,answer.period,"numeric",{"absolute_tolerance":xtol,"relative_tolerance":0}).correct:earned+=1
	return result(earned/maxf(1,total),"Graph graded from function values and required coordinates, including any incorrect extra points.")

static func check(problem: Dictionary,answer: Variant) -> Dictionary:
	if not safe_answer(answer):return result(0,"Answer exceeds the bounded structured-input limits or contains invalid data.")
	if not problem.has("answer"):return result(0,"Host key unavailable.")
	var expected: Variant=problem.answer;var form := str(problem.get("expected_form","expression"));var rubric: Dictionary=problem.get("rubric",{})
	match form:
		"solutions","restrictions":return set_match(expected,answer,rubric)
		"choice":return result(1 if str(expected)==str(answer) else 0,"Compare the defining property, not the appearance.")
		"multi_choice":return set_match(expected,answer,rubric)
		"graph":return graph(expected,answer,rubric)
		"table":
			if not answer is Dictionary or not answer.get("rows",null) is Array or not expected.get("rows",null) is Array:return result(0,"Complete the structured table cells.")
			if answer.rows.size()>expected.rows.size():return result(0,"The table has unexpected extra rows.")
			var earned := 0.0;var total := 0
			for row in range(expected.rows.size()):
				var supplied: Variant=answer.rows[row] if row<answer.rows.size() else []
				if not supplied is Array or supplied.size()>expected.rows[row].size():return result(0,"The table has an invalid row or extra columns.")
				for column in range(expected.rows[row].size()):
					total+=1;earned+=scalar(expected.rows[row][column],supplied[column] if column<supplied.size() else "","numeric",rubric).fraction
			return result(earned/maxi(1,total),"Each table ordinate is checked against the generated mathematical function.")
		"system":
			if not answer is Dictionary:return result(0,"Enter each requested variable or classify the system.")
			if expected.has("classification"):return result(1 if answer.get("classification","")==expected.classification else 0,"Classify the coefficient and augmented ranks.")
			var earned := 0.0
			for name in expected:earned+=scalar(expected[name],answer.get(name,""),"numeric",rubric).fraction
			return result(earned/maxi(1,expected.size()),"Substitute every requested variable into the original system.")
		"rational":
			if not answer is Dictionary:return result(0,"Supply the simplified expression and every original excluded value.")
			var expression := scalar(expected.expression,answer.get("expression",""),"expression",rubric)
			var restrictions := set_match(expected.excluded,answer.get("excluded",[]),rubric)
			var expression_ast := Core.input_ast(answer.get("expression",""))
			if expression_ast.ok and not original_domain(expression_ast.ast,expected.excluded):expression=result(0,"The submitted expression adds an excluded input outside the original domain.")
			if expression.correct and rubric.has("reduced_factors"):
				var parsed := Core.input_ast(answer.get("expression",""))
				if parsed.ok:
					var value := E.normalize(parsed.ast)
					if not value.is_empty():
						for factor in rubric.reduced_factors:
							var root: Array=E.scalar(E.parse_normal(str(factor)))
							if not root.is_empty() and E.peval(value.n,{"x":root})==E.q(0) and E.peval(value.d,{"x":root})==E.q(0):expression=result(0.5,"Cancel the remaining common factor.")
			return result(.75*expression.fraction+.25*restrictions.fraction,"Retain restrictions from the original denominators, including canceled factors.")
		"division","structured":
			if not answer is Dictionary:return result(0,"Complete the structured answer fields.")
			var earned := 0.0;var total := 0.0;var details: Array=[]
			for name in expected:
				var rule: Dictionary=rubric.get("fields",{}).get(name,{})
				var weight := float(rule.get("weight",1));total+=weight
				var part := scalar(expected[name],answer.get(name,""),str(rule.get("form","expression")),rule)
				earned+=weight*part.fraction;details.append({"field":name,"fraction":part.fraction,"reason":part.reason})
			var out := result(earned/maxf(1,total),"Each field is marked independently; missing entries receive no credit.");out.parts=details;return out
		"triangle":
			if not answer is Dictionary or not answer.get("solutions",null) is Array:return result(0,"Enter every valid triangle.")
			var supplied: Array=answer.solutions
			if supplied.size()!=expected.solutions.size():return result(0,"The number of valid triangles is incorrect; check the SSA ambiguity.")
			var used: Array=[];var earned := 0.0;var total := 0.0
			for actual in supplied:
				if not actual is Dictionary:return result(0,"Invalid triangle fields.")
				var best := -1;var credit := -1.0
				for i in range(expected.solutions.size()):
					if i in used:continue
					var score := 0.0
					for name in expected.solutions[i]:score+=scalar(expected.solutions[i][name],actual.get(name,""),"numeric",rubric).fraction
					if score>credit:credit=score;best=i
				if best>=0:used.append(best);earned+=credit;total+=expected.solutions[best].size()
			return result(1 if total==0 else earned/total,"Check side-angle opposition, angle sum, and every valid SSA solution.")
	return scalar(expected,answer,form,rubric)

static func allowed_denominators(ast: Dictionary,allowed: Array) -> bool:
	var constraints := Core.domain_constraints(ast)
	if not constraints.ok:return false
	var reference_factors: Array=[]
	for condition in allowed:
		for leaf in Forms.factor_leaves(condition):
			var normal := E.normalize(leaf)
			if not normal.is_empty():reference_factors.append(normal.n)
	for condition in constraints.constraints:
		if condition.relation!="nonzero":continue
		for leaf in Forms.factor_leaves(condition.expression):
			var normal := E.normalize(leaf)
			if normal.is_empty():return false
			if Forms.degree(normal.n)==0:continue
			var found := false
			for reference in reference_factors:
				if Forms.proportional(normal.n,reference):found=true;break
			if not found:return false
	return true

static func original_domain(ast: Dictionary,excluded: Array) -> bool:
	var constraints := Core.domain_constraints(ast)
	if not constraints.ok:return false
	for condition in constraints.constraints:
		if condition.relation!="nonzero":return false
		var expression := E.normalize(condition.expression)
		if expression.is_empty():return false
		var coefficients := Solver.coefficients(expression.n)
		if coefficients.is_empty() or coefficients.size()>3:return false
		var roots := Solver.equation(E.sparse_text(expression.n),"0")
		if not roots.get("ok",false) or roots.get("classification","")=="infinite":return false
		for root in roots.values:
			var found := false
			for value in excluded:
				if scalar(root,value,"numeric").correct:found=true;break
			if not found:return false
	return true

static func safe_answer(answer: Variant,depth: int=0,budget: Array=[0]) -> bool:
	if depth==0:budget=[0]
	budget[0]+=1
	if depth>16 or budget[0]>2048:return false
	if answer is String:return answer.length()<=512
	if answer is bool:return true
	if answer is int:return true
	if answer is float:return is_finite(answer) and absf(answer)<=1e100
	if answer is Array:
		if answer.size()>256:return false
		for child in answer:
			if not safe_answer(child,depth+1,budget):return false
		return true
	if answer is Dictionary:
		if answer.size()>64:return false
		for key in answer:
			if not (key is String or key is StringName) or str(key).length()>64 or not safe_answer(answer[key],depth+1,budget):return false
		return true
	return false
