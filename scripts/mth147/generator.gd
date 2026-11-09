extends RefCounted
const E = preload("res://scripts/mth147/exact.gd")
const N = preload("res://scripts/mth147/numeric.gd")
const P = preload("res://scripts/mth147/parser.gd")
const S = preload("res://scripts/mth147/solver.gd")
const Worked = preload("res://scripts/mth147/worked.gd")
const TYPES = [
	["scientific","ordinary","engineering","prefix","powers","arithmetic","significant","formula"],
	["like_terms","simplify","nested","monomial","negative_powers","expand","special","division"],
	["linear","fractions","rational","rearrange","substitute","invalid"],
	["system2","system3","determinant2","determinant3","cramer","singular","symbolic","model"],
	["gcf","quadratic","grouping","squares","cubes","higher","method","binomial","term","first_terms","combination","factorial"],
	["reduce","multiply","divide","add","complex","restrictions","equation","extraneous"],
	["simplify","combine","product","rationalize","conjugate","powers","nested","equation","variables"],
	["ratio","right","reciprocal","quadrant","coterminal","sign","equation","identity","sine_law","cosine_law","ssa"],
	["characteristics","equation","graph","table","compare","critical","frequency","transform","zeros"]
]
var rng := RandomNumberGenerator.new()
var difficulty: int=0
var week: int=1
var type: String=""
var problem: Dictionary={}

static func ids(week_number: int=0) -> Array:
	var out: Array=[]
	for w in range(1,10):
		if week_number!=0 and w!=week_number:continue
		for name in TYPES[w-1]:out.append("w%d.%s"%[w,name])
	return out

func integer(lo: int=1,hi: int=9) -> int:
	return rng.randi_range(lo,hi)

func signed(lo: int=1,hi: int=9) -> int:
	return integer(lo,hi)*(1 if integer(0,1)==0 else -1)

func pick(items: Array) -> Variant:
	return items[integer(0,items.size()-1)]

func number() -> int:
	return signed(1,3+2*difficulty)

func frac() -> String:
	return E.text(E.q(number(),integer(1,1+difficulty)))

func atom(variable: String="x") -> String:
	return "(%s*%s+(%s))"%[frac(),variable,frac()]

func expanded(expression: String) -> String:
	var normal := E.parse_normal(expression)
	return E.sparse_text(normal.n) if not normal.is_empty() and normal.d==E.pconstant(E.q(1)) else expression

func six_figure_tolerance(value: float) -> Dictionary:
	var tolerance := 1e-12 if value==0 else 0.50001*pow(10.0,floor(log(absf(value))/log(10.0))-5)
	return {"absolute_tolerance":tolerance,"relative_tolerance":0.0}

func set_question(form: String,prompt: String,expression: String,answer: Variant,steps: Array,proof: Dictionary={}) -> void:
	# Save scalar floats as round-trip-safe scientific literals. Godot's JSON writer
	# otherwise rounds very small decimal floats even with full_precision enabled.
	if answer is float:answer=N.literal(answer)
	elif form=="structured" and answer is Dictionary:
		answer=answer.duplicate(true)
		for field in answer:
			if answer[field] is float:answer[field]=N.literal(answer[field])
	elif form=="solutions" and answer is Array:
		answer=answer.duplicate(true)
		for i in range(answer.size()):
			if answer[i] is float:answer[i]=N.literal(answer[i])
	var parsed := P.new().parse(expression)
	problem.merge({"expected_form":form,"prompt":prompt,"ast":parsed.ast if parsed.ok else {"kind":"structured"},"answer":answer,"steps":[],"rubric":{},"input":{"kind":form},"parameters":{"expression":expression,"proof":proof}},true)
	for step in steps:problem.steps.append({"text":str(step)})
	if proof.is_empty():problem.parameters.proof={"kind":"identity","original":expression,"answer":answer}
	if proof.get("kind","") in ["equation","rearrange"]:
		var lhs := P.new().parse(str(proof.left));var rhs := P.new().parse(str(proof.right))
		if lhs.ok and rhs.ok:problem.ast={"kind":"equation","op":"equation","args":[lhs.ast,rhs.ast],"left":lhs.ast,"right":rhs.ast,"target":proof.get("target",proof.get("variable","x"))}
	elif proof.get("kind","")=="radical_equation":
		var rhs: Dictionary=P.new().parse("%d*x+(%d)"%[proof.c,proof.d]).ast
		problem.ast={"kind":"equation","op":"equation","args":[parsed.ast,rhs],"left":parsed.ast,"right":rhs,"target":"x"}
	problem.metadata={"unit":week,"subtopic":type,"estimated_minutes":1+difficulty,"requires_working":false,"answer_policy":"deterministic structured final/multipart answer; personal ink is not interpreted"}

func generate(generator_id: String,d: int,seed_value: int) -> Dictionary:
	if generator_id not in ids() or d<0 or d>4:return {"error":"Unknown generator or difficulty."}
	difficulty=d;type=generator_id.split(".")[1];week=int(generator_id.substr(1,1));rng.seed=seed_value
	problem={"id":"mth147.v1.%s.%d.%d"%[generator_id,d,seed_value],"version":1,"generator_id":generator_id,"seed":str(seed_value),"week":week,"difficulty":d,"course_id":"MTH147","points":1.0}
	match week:
		1:notation()
		2:algebra()
		3:equations()
		4:systems()
		5:factoring()
		6:rational()
		7:radicals()
		8:trigonometry()
		9:sinusoids()
	problem.steps.append_array(Worked.derive(problem))
	return problem

