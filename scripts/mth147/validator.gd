extends RefCounted
## Validates keys against original equations/constructions before issue.
const E = preload("res://scripts/mth147/exact.gd")
const N = preload("res://scripts/mth147/numeric.gd")
const S = preload("res://scripts/mth147/solver.gd")
const C = preload("res://scripts/mth147/math_core.gd")
const G = preload("res://scripts/mth147/grader.gd")
const Forms = preload("res://scripts/mth147/forms.gd")

static func fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func triangle(descriptor: Dictionary) -> bool:
	if descriptor.get("kind","")!="triangle" or descriptor.get("vertices",[]).size()!=3:return false
	var vertices: Array=descriptor.vertices;var names := ["a","b","c"]
	for i in range(3):
		var p: Dictionary=vertices[(i+1)%3];var q: Dictionary=vertices[(i+2)%3]
		var distance := sqrt(pow(float(p.x)-float(q.x),2)+pow(float(p.y)-float(q.y),2))
		if not N.close(distance,float(descriptor.sides[names[i]]),1e-7,1e-8):return false
	var sum := float(descriptor.angles.A)+float(descriptor.angles.B)+float(descriptor.angles.C)
	if not N.close(sum,180.0):return false
	var a := float(descriptor.sides.a);var b := float(descriptor.sides.b);var c := float(descriptor.sides.c)
	if minf(a,minf(b,c))<=0 or a+b<=c or b+c<=a or c+a<=b:return false
	for pair in [["a","A"],["b","B"],["c","C"]]:
		var angle := float(descriptor.angles[pair[1]])
		if angle<=0 or angle>=180:return false
	return N.close(a/sin(deg_to_rad(float(descriptor.angles.A))),b/sin(deg_to_rad(float(descriptor.angles.B))),1e-6,1e-7)

static func numeric_identity(left: String,right: String) -> bool:
	# Independent tree evaluation exercises normalizer against direct arithmetic.
	var count := 0
	for t in [0.37,0.89,1.67,2.31,-0.71]:
		var bindings := {"x":t,"y":t+1.23,"z":t-0.63,"t":t,"v":t+2.1,"a":t+0.45,"b":t+1.1,"c":t-0.9,"p":t+2.7,"i":t+1.0,"r":t+3.0}
		var a := N.from_text(left,bindings);var b := N.from_text(right,bindings)
		if not is_finite(a) or not is_finite(b):continue
		count+=1
		if not N.close(a,b,1e-7,1e-7):return false
	return count>=2

