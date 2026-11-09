extends RefCounted
## Worked transformations are computed from each original generated instance.
const E = preload("res://scripts/mth147/exact.gd")
const P = preload("res://scripts/mth147/parser.gd")
const S = preload("res://scripts/mth147/solver.gd")
const N = preload("res://scripts/mth147/numeric.gd")
const Forms = preload("res://scripts/mth147/forms.gd")

static func ast(expression: Variant) -> Dictionary:
	var parsed := P.new().parse(N.literal(expression))
	return parsed.ast if parsed.ok else {"op":"text","value":str(expression)}

static func equation(left: Variant,right: Variant) -> Dictionary:
	return {"op":"equation","args":[ast(left),ast(right)]}

static func matrix_ast(matrix: Array,rhs: Array=[]) -> Dictionary:
	var rows: Array=[]
	for i in range(matrix.size()):
		var row: Array=[]
		for cell in matrix[i]:row.append(ast(E.text(cell)))
		if not rhs.is_empty():row.append(ast(E.text(rhs[i])))
		rows.append(row)
	return {"op":"matrix","rows":rows}

static func answer_panels(problem: Dictionary) -> Array:
	var result: Array=[];var answer: Variant=problem.answer;var form := str(problem.expected_form)
	if form=="choice":
		var text := str(answer)
		for option in problem.get("options",[]):
			if str(option.id)==str(answer):text=str(option.text)
		result.append(ast(text))
	elif form in ["system","structured","division"]:
		for field in answer:
			result.append({"op":"text","value":str(answer[field])+" solutions"} if field=="classification" else equation(str(field),answer[field]))
	elif form in ["solutions","restrictions"]:
		var entries: Array=[]
		for entry in answer:entries.append(ast(entry))
		result.append({"op":"solutions" if form=="solutions" else "excluded","args":entries})
	elif form=="rational":
		result.append(ast(answer.expression));var entries: Array=[]
		for entry in answer.excluded:entries.append(ast(entry))
		result.append({"op":"excluded","args":entries})
	elif form=="graph":
		var f: Dictionary=answer.function
		result.append(equation("y","%s+(%s)*%s(360*(x-(%s))/(%s))"%[N.literal(f.offset),N.literal(f.amplitude),f.kind,N.literal(f.phase),N.literal(f.period)]))
	elif form=="table":
		var rows: Array=[]
		for row in answer.rows:
			var cells: Array=[]
			for cell in row:cells.append(ast(cell))
			rows.append(cells)
		result.append({"op":"matrix","rows":rows})
	elif form=="triangle":
		for i in range(answer.solutions.size()):
			result.append({"op":"text","value":"Triangle "+str(i+1)})
			for field in answer.solutions[i]:result.append(equation(str(field),answer.solutions[i][field]))
	else:result.append(ast(answer))
	return result