func notation() -> void:
	var digits := integer(2,mini(6,3+difficulty));var exponent := integer(-3-5*difficulty,3+5*difficulty)
	var coefficient := integer(11,98);var value := coefficient*pow(10.0,exponent-1)
	var sign_value := -1 if difficulty>0 and integer(0,1)==0 else 1;value*=sign_value
	var expression := "%de%d"%[sign_value*coefficient,exponent-1]
	var common := ["Separate the sign, significant digits and decimal scale.","Use a power of ten to move the decimal; changing the exponent compensates exactly.","Check the size of the result and preserve units."]
	match type:
		"scientific":
			var answer := "%se%d"%[str(sign_value*coefficient/10.0),exponent]
			set_question("scientific","Express %s in normalized scientific notation."%expression,expression,answer,common)
		"ordinary":
			var answer := ("%."+str(maxi(0,1-exponent))+"f")%value if absf(value)<1e15 else "%.0f"%value
			set_question("numeric","Write %s as an ordinary decimal (no power-of-ten notation)."%expression,expression,answer,common)
			problem.rubric.ordinary=true
		"engineering":
			var engineering_exp := int(floor(float(exponent)/3.0))*3
			var mantissa := value/pow(10.0,engineering_exp)
			set_question("engineering","Express %s in engineering notation."%expression,expression,"%se%d"%[str(mantissa),engineering_exp],common)
		"prefix":
			var prefixes := [{"e":-12,"s":"p"},{"e":-9,"s":"n"},{"e":-6,"s":"u"},{"e":-3,"s":"m"},{"e":0,"s":""},{"e":3,"s":"k"},{"e":6,"s":"M"},{"e":9,"s":"G"},{"e":12,"s":"T"}]
			var source: Dictionary=pick(prefixes);var target: Dictionary=pick(prefixes);var unit := str(pick(["V","A","W","s","m"]))
			var original := "%d*10^(%d)"%[coefficient,int(source.e)-int(target.e)]
			set_question("numeric","Convert %d %s%s to %s%s. Enter the numerical coefficient."%[coefficient,source.s,unit,target.s,unit],original,N.from_text(original),["Replace each SI prefix with its exact power of ten.","Divide the base-unit value by the target prefix scale.","The target unit is "+str(target.s)+unit+"."],{"kind":"numeric","original":original})
			problem.input.unit=str(target.s)+unit
		"powers":
			var a := integer(-3-difficulty,3+difficulty);var b := signed();var c := signed(1,2+difficulty)
			var operation := integer(0,2);var original: String = ["10^(%d)*10^(%d)"%[a,b],"10^(%d)/10^(%d)"%[a,b],"(10^(%d))^(%d)"%[a,c]][operation]
			var power_value: int = [a+b,a-b,a*c][operation]
			set_question("numeric","Simplify to a single power of ten: "+original,original,"10^(%d)"%power_value,["For products add exponents; for quotients subtract them.","For a power of a power multiply exponents.","Keep the sign of each exponent."],{"kind":"numeric","original":original})
			problem.rubric.single_power=true
		"arithmetic":
			var other_exp := exponent+integer(-2-difficulty,2+difficulty);var other := integer(11,90)
			var op := str(pick(["+","-","*","/"]));var original := "(%s)%s(%de%d)"%[expression,op,other,other_exp]
			set_question("numeric","Calculate, retaining at least six significant figures: "+original,original,N.from_text(original),["For addition/subtraction first use a common scale.","For multiplication/division combine mantissas and combine exponents.","Normalize after the operation; do not round intermediate values."],{"kind":"numeric","original":original})
			problem.rubric=six_figure_tolerance(N.from_text(original))
		"significant":
			var raw := integer(100001,999999)*pow(10.0,exponent-5);var power_value := int(floor(log(raw)/log(10.0)+1e-10));var scale := pow(10.0,digits-1-power_value)
			var rounded: float = roundf(raw*scale)/scale;var mantissa: float = rounded/pow(10.0,power_value)
			if mantissa>=10:power_value+=1;mantissa/=10
			var answer := (("%."+str(digits-1)+"f")%mantissa)+"e"+str(power_value)
			set_question("significant","Round %s to %d significant figures. Preserve meaningful trailing zeros."%[N.literal(raw),digits],N.literal(raw),answer,["Start counting at the first nonzero digit.","Inspect the first discarded digit and round only once.","Show exactly %d significant digits; scientific notation makes trailing zeros unambiguous."%digits],{"kind":"rounding","original":N.literal(raw),"digits":digits})
			problem.rubric.digits=digits
		"formula":
			var frequency := integer(12,90)*pow(10.0,integer(1,3+difficulty))
			var original := "1/(%s)"%str(frequency)
			set_question("numeric","A periodic signal has frequency %s Hz. From T=1/f, find its period in seconds."%str(frequency),original,1.0/frequency,["Frequency counts cycles per second; period measures seconds per cycle.","Take the reciprocal of frequency in hertz.","Convert seconds to an SI prefix only after the reciprocal; Hz^-1 = s."],{"kind":"numeric","original":original})
	problem.rubric.merge({"relative_tolerance":1e-8,"absolute_tolerance":1e-100},false)

func algebra() -> void:
	var variable := str(pick(["x","t","v","z"]));var a := number();var b := number();var n := integer(1,2+difficulty);var expression := ""
	match type:
		"like_terms":
			var correct := "%d*%s^%d"%[b,variable,n]
			var options := [correct,"%d*%s^%d"%[a,variable,n+1],"%d*y^%d"%[b,n],str(b)]
			var order: Array=[0,1,2,3]
			for i in range(3,0,-1):var j := integer(0,i);var temp: int=order[i];order[i]=order[j];order[j]=temp
			var public_options: Array=[];var key := ""
			for i in range(4):
				public_options.append({"id":str(i),"text":options[order[i]]})
				if order[i]==0:key=str(i)
			set_question("choice","Which term is like %d*%s^%d?"%[a,variable,n],"%d*%s^%d"%[a,variable,n],key,["Like terms have identical variable parts and exponents.","Coefficients may differ; a changed exponent or variable gives unlike terms."],{"kind":"like_terms","variable":variable,"power":n,"options":public_options})
			problem.options=public_options
		"simplify","nested":
			expression=atom(variable)
			for i in range(1+difficulty):
				var term := "%s*%s^%d"%[frac(),variable,integer(0,1+difficulty)]
				expression="(%s)%s(%s)"%[expression,str(pick(["+","-"])),term]
				if type=="nested" and (i%2==0):expression="%d*(%s)-(%s)"%[number(),expression,atom(variable)]
			set_question("expanded","Simplify and combine like terms: "+expression,expression,expanded(expression),["Distribute each outer factor to every inner term, preserving signs.","Remove brackets from the innermost pair outward.","Combine coefficients only when variable powers match.","Check the result by expanding both forms independently."])
		"monomial":
			expression="(%d*%s^%d*y^%d)*(%d*%s^%d*y^%d)"%[a,variable,n,integer(1,2+difficulty),b,variable,integer(1,2+difficulty),integer(1,2+difficulty)]
			set_question("expanded","Multiply and use positive exponents: "+expression,expression,expanded(expression),["Multiply signed coefficients.","Add exponents of each same base separately.","Write the combined monomial in positive-exponent form."])
		"negative_powers":
			var m := integer(1,2+difficulty)
			expression="(%d*%s^(-%d)*y^%d)/(%d*%s^%d*y^(-%d))"%[a,variable,n,m,b,variable,m,n]
			var answer := "(%s*y^%d)/(%s^%d)"%[E.text(E.q(a,b)),m+n,variable,m+n]
			set_question("positive_exponents","Use only positive exponents; assume %s and y are nonzero: %s"%[variable,expression],expression,answer,["Subtract denominator exponents from numerator exponents for each base.","A negative power moves its factor across the fraction bar.","Original nonzero-base restrictions still apply."])
		"expand","special":
			if type=="special":
				var first := "%d*%s"%[a,variable]
				expression="(%s+(%d))*(%s-(%d))"%[first,b,first,b] if integer(0,1)==0 else "(%s+(%d))^2"%[first,b]
			else:
				expression=atom(variable)
				for _i in range(1+difficulty):expression+="*"+atom(variable)
			set_question("expanded","Expand and collect like terms: "+expression,expression,expanded(expression),["Multiply every term in one factor by every term in the next.","For (u+v)^2 include 2uv; for (u+v)(u-v) the cross terms cancel.","Collect equal powers after every multiplication."])
		"division":
			var divisor: Array=[E.q(number()),E.q(integer(1,3))];var quotient: Array=[]
			for _i in range(2+difficulty):quotient.append(E.q(number()))
			var remainder := E.q(number() if integer(0,1)==1 else 0)
			var qtext := E.polynomial_text(quotient,variable);var dtext := E.polynomial_text(divisor,variable)
			expression=expanded("(%s)*(%s)+(%s)"%[qtext,dtext,E.text(remainder)])
			set_question("division","Divide %s by %s. Give quotient and remainder."%[expression,dtext],expression,{"quotient":qtext,"remainder":E.text(remainder)},["Order the dividend and divisor by descending powers, inserting zero coefficients.","Divide leading terms, multiply the divisor and subtract the whole product.","Repeat until the remainder degree is less than the divisor degree.","Check dividend = divisor × quotient + remainder."],{"kind":"division","dividend":expression,"divisor":dtext,"variable":variable})
			problem.input.fields=[{"id":"quotient","label":"Quotient"},{"id":"remainder","label":"Remainder"}]