static func verify(problem: Dictionary) -> Dictionary:
	for field in ["id","generator_id","seed","ast","expected_form","answer","rubric","steps","parameters"]:
		if not problem.has(field):return fail("Missing "+field)
	var proof: Dictionary=problem.parameters.get("proof",{});var kind := str(proof.get("kind",""));var answer: Variant=problem.answer
	var original := str(proof.get("original",problem.parameters.get("expression","")))
	var ok := false
	match kind:
		"identity","factor","radical_identity":
			ok=E.same(original,str(answer)) and numeric_identity(original,str(answer))
			# Constant-only identities have no need for two distinct symbol bindings.
			if kind=="factor" and ok:
				var reference := C.input_ast(proof.reference)
				ok=reference.ok and G.scalar(proof.reference,answer,"factored").correct
				if ok:
					for leaf in Forms.factor_leaves(reference.ast):
						var normal := E.normalize(leaf)
						if normal.is_empty():ok=false;break
						var coefficients := S.coefficients(normal.n)
						if coefficients.is_empty() or coefficients.size()>3:ok=false;break
						if coefficients.size()==3:
							var discriminant := E.add(E.mul(coefficients[1],coefficients[1]),E.neg(E.mul(E.q(4),E.mul(coefficients[2],coefficients[0]))))
							if discriminant.is_empty() or not E.rational_sqrt(discriminant).is_empty():ok=false;break
		"numeric":
			var tolerance := 1e-14 if problem.generator_id in ["w8.ratio","w8.reciprocal"] else 1e-95
			ok=N.close(N.from_text(original),N.from_value(answer),tolerance,1e-10)
		"rounding":
			var value := float(proof.original);var digits := int(proof.digits)
			var exponent := int(floor(log(absf(value))/log(10.0)+1e-10));var unit := pow(10.0,exponent-digits+1)
			var rounded := roundf(value/unit)*unit
			ok=N.close(rounded,N.from_text(str(answer)),1e-95,1e-10)
		"factoring_method":
			var normalized := E.parse_normal(original)
			var coefficients := S.coefficients(normalized.n) if not normalized.is_empty() else []
			var nonzero := 0
			for coefficient in coefficients:
				if coefficient[0]!=0:nonzero+=1
			var expected := "perfect_square" if nonzero==3 else ("difference_squares" if (coefficients.size()-1)%2==0 else ("sum_cubes" if coefficients[0][0]>0 else "difference_cubes"))
			ok=str(answer)==expected
		"binomial_terms":
			var terms: PackedStringArray=[]
			for k in range(int(proof.count)):
				var coefficient := E.scalar(E.parse_normal("choose(%d,%d)"%[proof.n,k]))
				terms.append("(%s)*(%s)^%d*(%s)^%d"%[E.text(coefficient),proof.first,int(proof.n)-k,proof.second,k])
			ok=E.same("+".join(terms),str(answer)) and numeric_identity("+".join(terms),str(answer))
		"like_terms":
			for option in proof.options:
				if str(option.id)!=str(answer):continue
				var value := E.parse_normal(option.text)
				ok=not value.is_empty() and value.n.size()==1 and value.n.has("%s:%d"%[proof.variable,proof.power])
		"division":
			var divisor := E.parse_normal(proof.divisor);var dividend := E.parse_normal(proof.dividend)
			if divisor.is_empty() or dividend.is_empty():return fail("Invalid polynomial division input.")
			var divided := E.divide_polynomial(S.coefficients(dividend.n,proof.variable),S.coefficients(divisor.n,proof.variable))
			ok=not divided.is_empty() and E.same(E.polynomial_text(divided.quotient,proof.variable),str(answer.quotient)) and E.same(E.polynomial_text(divided.remainder,proof.variable),str(answer.remainder))
		"equation":
			var solved := S.equation(proof.left,proof.right,proof.variable,proof.excluded)
			ok=solved.get("ok",false) and G.set_match(solved.get("values",[]),answer).correct
		"rearrange":ok=S.verify_rearrangement(proof.left,proof.right,proof.target,str(answer))
		"system","model":
			var solved := E.solve(proof.matrix,proof.rhs)
			if solved.is_empty():return fail("System solver rejected arithmetic bounds.")
			if answer.has("classification"):ok=solved.classification==answer.classification
			else:
				ok=solved.classification=="unique"
				for name in answer:
					if not ok:break
					if str(name) in ["x","y","z"]:ok=E.same(E.text(solved.values[["x","y","z"].find(str(name))]),str(answer[name]))
					elif str(name).begins_with("balance"):
						var row := int(str(name).trim_prefix("balance"))-1
						var expression := "(%s)*x+(%s)*y-(%s)"%[E.text(proof.matrix[row][0]),E.text(proof.matrix[row][1]),E.text(proof.rhs[row])]
						ok=G.scalar(expression,answer[name],"equation_zero").correct
		"symbolic_system":
			ok=true
			for i in range(proof.left.size()):
				var left := str(proof.left[i]);var right := str(proof.right[i])
				for symbol in answer:left=left.replace(symbol,"("+str(answer[symbol])+")")
				if not E.same(left,right):ok=false
		"determinant":
			# Independent closed 2x2 / Sarrus 3x3, separate from cofactor key.
			var m: Array=proof.matrix;var value: Array=[]
			if m.size()==2:value=E.add(E.mul(m[0][0],m[1][1]),E.neg(E.mul(m[0][1],m[1][0])))
			else:
				value=E.q(0)
				for i in range(3):
					value=E.add(value,E.mul(m[0][i],E.mul(m[1][(i+1)%3],m[2][(i+2)%3])))
					value=E.add(value,E.neg(E.mul(m[0][i],E.mul(m[1][(i+2)%3],m[2][(i+1)%3]))))
			ok=E.same(E.text(value),str(answer))
		"rational":ok=E.same(original,str(answer.expression)) and G.set_match(proof.excluded,answer.excluded).correct and numeric_identity(original,str(answer.expression))
		"restrictions":ok=G.set_match(proof.excluded,answer).correct
		"nested_radical":
			var p := int(proof.u);var q := int(proof.v)
			ok=E.same("(%s)^2"%str(answer),"%d+2*sqrt(%d)"%[p+q,p*q]) and N.from_text(str(answer))>=0
		"variable_radical":ok=E.same("(%s)^2"%str(answer),"%d*x^%d"%[int(proof.a)*int(proof.a),2*int(proof.n)]) and N.from_text(str(answer),{"x":1.7})>=0
		"radical_equation":
			var solved := S.radical_equation(proof.a,proof.b,proof.c,proof.d)
			ok=solved.get("ok",false) and G.set_match(solved.get("values",[]),answer).correct
		"quadrant":
			var reduced := int(proof.angle)%360
			if reduced<0:reduced+=360
			var expected := str(int(reduced/90)+1)
			if proof.ask_sign:
				var positive := reduced<180 if proof.function=="sin" else (reduced<90 or reduced>270 if proof.function=="cos" else int(reduced/90)%2==0)
				expected="positive" if positive else "negative"
			ok=str(answer)==expected
		"coterminal":ok=float(answer)>=0 and float(answer)<360 and (int(proof.angle)-int(answer))%360==0
		"trig_equation":
			var expected := N.trig_solutions(proof.function,proof.target,proof.lo,proof.hi,proof.scale,proof.shift)
			ok=G.set_match(expected,answer).correct
			for x in answer:
				var value := N.from_text("%s(%s)"%[proof.function,str(float(proof.scale)*float(x)+float(proof.shift))])
				if not N.close(value,float(proof.target)):ok=false
		"triangle":
			ok=triangle(proof.descriptor)
			for field in proof.fields:
				var target: Variant=proof.descriptor.sides.get(field,proof.descriptor.angles.get(field,NAN))
				if not N.close(float(target),float(answer[field])):ok=false
		"ssa":
			var solutions := N.ssa(proof.A,proof.a,proof.b);ok=solutions.size()==answer.solutions.size()
			for item in answer.solutions:
				if not triangle(N.triangle(item.a,item.b,item.c)):ok=false
				if not N.close(float(item.A),float(proof.A)):ok=false
		"wave","wave_compare":
			var f: Dictionary=proof.function;ok=float(f.period)>0 and absf(float(f.amplitude))>0
			for point in proof.get("points",[]):
				if not N.close(float(point.y),N.wave(f,float(point.x))):ok=false
			if problem.expected_form=="table":
				for i in range(proof.points.size()):
					if not N.close(N.from_value(answer.rows[0][i]),N.wave(f,float(proof.points[i].x))):ok=false
			if problem.expected_form=="structured":
				var expected := {"amplitude":absf(float(f.amplitude)),"period":f.period,"frequency":1.0/float(f.period),"phase":f.phase,"midline":f.offset,"maximum":float(f.offset)+absf(float(f.amplitude)),"minimum":float(f.offset)-absf(float(f.amplitude))}
				if kind=="wave_compare":expected={"amplitude_ratio":absf(float(proof.other.amplitude)/float(f.amplitude)),"period_ratio":float(proof.other.period)/float(f.period),"frequency_ratio":float(f.period)/float(proof.other.period),"shift_change":float(proof.other.phase)-float(f.phase)}
				for field in answer:
					var target: float=float(expected.get(field,NAN))
					if str(field).begins_with("y") and str(field).substr(1).is_valid_int():target=N.wave(f,float(proof.points[int(str(field).substr(1))].x))
					if not N.close(target,float(answer[field])):ok=false
		"wave_zeros":
			var f: Dictionary=proof.function;var phases := N.trig_solutions(f.kind,-float(f.offset)/float(f.amplitude),0,360);var expected: Array=[]
			for angle in phases:expected.append(float(f.phase)+float(f.period)*float(angle)/360)
			ok=G.set_match(expected,answer,problem.rubric).correct
			for time_value in answer:
				if not N.close(N.wave(f,N.from_value(time_value)),0,1e-7,1e-7):ok=false
		_:return fail("Missing independent validator for "+kind)
	if not ok:return fail("Key failed independent validation: "+kind)
	if problem.has("diagram") and problem.diagram.get("kind","")=="triangle" and not triangle(problem.diagram):return fail("Triangle descriptor geometry mismatch.")
	var self_check := G.check(problem,problem.answer)
	if not self_check.correct:return fail("Key is not accepted in its required form: "+str(self_check.reason))
	return {"ok":true,"reason":"Verified original mathematics, domain and required key form.","validator_version":1}