static func derive(problem: Dictionary) -> Array:
	var out: Array=[];var proof: Dictionary=problem.parameters.proof;var kind := str(proof.kind)
	if kind=="equation":
		var left := E.parse_normal(proof.left);var right := E.parse_normal(proof.right)
		if not left.is_empty() and not right.is_empty():
			var numerator := E.padd(E.pmul(left.n,right.d),E.pmul(right.n,left.d),true)
			out.append({"text":"Clear the recorded nonzero denominators, move terms to the left and combine like powers.","math":equation(E.sparse_text(numerator),"0")})
		for candidate in problem.answer:
			var value := N.from_text(str(candidate))
			out.append({"text":"Check x=%s in the ORIGINAL equation. The two sides evaluate to %s and %s."%[str(candidate),N.literal(N.from_text(proof.left,{proof.variable:value})),N.literal(N.from_text(proof.right,{proof.variable:value}))],"math":equation(proof.variable,candidate)})
	elif kind=="division":
		var variable := str(proof.variable);var dividend := E.parse_normal(proof.dividend);var divisor := E.parse_normal(proof.divisor)
		if not dividend.is_empty() and not divisor.is_empty():
			var rem := S.coefficients(dividend.n,variable);var den := S.coefficients(divisor.n,variable)
			for _iteration in range(12):
				if rem.size()<den.size() or (rem.size()==1 and rem[0][0]==0):break
				var shift := rem.size()-den.size();var coefficient := E.divq(rem[-1],den[-1])
				var term := "(%s)*%s^%d"%[E.text(coefficient),variable,shift]
				for i in range(den.size()):rem[i+shift]=E.add(rem[i+shift],E.neg(E.mul(coefficient,den[i])))
				while rem.size()>1 and rem[-1][0]==0:rem.pop_back()
				out.append({"text":"The next quotient term is %s. Multiply the divisor by it and subtract. The remaining dividend is shown."%term,"math":ast(E.polynomial_text(rem,variable))})
		out.append({"text":"Reconstruct the dividend to verify both parts.","math":equation(proof.dividend,"(%s)*(%s)+(%s)"%[proof.divisor,problem.answer.quotient,problem.answer.remainder])})
	elif kind in ["system","determinant"]:
		var determinant := E.determinant(proof.matrix);var panel := matrix_ast(proof.matrix);panel.op="determinant"
		out.append({"text":"The coefficient determinant is D=%s."%E.text(determinant),"math":panel})
		if kind=="system" and determinant[0]!=0:
			for col in range(proof.matrix.size()):
				var replacement: Array=proof.matrix.duplicate(true)
				for row in range(replacement.size()):replacement[row][col]=proof.rhs[row]
				var numerator := E.determinant(replacement);var replaced := matrix_ast(replacement);replaced.op="determinant"
				out.append({"text":"Replace column %d with b. The replacement determinant is %s, so %s=%s/(%s)=%s."%[col+1,E.text(numerator),["x","y","z"][col],E.text(numerator),E.text(determinant),E.text(E.divq(numerator,determinant))],"math":replaced})
		elif kind=="system":
			var rows: Array=proof.matrix.duplicate(true);var rhs: Array=proof.rhs.duplicate(true);var multiple := E.divq(rows[1][0],rows[0][0])
			for j in range(rows.size()):rows[1][j]=E.add(rows[1][j],E.neg(E.mul(multiple,rows[0][j])))
			rhs[1]=E.add(rhs[1],E.neg(E.mul(multiple,rhs[0])))
			out.append({"text":"Subtract the dependent multiple of row 1 from row 2; inspect the zero coefficient row and its constant.","math":matrix_ast(rows,rhs)})
	elif kind=="factor":
		var parsed := P.new().parse(str(problem.answer))
		if parsed.ok:
			var factors := Forms.factor_leaves(parsed.ast);var revealed := E.rf(E.pconstant(E.q(1)))
			for i in range(mini(6,factors.size()-1)):
				revealed=E.combine(revealed,E.normalize(factors[i]),"mul");var remaining := E.rf(E.pconstant(E.q(1)))
				for j in range(i+1,factors.size()):remaining=E.combine(remaining,E.normalize(factors[j]),"mul")
				if revealed.is_empty() or remaining.is_empty():break
				out.append({"text":"Expose a verified factor, then continue factoring the remaining polynomial.","math":ast("("+E.sparse_text(revealed.n)+")*("+E.sparse_text(remaining.n)+")")})
	elif kind=="radical_equation":
		out.append({"text":"Square both sides while retaining the ORIGINAL nonnegative-side conditions.","math":equation("%d*x+(%d)"%[proof.a,proof.b],"(%d*x+(%d))^2"%[proof.c,proof.d])})
		var solved := S.radical_equation(proof.a,proof.b,proof.c,proof.d)
		for candidate in solved.get("extraneous",[]):out.append({"text":"Reject x=%s: it solves the squared equation but fails the original principal-root equation."%str(candidate),"math":equation("x",candidate)})
	elif kind=="nested_radical":out.append({"text":"Recognize the square of a sum of positive roots.","math":equation("(sqrt(%s)+sqrt(%s))^2"%[proof.u,proof.v],"%s+2*sqrt(%s)"%[int(proof.u)+int(proof.v),int(proof.u)*int(proof.v)])})
	elif kind=="ssa":out.append({"text":"Compute the sine-law candidate before choosing either inverse-sine branch.","math":equation("sin(B)","(%s)*sin(%s)/(%s)"%[N.literal(proof.b),N.literal(proof.A),N.literal(proof.a)])})
	elif kind in ["wave","wave_compare"]:
		out.append({"text":"Take the reciprocal of the period in seconds to find frequency in hertz.","math":equation("f","1/(%s)"%N.literal(proof.function.period))})
		for point in proof.get("points",[]):out.append({"text":"Evaluate at t=%s s: %s point."%[N.literal(point.x),point.role],"math":equation("y",point.y)})
	for panel in answer_panels(problem):out.append({"text":"Final verified result. Check the required form and original conditions.","math":panel})
	return out