func equations() -> void:
	var root := number();var a := number();var b := number();var c := number()
	if a==c:c+=1
	var left := "";var right := ""
	match type:
		"linear","fractions":
			left="%d*x+(%d)"%[a,b];right="%d*x+(%d)"%[c,(a-c)*root+b]
			if type=="fractions":
				var denominator := integer(2,3+difficulty)
				left="(%s)/%d"%[left,denominator];right="(%s)/%d"%[right,denominator]
			for _i in range(difficulty):
				var k := number();var offset := number()
				left="%d*(%s)+(%d)"%[k,left,offset];right="%d*(%s)+(%d)"%[k,right,offset]
			set_question("solutions","Solve for x: %s = %s"%[left,right],left,[str(root)],["Distribute and remove brackets on both sides.","Multiply by a common nonzero denominator if necessary.","Perform the same inverse operation on both sides.","Substitute x=%d into the original equation."%root],{"kind":"equation","left":left,"right":right,"variable":"x","excluded":[]})
		"rational","invalid":
			var excluded := root+integer(1,4);var offset := number()
			left="(x-(%d))*(x-(%d))/(x-(%d))"%[root,excluded,excluded]
			right="0"
			if type=="invalid":
				left="(x-(%d))/(x-(%d))"%[excluded,excluded];right="0"
			var solution: Array=[] if type=="invalid" else [str(root)]
			set_question("solutions","Solve %s = %s. Reject values undefined in the original equation."%[left,right],left,solution,["Record x ≠ %d before multiplying by the denominator."%excluded,"Solve the numerator equation on the original domain.","Any canceled denominator zero is still excluded.","Substitute each candidate into the original equation."],{"kind":"equation","left":left,"right":right,"variable":"x","excluded":[str(excluded)],"unused_offset":offset})
		"rearrange","substitute":
			# Build a reversible symbolic operation tree rather than a fixed formula bank.
			var target := str(pick(["x","r","t","v"]))
			var expression := target;var operations: Array=[];var conditions: PackedStringArray=[]
			for i in range(2+difficulty):
				var symbol := str(pick(["a","b","c","d","i"]))
				var term := "(%d*%s^%d)"%[signed(1,3+difficulty),symbol,integer(1,1+int(difficulty/2))]
				var op := str(pick(["add","mul","div","reciprocal"]))
				if op=="reciprocal":
					conditions.append(expression+" != 0");conditions.append(term+" != 0")
					expression="%s/(%s)"%[term,expression]
				elif op=="add":expression="(%s)+%s"%[expression,term]
				else:
					conditions.append(term+" != 0")
					expression="(%s)%s%s"%[expression,"*" if op=="mul" else "/",term]
				operations.append({"op":op,"term":term})
			var rearranged := "p"
			var reverse_steps: Array=[]
			for i in range(operations.size()-1,-1,-1):
				var operation: Dictionary=operations[i];var term := str(operation.term)
				match operation.op:
					"add":rearranged="(%s)-%s"%[rearranged,term]
					"mul":rearranged="(%s)/%s"%[rearranged,term]
					"div":rearranged="(%s)*%s"%[rearranged,term]
					"reciprocal":conditions.append(rearranged+" != 0");rearranged="%s/(%s)"%[term,rearranged]
				reverse_steps.append("Undo %s: remaining inner expression = %s."%[operation.op,rearranged])
			if type=="rearrange":
				set_question("expression","Rearrange p=%s for %s. Assume %s."%[expression,target,", ".join(conditions)],expression,rearranged,["Follow the target from the innermost expression outward, then undo the operations in reverse order."]+reverse_steps+["Substitute the isolated expression into the original formula, keeping the nonzero conditions."],{"kind":"rearrange","left":"p","right":expression,"target":target})
				problem.rubric.allowed_denominators=Core_denominators(rearranged)
			else:
				var bindings := {"a":integer(1,3),"b":integer(1,3),"c":integer(1,3),"d":integer(1,3),"i":integer(1,3)}
				bindings[target]=integer(1,4)
				var lhs := N.from_text(expression,bindings)
				bindings.p=lhs
				var substituted := rearranged
				for symbol in bindings:substituted=substituted.replace(symbol,"("+N.literal(bindings[symbol])+")")
				set_question("numeric","Isolate %s in p=%s, then calculate using %s. Assume every displayed divisor is nonzero."%[target,expression,str(bindings)],substituted,N.from_text(substituted),reverse_steps+["Substitute the supplied values after rearranging, and check the result in the original formula."],{"kind":"numeric","original":substituted})

func Core_denominators(expression: String) -> Array:
	var parsed := P.new().parse(expression)
	var result: Array=[]
	if parsed.ok:collect_denominators(parsed.ast,result)
	return result

func collect_denominators(ast: Dictionary,result: Array) -> void:
	if ast.get("op","")=="div":result.append(ast.args[1].duplicate(true))
	for child in ast.get("args",[]):collect_denominators(child,result)

func systems() -> void:
	var size := 3 if type in ["system3","determinant3"] or (type=="cramer" and difficulty>=2) else 2
	var matrix: Array=[];var solution: Array=[];var rhs: Array=[]
	for _i in range(size):solution.append(E.q(number(),integer(1,1+difficulty)))
	for i in range(size):
		var row: Array=[]
		for j in range(size):row.append(E.q(number(),integer(1,1+difficulty)))
		matrix.append(row)
	# Strict diagonal dominance guarantees nonsingularity before independent rank validation.
	for i in range(size):
		var sum := E.q(1)
		for j in range(size):
			if i!=j:sum=E.add(sum,E.q(absi(matrix[i][j][0]),matrix[i][j][1]))
		matrix[i][i]=sum
	for row in matrix:
		var value := E.q(0)
		for j in range(size):value=E.add(value,E.mul(row[j],solution[j]))
		rhs.append(value)
	if type=="singular":
		for j in range(size):matrix[1][j]=E.mul(E.q(2),matrix[0][j])
		rhs[1]=E.mul(E.q(2),rhs[0]);var classification := "infinite"
		if integer(0,1)==0:rhs[1]=E.add(rhs[1],E.q(1));classification="none"
		set_question("system","Classify this intentionally singular system as none or infinite solutions.","0",{"classification":classification},["Compare the coefficient rows and augmented constants.","A zero coefficient row with a nonzero constant is inconsistent.","A dependent row with a matching constant leaves a free variable."],{"kind":"system","matrix":matrix,"rhs":rhs})
	elif type in ["determinant2","determinant3"]:
		var determinant := E.determinant(matrix)
		set_question("expression","Evaluate this %d by %d determinant."%[size,size],"0",E.text(determinant),["Choose a row or column and use alternating cofactor signs.","For a 2×2 determinant, multiply the main diagonal and subtract the other product.","Retain exact fractions; check determinant nonzero before using Cramer's rule."],{"kind":"determinant","matrix":matrix})
	elif type=="symbolic":
		var coefficient := integer(1,5);var x := number();var y := number()
		set_question("system","Solve a*x+%d*y=%d*a+(%d), %d*x-a*y=%d-(%d)*a for real parameter a."%[coefficient,x,coefficient*y,coefficient,coefficient*x,y],"0",{"x":str(x),"y":str(y)},["Eliminate one variable symbolically.","The determinant is -(a^2+%d), nonzero for every real a."%[coefficient*coefficient],"Substitution gives x=%d and y=%d for every real a."%[x,y]],{"kind":"symbolic_system","left":["a*x+%d*y"%coefficient,"%d*x-a*y"%coefficient],"right":["%d*a+(%d)"%[x,coefficient*y],"%d-(%d)*a"%[coefficient*x,y]],"coefficient":coefficient})
	else:
		var answer := {};var variables := ["x","y","z"]
		for j in range(size):answer[variables[j]]=E.text(solution[j])
		if type=="cramer":
			var requested := str(variables[integer(0,size-1)])
			for variable in answer.keys():
				if variable!=requested:answer.erase(variable)
		var method := "Cramer's rule" if type=="cramer" else ("substitution" if type=="system2" and integer(0,1)==0 else "elimination")
		var prompt := "Solve this system using %s."%method
		if type=="cramer":prompt+=" Find only "+str(answer.keys()[0])+"."
		set_question("system",prompt,"0",answer,["Arrange coefficients in consistent variable order.","Compute D=det(A); D ≠ 0 ensures one solution.","For Cramer's rule replace the target column by b and compute D_variable / D.","Alternatively eliminate with exact row operations.","Substitute the solution into every original equation."],{"kind":"system","matrix":matrix,"rhs":rhs})
	problem.ast={"kind":"determinant" if type.begins_with("determinant") else "system","matrix":matrix,"rhs":rhs,"variables":["x","y","z"].slice(0,size)}
	var presentation := Worked.matrix_ast(matrix,[] if type.begins_with("determinant") else rhs)
	presentation.op="determinant" if type.begins_with("determinant") else "matrix"
	problem.ast.merge(presentation,true)
	if type=="symbolic":problem.ast={"kind":"symbolic_system","left":problem.parameters.proof.left,"right":problem.parameters.proof.right,"parameter":"a","parameter_domain":"real","variables":["x","y"]}
	problem.input.merge({"rows":size,"columns":size,"symbols":["x","y","z"].slice(0,size)},true)
	if type=="cramer":problem.input.symbols=problem.answer.keys()
	if type=="model":
		var descriptions: PackedStringArray=[];var answer: Dictionary=problem.answer.duplicate(true)
		var fields: Array=[];var rules := {}
		for i in range(2):
			var left := "(%s)*x+(%s)*y"%[E.text(matrix[i][0]),E.text(matrix[i][1])]
			var constant := E.text(rhs[i]);var field := "balance%d"%[i+1]
			descriptions.append("Relationship %d: %s times x plus %s times y totals %s."%[i+1,E.text(matrix[i][0]),E.text(matrix[i][1]),constant])
			answer[field]=left+"-("+constant+")";fields.append({"id":field,"label":"Relationship %d: enter its left side minus right side (equal to zero)"%[i+1]});rules[field]={"form":"equation_zero"}
		for variable in ["x","y"]:fields.append({"id":variable,"label":variable});rules[variable]={"form":"numeric"}
		problem.prompt="\n".join(descriptions)+"\nBuild both equations as expressions equal to zero, then solve x and y. A nonzero multiple of either whole equation is equivalent."
		problem.expected_form="structured";problem.answer=answer;problem.input={"kind":"structured","fields":fields};problem.rubric.fields=rules;problem.parameters.proof.kind="model"
		problem.ast={"kind":"linear_model","op":"text","value":"Translate the two described linear relationships into equations.","statements":Array(descriptions),"variables":["x","y"]}
	problem.parameters.matrix=matrix;problem.parameters.rhs=rhs

func factoring() -> void:
	var a := integer(1,2+difficulty);var b := signed(1,3+difficulty);var c := signed(1,3+difficulty);var n := integer(2,3+difficulty)
	var factor := "";var expression := ""
	match type:
		"gcf":factor="%d*x^%d*(x+(%d))"%[integer(2,6),integer(1,2+difficulty),b]
		"quadratic":factor="(%d*x+(%d))*(x+(%d))"%[a,b,c]
		"grouping":factor="(x+(%d))*(%d*x^2+(%d))"%[b,a,c]
		"squares":factor="(%d*x+(%d))*(%d*x-(%d))"%[a,b,a,b] if integer(0,1)==0 else "(%d*x+(%d))^2"%[a,b]
		"cubes":
			# x^3 ± b^3 with positive b has an irreducible quadratic over Q.
			b=integer(1,4);var sign_value := signed(1,1)
			factor="(x+(%d))*(x^2-(%d)*x+%d)"%[sign_value*b,sign_value*b,b*b]
		"higher":
			factor="%d*x^%d"%[a,integer(1,2)]
			for _i in range(2+difficulty):factor+="*(x+(%d))"%number()
		"method":
			var m := 3 if difficulty>=3 and integer(0,1)==0 else 1
			b=integer(2,6);var method := str(pick(["difference_squares","perfect_square","sum_cubes","difference_cubes"]))
			var u := "x^%d"%m
			var pattern := "(%s)^2-%d"%[u,b*b]
			if method=="perfect_square":pattern="(%s+%d)^2"%[u,b]
			elif method=="sum_cubes":pattern="(%s)^3+%d"%[u,b*b*b]
			elif method=="difference_cubes":pattern="(%s)^3-%d"%[u,b*b*b]
			expression=expanded(pattern)
			set_question("choice","Which listed special-product factoring identity directly matches %s?"%expression,expression,method,["Count the terms and examine the leading and constant powers.","A square trinomial has its middle term twice the product of the square roots.","For two terms, distinguish square and cube powers and the sign between them."],{"kind":"factoring_method","original":expression})
			problem.options=[]
			for option in ["difference_squares","perfect_square","sum_cubes","difference_cubes"]:problem.options.append({"id":option,"text":str(option).capitalize()})
			return
		"binomial","term","first_terms":
			var exponent := integer(2+difficulty,3+difficulty)
			var first := "%d*x"%a;var second := str(b)
			if difficulty>=2:second="%d*y"%b
			expression="(%s+(%s))^%d"%[first,second,exponent]
			if type=="binomial":
				set_question("expanded","Expand using Pascal's triangle or the binomial theorem: "+expression,expression,expanded(expression),["Pascal row n gives the binomial coefficients C(n,k).","Term k+1 is C(n,k) A^(n-k) B^k.","Increase the B power as the A power decreases; keep signed B inside parentheses.","Combine like terms and express all powers positively."])
			elif type=="term":
				var position := integer(1,exponent+1);var k := position-1;var coefficient := N.from_text("choose(%d,%d)"%[exponent,k])
				var term := "(%s)*(%s)^%d*(%s)^%d"%[str(coefficient),first,exponent-k,second,k]
				set_question("expanded","Find term %d (counting from 1) of %s."%[position,expression],term,expanded(term),["Term position r corresponds to k=r-1.","Use C(n,k) A^(n-k) B^k.","Simplify coefficients and powers; the requested term is not the coefficient alone."],{"kind":"identity","original":term})
			else:
				var count := integer(2,exponent);var terms: PackedStringArray=[]
				for k in range(count):terms.append("choose(%d,%d)*(%s)^%d*(%s)^%d"%[exponent,k,first,exponent-k,second,k])
				var partial := "+".join(terms)
				set_question("expanded","Find the first %d terms of %s in descending powers of x."%[count,expression],expression,expanded(partial),["The first term uses k=0, not k=1.","Apply C(n,k) A^(n-k) B^k for k=0 through %d."%[count-1],"Stop at the requested term count; preserve signs and positive powers."],{"kind":"binomial_terms","n":exponent,"first":first,"second":second,"count":count})
			return
		"combination":
			var r := integer(0,n)
			expression="choose(%d,%d)"%[n,r]
			set_question("expression","Evaluate C(%d,%d)."%[n,r],expression,str(int(N.from_text(expression))),["C(n,r)=n!/[r!(n-r)!].","Cancel common factors before multiplying.","C(n,r)=C(n,n-r) provides a quick check."],{"kind":"numeric","original":expression});return
		"factorial":
			var r := integer(1,n)
			expression="factorial(%d)/factorial(%d)"%[n,r]
			set_question("expression","Evaluate exactly: "+expression,expression,E.text(E.scalar(E.parse_normal(expression))),["Expand only the factors above the denominator factorial.","Cancel before multiplying; remember 0!=1."],{"kind":"numeric","original":expression});return
	# Avoid reducible quadratic leaf in grouping: use x² + positive nonsquare constant.
	if type=="grouping":factor="(x+(%d))*(x^2+%d)"%[b,integer(1,6)]
	expression=expanded(factor)
	set_question("factored","Factor completely over rational coefficients: "+expression,expression,factor,["First extract the numerical and variable greatest common factors.","Look for grouping, square/cube patterns or a pair of binomial factors.","Continue until each remaining nonconstant factor is irreducible over rational coefficients.","Multiply the factors back out to verify the original polynomial."],{"kind":"factor","original":expression,"reference":factor})

func rational() -> void:
	var a := number();var b := a+integer(1,3);var c := b+integer(1,3);var k := number()
	var fa := "(x-(%d))"%a;var fb := "(x-(%d))"%b;var fc := "(x-(%d))"%c
	var expression := "";var answer := "";var excluded: Array=[str(a),str(b)]
	match type:
		"reduce","restrictions":expression="(%s*%s)/(%s*%s)"%[fa,fc,fa,fb];answer="%s/%s"%[fc,fb]
		"multiply":expression="(%s/%s)*(%s/%s)"%[fa,fb,fb,fc];answer="%s/%s"%[fa,fc];excluded=[str(b),str(c)]
		"divide":expression="(%s/%s)/(%s/%s)"%[fa,fb,fc,fb];answer="%s/%s"%[fa,fc];excluded=[str(b),str(c)]
		"add":
			var sign_value := signed(1,1)
			expression="%d/%s+(%d)/%s"%[k,fa,sign_value*k,fb]
			answer="(%d*%s+(%d)*%s)/(%s*%s)"%[k,fb,sign_value*k,fa,fa,fb]
		"complex":expression="(1/%s)/(1/%s)"%[fa,fb];answer="%s/%s"%[fb,fa]
		"equation","extraneous":
			var solution := c
			expression="(%s*(x-(%d)))/(%s*%s)"%[fa,solution,fa,fb]
			if type=="extraneous":expression="(%s^2)/(%s*%s)"%[fa,fa,fb]
			set_question("solutions","Solve %s = 0 and reject every original denominator zero."%expression,expression,[] if type=="extraneous" else [str(solution)],["Original denominator restrictions: x ≠ %d and x ≠ %d."%[a,b],"A zero rational expression needs a zero numerator and a nonzero denominator.","Canceling a factor does not restore its excluded input.","Check candidates in the original expression."],{"kind":"equation","left":expression,"right":"0","variable":"x","excluded":excluded});return
	if type=="restrictions":
		set_question("restrictions","List all original excluded x values for "+expression,expression,excluded,["Set every original denominator factor equal to zero.","Do this before cancellation.","A restriction is a value, not a simplified denominator."],{"kind":"restrictions","original":expression,"excluded":excluded});return
	set_question("rational","Simplify fully and list all original excluded values: "+expression,expression,{"expression":answer,"excluded":excluded},["Factor every numerator and denominator.","Record every denominator zero and any zero divisor before cancellation.","For addition use a common denominator; for division multiply by the reciprocal.","Cancel common factors, never terms across an addition.","Retain the original restrictions in the final answer."],{"kind":"rational","original":expression,"excluded":excluded})
	problem.rubric.reduced_factors=excluded
	problem.input.fields=[{"id":"expression","label":"Simplified expression"},{"id":"excluded","label":"Original excluded x values","kind":"solutions"}]

func radicals() -> void:
	var a := integer(2,4+difficulty);var prime := int(pick([2,3,5,7,11,13]));var b := integer(1,3+difficulty)
	var index := integer(2,mini(6,2+difficulty));var root_name := "sqrt" if index==2 else "cbrt" if index==3 else "root"
	var root_prefix := root_name+"("+(str(index)+"," if index>3 else "")
	var root_expression := root_prefix+str(prime)+")"
	var expression := "";var answer := ""
	match type:
		"simplify":expression=root_prefix+str(int(pow(a,index))*prime)+")";answer="%d*%s"%[a,root_expression]
		"combine":expression=root_prefix+str(int(pow(a,index))*prime)+")+(%d)*%s-"%[b,root_expression]+root_prefix+str(int(pow(2,index))*prime)+")";answer="%d*%s"%[a+b-2,root_expression]
		"product":
			prime=int(pick([2,3]));a=integer(2,5);b=integer(1,5)
			expression=root_prefix+str(int(pow(a,index))*prime)+")*"+root_prefix+str(int(pow(b,index))*int(pow(prime,index-1)))+")";answer=str(a*b*prime)
		"rationalize":expression="%d/%s"%[a,root_expression];answer="(%d*%s%d))/%d"%[a,root_prefix,int(pow(prime,index-1)),prime]
		"conjugate":
			if a*a==prime:a+=1
			expression="%d/(%d+sqrt(%d))"%[b,a,prime];answer="(%s)+(%s)*sqrt(%d)"%[E.text(E.q(b*a,a*a-prime)),E.text(E.q(-b,a*a-prime)),prime]
		"powers":
			var power_index := integer(2,mini(6,2+difficulty));var numerator := integer(1,power_index+1);var negative := difficulty>=2 and integer(0,1)==1
			expression="%d^(%d/%d)"%[int(pow(a,power_index)),(-1 if negative else 1)*numerator,power_index]
			answer="1/%d"%int(pow(a,numerator)) if negative else str(int(pow(a,numerator)))
		"nested":
			# sqrt(a+b+2sqrt(ab)) = sqrt(a)+sqrt(b), distinct squarefree primes.
			var other := int(pick([2,3,5,7]));while other==prime:other=int(pick([2,3,5,7]))
			expression="sqrt(%d+2*sqrt(%d))"%[prime+other,prime*other];answer="sqrt(%d)+sqrt(%d)"%[prime,other]
			set_question("radical","Simplify the nested radical exactly: "+expression,expression,answer,["Compare with (sqrt(u)+sqrt(v))^2=u+v+2sqrt(uv).","Find positive u and v with the required sum and product.","The principal root is nonnegative, so choose the positive sum."],{"kind":"nested_radical","u":prime,"v":other});return
		"equation":
			# sqrt(k*x+r²-k*r)=x has candidate roots r and k-r, then original check.
			var root := integer(1,3+difficulty);var k := integer(1,4+difficulty);var constant := root*root-k*root
			var solved := S.radical_equation(k,constant,1,0)
			expression="sqrt(%d*x+(%d))"%[k,constant]
			set_question("solutions","Solve %s = x over the reals; check every candidate."%expression,expression,solved.get("values",[]),["Require the radicand and right-hand side to be nonnegative.","Square both sides to obtain x²-%d*x-(%d)=0."%[k,constant],"Solve the quadratic, then substitute each candidate into the original unsquared equation.","Reject any extraneous candidate introduced by squaring."],{"kind":"radical_equation","a":k,"b":constant,"c":1,"d":0});return
		"variables":
			var n := integer(1,2+difficulty)
			expression="sqrt(%d*x^%d)"%[a*a,2*n]
			answer="%d*x^%d"%[a,n]
			set_question("expression","Simplify %s assuming x ≥ 0. (Without that assumption an absolute value may be required.)"%expression,expression,answer,["Separate the perfect-square coefficient and even variable power.","The principal square root is nonnegative.","The stated x ≥ 0 assumption permits x^n instead of |x^n|."],{"kind":"variable_radical","a":a,"n":n,"domain":"x>=0"});return
	set_question("radical","Simplify exactly, rationalizing any denominator: "+expression,expression,answer,["Extract perfect powers from the radicand.","Combine only radicals with the same index and radicand.","Multiply by a suitable radical or conjugate to rationalize a denominator.","Keep an exact radical rather than replacing it with a decimal."],{"kind":"radical_identity","original":expression})

func trigonometry() -> void:
	var angles := [0,30,45,60,90,120,135,150,180,210,225,240,270,300,315,330]
	var angle := int(pick(angles.slice(0,5) if difficulty==0 else angles));var expression := ""
	match type:
		"ratio","reciprocal":
			var function := str(pick(["sin","cos","tan"] if type=="ratio" else ["sec","csc","cot"]))
			expression="%s(%d)"%[function,angle]
			var value := N.from_text(expression)
			if not is_finite(value):angle=30;expression="%s(%d)"%[function,angle];value=N.from_text(expression)
			if absf(value)<1e-14:value=0.0
			set_question("numeric","Evaluate %s in degree mode; give at least six significant figures."%expression,expression,value,["Locate the angle on the unit circle and determine its quadrant.","Use the appropriate side ratio or reciprocal.","Check whether the denominator is zero before evaluating."],{"kind":"numeric","original":expression})
			problem.rubric=six_figure_tolerance(value)
		"quadrant","sign":
			angle=integer(-3-difficulty,3+difficulty)*360+integer(1,89)+integer(0,3)*90
			var reduced := posmod(angle,360);var quadrant := int(reduced/90)+1
			var function := str(pick(["sin","cos","tan"]))
			var answer := str(quadrant)
			var prompt := "In which quadrant does %d degrees terminate? Enter 1, 2, 3, or 4."%angle
			if type=="sign":answer="positive" if N.from_text("%s(%d)"%[function,angle])>0 else "negative";prompt="Is %s(%d degrees) positive or negative?"%[function,angle]
			set_question("choice",prompt,str(angle),answer,["Reduce by whole turns of 360 degrees.","Locate the terminal side; these generated angles are not on an axis.","Sine follows y, cosine follows x, and tangent follows y/x."],{"kind":"quadrant","angle":angle,"function":function,"ask_sign":type=="sign"})
			problem.options=[{"id":"positive","text":"Positive"},{"id":"negative","text":"Negative"}] if type=="sign" else [{"id":"1","text":"I"},{"id":"2","text":"II"},{"id":"3","text":"III"},{"id":"4","text":"IV"}]
		"coterminal":
			angle=integer(-8,8)*360+integer(0,359)
			set_question("numeric","Find the coterminal angle of %d degrees in [0,360)."%angle,str(posmod(angle,360)),posmod(angle,360),["Add or subtract an integer number of complete 360-degree turns.","Keep the unique representative at least zero and below 360."],{"kind":"coterminal","angle":angle})
		"equation":
			var function := str(pick(["sin","cos","tan"]));var alpha := int(pick([30,45,60]));var target := N.from_text("%s(%d)"%[function,alpha])
			var scale := integer(1,1+difficulty);var shift := integer(-2,2)*30 if difficulty>=2 else 0
			var lo := -360.0 if difficulty>=3 else 0.0;var hi := 720.0 if difficulty==4 else 360.0
			var solutions := N.trig_solutions(function,target,lo,hi,scale,shift)
			expression="%s(%d*x+(%d))"%[function,scale,shift]
			set_question("solutions","Find ALL x in [%s,%s] degrees satisfying %s = %s."%[str(lo),str(hi),expression,str(target)],expression,solutions,["Find a reference angle with an inverse trigonometric function.","Use both sine/cosine branches or the tangent period, including negative and positive turns.","Solve %d*x+(%d)=each admissible phase angle."%[scale,shift],"Filter to the closed requested interval and remove duplicate boundary values."],{"kind":"trig_equation","function":function,"target":target,"lo":lo,"hi":hi,"scale":scale,"shift":shift})
			problem.rubric.merge({"absolute_tolerance":0.0001,"relative_tolerance":1e-8})
		"identity":
			var identities := [{"left":"sin(x)^2+cos(x)^2","right":"1","restriction":"all real x"},{"left":"(1-cos(x)^2)/sin(x)","right":"sin(x)","restriction":"sin(x) != 0"},{"left":"sec(x)^2-tan(x)^2","right":"1","restriction":"cos(x) != 0"},{"left":"(1-sin(x)^2)/(cos(x)^2)","right":"1","restriction":"cos(x) != 0"},{"left":"tan(x)*cos(x)","right":"sin(x)","restriction":"cos(x) != 0"}]
			var chosen: Dictionary=pick(identities);var multiplier := integer(1,2+difficulty)
			expression="%d*(%s)"%[multiplier,chosen.left];var answer := "%d*(%s)"%[multiplier,chosen.right]
			if difficulty>=2:expression+="+sin(x)^2";answer+="+sin(x)^2"
			set_question("expression","Simplify using trig identities: %s. Original domain: %s."%[expression,chosen.restriction],expression,answer,["Rewrite reciprocal and quotient functions in sine and cosine.","Use sin²(x)+cos²(x)=1 while retaining the original domain.","Cancel factors only on inputs where the original expression exists.","An identity proof applies to every input in the stated domain, not a few samples."],{"kind":"identity","original":expression})
		"right":
			var leg_a := float(integer(3,8+difficulty));var leg_b := float(integer(4,9+difficulty));var hyp := sqrt(leg_a*leg_a+leg_b*leg_b)
			var descriptor := N.triangle(leg_a,leg_b,hyp);descriptor.given=["a","b","C"];descriptor.unknown=["c","A","B"]
			set_question("structured","In this right triangle C=90 degrees, a=%s and b=%s. Find c, A and B (degrees)."%[str(leg_a),str(leg_b)],"0",{"c":hyp,"A":descriptor.angles.A,"B":descriptor.angles.B},["Use c²=a²+b² for the hypotenuse.","Use atan(a/b) for A, because side a is opposite A.","The two acute angles sum to 90 degrees."],{"kind":"triangle","descriptor":descriptor,"fields":["c","A","B"]})
			problem.diagram=descriptor
		"cosine_law","sine_law":
			var side_a := float(integer(3,8+difficulty));var side_b := float(integer(3,8+difficulty));var C := float(integer(35,120));var side_c := sqrt(side_a*side_a+side_b*side_b-2*side_a*side_b*cos(deg_to_rad(C)))
			var descriptor := N.triangle(side_a,side_b,side_c)
			var given := ["a","b","C"] if type=="cosine_law" else ["a","A","B"]
			descriptor.given=given;descriptor.unknown=["a","b","c","A","B","C"].filter(func(v):return v not in given)
			var answer := {};var information: PackedStringArray=[]
			for field in ["a","b","c","A","B","C"]:
				var value := float(descriptor.sides.get(field,descriptor.angles.get(field,0)))
				if field in given:information.append(field+"="+str(value))
				else:answer[field]=value
			set_question("structured","Solve the non-right triangle with %s. Use degrees."%[", ".join(information)],"0",answer,["Match each lower-case side to its opposite upper-case angle.","For SAS, use c²=a²+b²-2ab cos(C) first.","For two known angles, find the third from 180 degrees, then apply a/sin(A)=b/sin(B)=c/sin(C).","Check the angle sum, side inequalities, and law of cosines."],{"kind":"triangle","descriptor":descriptor,"fields":answer.keys()})
			problem.diagram=descriptor
		"ssa":
			var A := float(integer(20,45));var bside := float(integer(8,16));var height := bside*sin(deg_to_rad(A))
			var case_type := integer(0,2);var aside := (height+bside)/2.0 if case_type==0 else (bside+integer(1,4) if case_type==1 else height*0.8)
			var solutions := N.ssa(A,aside,bside)
			set_question("triangle","SSA: A=%s degrees, a=%s, b=%s. Find all valid triangles, or an empty set if none. Report A,B,C,a,b,c."%[str(A),str(aside),str(bside)],"0",{"solutions":solutions},["Compute sin(B)=b*sin(A)/a.","If it exceeds 1, no real triangle exists.","Consider B=asin(value) and B=180-asin(value).","Keep only branches with C=180-A-B>0, then use the sine law for c.","Two possible triangles must both be reported."],{"kind":"ssa","A":A,"a":aside,"b":bside})
			if not solutions.is_empty():
				var first: Dictionary=solutions[0];problem.diagram=N.triangle(first.a,first.b,first.c);problem.diagram.given=["A","a","b"];problem.diagram.unknown=["B","C","c"];problem.diagram.alternatives=[]
				for item in solutions:problem.diagram.alternatives.append(N.triangle(item.a,item.b,item.c))
			else:problem.diagram={"kind":"triangle_conditions","A":A,"a":aside,"b":bside,"given":["A","a","b"]}
	if problem.expected_form in ["structured","triangle"]:
		problem.rubric.merge({"absolute_tolerance":0.0001,"relative_tolerance":0.00001})
		if problem.answer is Dictionary and problem.expected_form=="structured":
			problem.input.fields=[];problem.rubric.fields={}
			for field in problem.answer:problem.input.fields.append({"id":field,"label":field});problem.rubric.fields[field]={"form":"numeric","absolute_tolerance":0.0001,"relative_tolerance":0.00001}
	if type in ["right","cosine_law","sine_law"]:
		var givens := {}
		for field in problem.diagram.given:givens[field]=problem.diagram.sides.get(field,problem.diagram.angles.get(field,0))
		problem.ast={"kind":"triangle","given":givens,"angle_unit":"degrees"}
	elif type=="ssa":problem.ast={"kind":"ssa","A":problem.parameters.proof.A,"a":problem.parameters.proof.a,"b":problem.parameters.proof.b,"angle_unit":"degrees"}

func sinusoids() -> void:
	var amplitude := float(integer(1,3+2*difficulty))*(-1.0 if difficulty>=2 and integer(0,1)==0 else 1.0)
	var period := float(integer(2,8))*pow(10.0,-integer(0,difficulty))
	var phase := period*integer(-4,4)/8.0 if difficulty>=1 else 0.0
	var offset := float(number()) if difficulty>=2 else 0.0
	var kind := str(pick(["sin","cos"]));var function := {"kind":kind,"amplitude":amplitude,"period":period,"phase":phase,"offset":offset}
	var domain := [phase,phase+period];var points: Array=[]
	for i in range(5):
		var x := phase+period*i/4.0;var y := N.wave(function,x);var role := "critical"
		if N.close(y,offset+absf(amplitude)):role="peak"
		elif N.close(y,offset-absf(amplitude)):role="trough"
		elif offset==0:role="intercept"
		points.append({"x":x,"y":y,"role":role,"label":"P%d"%i})
	var descriptor := {"kind":"sinusoid","function":function,"domain":domain,"range":[offset-absf(amplitude)*1.3,offset+absf(amplitude)*1.3],"points":points,"x_label":"Time (s)","y_label":"Displacement (units)","angle_unit":"degrees","degrees":true}
	var expression := "%s+(%s)*%s(360*(x-(%s))/(%s))"%[str(offset),str(amplitude),kind,str(phase),str(period)]
	var steps := ["Compare y=D+A*%s(360*(t-h)/T) with the generated equation."%kind,"Amplitude is |A|; a negative A reflects about the midline y=D.","The horizontal shift is h; period is T seconds and frequency is 1/T hertz.","Critical points are spaced T/4 apart. Evaluate the original function at each coordinate.","Use the full cycle and unit-labelled axes to check maxima, minima and crossings."]
	match type:
		"characteristics","transform":
			var answer := {"amplitude":absf(amplitude),"period":period,"frequency":1.0/period,"phase":phase,"midline":offset,"maximum":offset+absf(amplitude),"minimum":offset-absf(amplitude)}
			set_question("structured","For y=%s, find amplitude, period (s), frequency (Hz), displayed horizontal shift (s), midline, maximum and minimum. Report the shift in this displayed form."%expression,expression,answer,steps,{"kind":"wave","function":function,"fields":answer.keys()})
			if type=="transform":problem.prompt+=" Explain the reflection using the sign of A in your working."
		"frequency":
			set_question("numeric","A sinusoidal waveform repeats every %s s. Find its frequency in Hz."%str(period),"1/(%s)"%str(period),1.0/period,steps,{"kind":"numeric","original":"1/(%s)"%str(period)})
		"table","critical":
			var answer := {};var input_fields: Array=[]
			for i in range(5):answer["y%d"%i]=points[i].y;input_fields.append({"id":"y%d"%i,"label":"y at t=%s s"%str(points[i].x)})
			set_question("structured","For y=%s, fill the five one-cycle critical-point ordinates at the listed times."%expression,expression,answer,steps,{"kind":"wave","function":function,"points":points,"fields":answer.keys()})
			problem.input.fields=input_fields
		"compare":
			var other := function.duplicate(true);other.amplitude*=2;other.period*=integer(2,4);other.phase+=period/4
			var answer := {"amplitude_ratio":absf(float(other.amplitude)/amplitude),"period_ratio":float(other.period)/period,"frequency_ratio":period/float(other.period),"shift_change":float(other.phase)-phase}
			set_question("structured","Compare wave B to A: A=%s; B has A=%s, T=%s s, h=%s s and D=%s. Find B/A amplitude, period and frequency ratios, plus h_B-h_A."%[expression,str(other.amplitude),str(other.period),str(other.phase),str(other.offset)],expression,answer,steps,{"kind":"wave_compare","function":function,"other":other})
			descriptor.curves=[function,other]
		"equation":
			var prompt := "Infer a sinusoidal equation from the generated graph. Submit its function parameters (sin/cos, signed amplitude, period, phase, offset). Equivalent phases and sine/cosine forms are accepted."
			if integer(0,1)==1:
				var crossing: float=phase+(period/4 if kind=="cos" else 0.0)
				var rising := amplitude<0 if kind=="cos" else amplitude>0
				prompt="A waveform has maximum %s, minimum %s and period %s s. At t=%s s it crosses its midline %s. Construct any equivalent sine or cosine equation by entering its function parameters."%[N.literal(offset+absf(amplitude)),N.literal(offset-absf(amplitude)),N.literal(period),N.literal(crossing),"rising" if rising else "falling"]
			set_question("graph",prompt,expression,{"function":function,"points":[],"domain":domain},steps,{"kind":"wave","function":function,"fields":[]})
			problem.input.mode="function";problem.input.fields=[{"id":"amplitude","label":"Signed amplitude"},{"id":"period","label":"Period (s)"},{"id":"phase","label":"Phase (s)"},{"id":"offset","label":"Offset"}]
		"zeros":
			var phases := N.trig_solutions(kind,-offset/amplitude,0,360)
			var values: Array=[]
			for angle in phases:values.append(phase+period*float(angle)/360)
			set_question("solutions","Find every zero (including tangent touches) of y=%s for t in [%s,%s] seconds. If there are none, submit an explicit empty set."%[expression,N.literal(domain[0]),N.literal(domain[1])],expression,values,steps+["Solve the sine/cosine phase equation with target -D/A, retain every phase in the closed cycle, then convert phase to time."],{"kind":"wave_zeros","function":function,"domain":domain})
			problem.rubric={"absolute_tolerance":period*1e-5,"relative_tolerance":1e-7}
		"graph":
			set_question("graph","Graph one full cycle of y=%s for t in [%s,%s] seconds. Place all five critical points, label peaks/troughs/crossings and mark the period."%[expression,str(domain[0]),str(domain[1])],expression,descriptor.duplicate(true),steps,{"kind":"wave","function":function,"points":points,"fields":[]})
			problem.rubric.require_period=true
			problem.answer.period=period
	if type=="table":
		var row: Array=[];var blank: Array=[];var columns: Array=[]
		for i in range(5):row.append(N.literal(points[i].y));blank.append("");columns.append({"id":"y%d"%i,"label":"t=%s s"%N.literal(points[i].x)})
		problem.expected_form="table";problem.answer={"rows":[row]};problem.input={"kind":"table","columns":columns,"rows":[blank]};problem.rubric={"absolute_tolerance":1e-8,"relative_tolerance":0.00001}
	problem.diagram=descriptor
	problem.parameters.function=function
	if problem.expected_form=="structured":
		problem.rubric.fields={}
		if not problem.input.has("fields"):problem.input.fields=[]
		for field in problem.answer:
			if not problem.input.fields.any(func(f):return f.id==field):problem.input.fields.append({"id":field,"label":str(field).capitalize()})
			problem.rubric.fields[field]={"form":"numeric","absolute_tolerance":1e-8,"relative_tolerance":0.00001}
