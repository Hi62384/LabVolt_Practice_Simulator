extends RefCounted
## Checked rational arithmetic and sparse multivariate rational functions.
## Invalid/overflow results are empty arrays/dictionaries, never approximate equality.
const LIMIT: int = 1000000000000
const Parser = preload("res://scripts/mth147/parser.gd")

static func gcd(a: int,b: int) -> int:
	a=absi(a);b=absi(b)
	while b!=0:
		var t := a%b;a=b;b=t
	return maxi(1,a)

static func q(n: int,d: int=1) -> Array:
	if d==0 or n< -LIMIT or n>LIMIT or d< -LIMIT or d>LIMIT:return []
	var g := gcd(n,d)
	return [int(n/g)*(1 if d>0 else -1),int(absi(d)/g)]

static func mul(a: Array,b: Array) -> Array:
	if a.is_empty() or b.is_empty():return []
	var g := gcd(a[0],b[1]);var h := gcd(b[0],a[1])
	var n := int(a[0]/g);var m := int(b[0]/h);var d := int(a[1]/h);var e := int(b[1]/g)
	if (m!=0 and absi(n)>int(LIMIT/absi(m))) or d>int(LIMIT/e):return []
	return q(n*m,d*e)

static func add(a: Array,b: Array) -> Array:
	if a.is_empty() or b.is_empty():return []
	var g := gcd(a[1],b[1]);var d := int(a[1]/g);var e := int(b[1]/g)
	if absi(a[0])>int(LIMIT/e) or absi(b[0])>int(LIMIT/d) or d>int(LIMIT/b[1]):return []
	var n := int(a[0])*e+int(b[0])*d
	return q(n,d*int(b[1]))

static func neg(a: Array) -> Array:
	return [-int(a[0]),int(a[1])] if not a.is_empty() else []

static func divq(a: Array,b: Array) -> Array:
	return mul(a,q(b[1],b[0])) if not b.is_empty() else []

static func power(a: Array,n: int) -> Array:
	if absi(n)>24 or a.is_empty():return []
	if n<0:return power(q(a[1],a[0]),-n)
	var out := q(1)
	for _i in range(n):out=mul(out,a)
	return out

static func decimal(s: String) -> Array:
	s=s.to_lower();var chunks := s.split("e")
	if chunks.size()>2:return []
	var exponent := int(chunks[1]) if chunks.size()==2 else 0
	if absi(exponent)>24:return []
	var value := str(chunks[0]);var sign_value := -1 if value.begins_with("-") else 1
	value=value.trim_prefix("-").trim_prefix("+")
	var parts := value.split(".")
	if parts.size()>2:return []
	var digits := "".join(parts)
	if digits.is_empty() or not digits.is_valid_int() or digits.length()>13:return []
	exponent-=parts[1].length() if parts.size()==2 else 0
	var result := q(sign_value*int(digits))
	# Values outside exact integer bound are available through numeric validator only.
	return mul(result,power(q(10),exponent))

static func text(a: Array) -> String:
	if a.is_empty():return "undefined"
	return str(a[0]) if a[1]==1 else "%s/%s"%[a[0],a[1]]

static func value(a: Array) -> float:
	return float(a[0])/float(a[1]) if not a.is_empty() else NAN

static func pconstant(a: Array) -> Dictionary:
	return {"":a} if not a.is_empty() else {}

static func psymbol(name: String) -> Dictionary:
	return {name+":1":q(1)}

static func powers(key: String) -> Dictionary:
	var out := {}
	if key.is_empty():return out
	for item in key.split("|"):
		var pair := item.split(":");out[pair[0]]=int(pair[1])
	return out

static func key_of(p: Dictionary) -> String:
	var names := p.keys();names.sort();var parts: PackedStringArray=[]
	for name in names:
		if int(p[name])!=0:parts.append(str(name)+":"+str(p[name]))
	return "|".join(parts)

static func clean(p: Dictionary) -> Dictionary:
	if p.is_empty():return {}
	var out := {}
	for key in p:
		if p[key].is_empty():return {}
		if p[key][0]!=0:out[key]=p[key]
	if out.is_empty():out[""]=q(0)
	return out

static func padd(a: Dictionary,b: Dictionary,subtract: bool=false) -> Dictionary:
	if a.is_empty() or b.is_empty():return {}
	var out := a.duplicate(true)
	for key in b:
		out[key]=add(out.get(key,q(0)),neg(b[key]) if subtract else b[key])
		if out[key].is_empty():return {}
	return clean(out)

static func pmul(a: Dictionary,b: Dictionary) -> Dictionary:
	if a.is_empty() or b.is_empty() or a.size()*b.size()>4096:return {}
	var out := {}
	for ka in a:
		for kb in b:
			var exps := powers(ka);var degree := 0;var coefficient := mul(a[ka],b[kb])
			for symbol in powers(kb):exps[symbol]=int(exps.get(symbol,0))+int(powers(kb)[symbol])
			# Constant radicals carry prime exponents; reduce powers by the root index.
			var radical_powers := {}
			for symbol in exps.keys():
				if str(symbol).begins_with("r") and "_" in str(symbol):
					var pair := str(symbol).substr(1).split("_");var index := int(pair[0]);var prime := int(pair[1])
					radical_powers[prime]=add(radical_powers.get(prime,q(0)),q(int(exps[symbol]),index));exps.erase(symbol)
			for prime in radical_powers:
				var exponent: Array=radical_powers[prime]
				if exponent.is_empty():return {}
				coefficient=mul(coefficient,power(q(int(prime)),int(int(exponent[0])/int(exponent[1]))))
				var remainder := q(int(exponent[0])%int(exponent[1]),int(exponent[1]))
				if remainder[0]!=0:exps["r%d_%d"%[remainder[1],prime]]=remainder[0]
			for symbol in exps:
				degree+=int(exps[symbol])
			if degree>24 or coefficient.is_empty():return {}
			var key := key_of(exps)
			out[key]=add(out.get(key,q(0)),coefficient)
			if out[key].is_empty() or out.size()>128:return {}
	return trig_reduce(clean(out))

static func trig_reduce(p: Dictionary) -> Dictionary:
	# Deterministic algebraic identity cos(t)^2 = 1 - sin(t)^2.
	var result := p.duplicate(true)
	for _pass in range(24):
		var changed := false
		for key in result.keys():
			var exps := powers(key)
			for name in exps:
				if str(name).begins_with("C_") and int(exps[name])>=2:
					var c: Array=result[key];result.erase(key);exps[name]-=2
					var k1 := key_of(exps);result[k1]=add(result.get(k1,q(0)),c)
					var sin_name := "S_"+str(name).substr(2);exps[sin_name]=int(exps.get(sin_name,0))+2
					var k2 := key_of(exps);result[k2]=add(result.get(k2,q(0)),neg(c));changed=true;break
			if changed:break
		if not changed:return clean(result)
	return {}

static func ppow(p: Dictionary,n: int) -> Dictionary:
	if n<0 or n>12:return {}
	var out := pconstant(q(1))
	for _i in range(n):out=pmul(out,p)
	return out

static func rf(n: Dictionary,d: Dictionary={"": [1,1]}) -> Dictionary:
	if n.is_empty() or d.is_empty() or pzero(d):return {}
	if d.size()==1 and d.has(""):
		var normalized := {}
		for key in n:
			normalized[key]=divq(n[key],d[""])
			if normalized[key].is_empty():return {}
		return {"n":clean(normalized),"d":pconstant(q(1))}
	return {"n":n,"d":d}

static func pzero(p: Dictionary) -> bool:
	return not p.is_empty() and clean(p).size()==1 and clean(p).has("") and clean(p)[""][0]==0

static func combine(a: Dictionary,b: Dictionary,op: String) -> Dictionary:
	if a.is_empty() or b.is_empty():return {}
	match op:
		"add","sub":return rf(padd(pmul(a.n,b.d),pmul(b.n,a.d),op=="sub"),pmul(a.d,b.d))
		"mul":return rf(pmul(a.n,b.n),pmul(a.d,b.d))
		"div":return rf(pmul(a.n,b.d),pmul(a.d,b.n))
	return {}

static func scalar(a: Dictionary) -> Array:
	if a.is_empty() or a.n.size()!=1 or a.d.size()!=1 or not a.n.has("") or not a.d.has(""):return []
	return divq(a.n[""],a.d[""])

static func radical(a: Array,index: int) -> Dictionary:
	if a.is_empty() or index<2 or index>6 or (a[0]<0 and index%2==0):return {}
	if a[0]==0:return rf(pconstant(q(0)))
	var result := rf(pconstant(q(-1 if a[0]<0 else 1)))
	for part in [[absi(a[0]),false],[a[1],true]]:
		var n := int(part[0]);var outside := 1;var exps := {};var prime := 2
		if n>100000000:return {}
		while prime*prime<=n:
			var exponent := 0
			while n%prime==0:n=int(n/prime);exponent+=1
			if exponent>0:
				outside*=int(pow(prime,int(exponent/index)))
				if exponent%index!=0:exps["r%d_%d"%[index,prime]]=exponent%index
			prime+=1
		if n>1:exps["r%d_%d"%[index,n]]=int(exps.get("r%d_%d"%[index,n],0))+1
		var poly := pmul({key_of(exps):q(outside)},pconstant(q(1)))
		result=combine(result,rf(poly),"div" if part[1] else "mul")
	return result

static func rational_sqrt(a: Array) -> Array:
	if a.is_empty() or a[0]<0:return []
	var n := int(round(sqrt(float(a[0]))));var d := int(round(sqrt(float(a[1]))))
	return q(n,d) if n*n==int(a[0]) and d*d==int(a[1]) else []

static func nested_square_root(a: Dictionary) -> Dictionary:
	if a.is_empty() or a.n.size()!=2 or a.d.size()!=1 or not a.d.has("") or not a.n.has(""):return {}
	var constant := divq(a.n[""],a.d[""]);var radical_key := ""
	for key in a.n:
		if key!="":radical_key=key
	var exps := powers(radical_key);var squarefree := q(1)
	for name in exps:
		if not str(name).begins_with("r2_") or exps[name]!=1:return {}
		squarefree=mul(squarefree,q(int(str(name).substr(3))))
	var coefficient := divq(a.n[radical_key],a.d[""])
	var discriminant := add(mul(constant,constant),neg(mul(mul(coefficient,coefficient),squarefree)))
	var root := rational_sqrt(discriminant)
	if root.is_empty():return {}
	var u := divq(add(constant,root),q(2));var v := divq(add(constant,neg(root)),q(2))
	if u.is_empty() or v.is_empty() or u[0]<0 or v[0]<0:return {}
	return combine(radical(u,2),radical(v,2),"add" if coefficient[0]>=0 else "sub")

static func angle_pair(ast: Dictionary,depth: int=0) -> Dictionary:
	# Exact angle-addition proof in the sin/cos polynomial ring. Supports sums,
	# differences, negation and bounded integer multiples; no value sampling.
	if depth>16:return {}
	var op := str(ast.get("op",""));var args: Array=ast.get("args",[])
	var one := rf(pconstant(q(1)));var zero := rf(pconstant(q(0)))
	if op=="symbol" and ast.name!="pi":return {"s":rf(psymbol("S_"+str(ast.name))),"c":rf(psymbol("C_"+str(ast.name)))}
	if op=="num" and scalar(normalize(ast))==q(0):return {"s":zero,"c":one}
	if op=="neg":
		var pair := angle_pair(args[0],depth+1)
		return {"s":combine(rf(pconstant(q(-1))),pair.s,"mul"),"c":pair.c} if not pair.is_empty() else {}
	if op in ["add","sub"]:
		var a := angle_pair(args[0],depth+1);var b := angle_pair(args[1],depth+1)
		if a.is_empty() or b.is_empty():return {}
		var sine := combine(combine(a.s,b.c,"mul"),combine(a.c,b.s,"mul"),"add" if op=="add" else "sub")
		var cosine := combine(combine(a.c,b.c,"mul"),combine(a.s,b.s,"mul"),"sub" if op=="add" else "add")
		return {"s":sine,"c":cosine} if not sine.is_empty() and not cosine.is_empty() else {}
	if op=="mul":
		var factor := scalar(normalize(args[0]));var inner: Dictionary=args[1]
		if factor.is_empty():factor=scalar(normalize(args[1]));inner=args[0]
		if factor.is_empty() or factor[1]!=1 or absi(factor[0])>6:return {}
		var pair := angle_pair(inner,depth+1)
		if pair.is_empty():return {}
		var sine := zero;var cosine := one
		for _i in range(absi(factor[0])):
			var next_sine := combine(combine(sine,pair.c,"mul"),combine(cosine,pair.s,"mul"),"add")
			var next_cosine := combine(combine(cosine,pair.c,"mul"),combine(sine,pair.s,"mul"),"sub")
			sine=next_sine;cosine=next_cosine
			if sine.is_empty() or cosine.is_empty():return {}
		if factor[0]<0:sine=combine(rf(pconstant(q(-1))),sine,"mul")
		return {"s":sine,"c":cosine}
	return {}

static func normalize(ast: Dictionary,depth: int=0) -> Dictionary:
	if depth>24 or ast.is_empty():return {}
	var op := str(ast.get("op",""))
	if op=="num":return rf(pconstant(decimal(str(ast.value))))
	if op=="symbol":return rf(psymbol(str(ast.name)))
	var args: Array=ast.get("args",[])
	if args.is_empty():return {}
	var a := normalize(args[0],depth+1)
	if op=="neg":return combine(rf(pconstant(q(-1))),a,"mul")
	if op in ["add","sub","mul","div"]:return combine(a,normalize(args[1],depth+1),op)
	if op=="pow":
		var exponent := scalar(normalize(args[1],depth+1))
		if exponent.is_empty():return {}
		if exponent[0]==0 and not a.is_empty() and pzero(a.n):return {}
		if exponent[1]!=1:
			var base := scalar(a)
			if base.is_empty():return {}
			var r := radical(base,int(exponent[1]))
			if r.is_empty():return {}
			return rf(ppow(r.n,absi(exponent[0])),ppow(r.d,absi(exponent[0]))) if exponent[0]>=0 else rf(ppow(r.d,absi(exponent[0])),ppow(r.n,absi(exponent[0])))
		if absi(exponent[0])>12 or a.is_empty():return {}
		return rf(ppow(a.n,absi(exponent[0])),ppow(a.d,absi(exponent[0]))) if exponent[0]>=0 else rf(ppow(a.d,absi(exponent[0])),ppow(a.n,absi(exponent[0])))
	if op in ["sqrt","cbrt","root"]:
		var index := 2 if op=="sqrt" else 3
		var radicand := scalar(a)
		if op=="root":
			var idx := scalar(a)
			if idx.is_empty() or idx[1]!=1:return {}
			index=int(idx[0]);radicand=scalar(normalize(args[1],depth+1))
		if radicand.is_empty() and index==2:return nested_square_root(a)
		return radical(radicand,index)
	if op in ["sin","cos","tan","sec","csc","cot"]:
		var pair := angle_pair(args[0])
		if pair.is_empty():return {}
		var s: Dictionary=pair.s;var c: Dictionary=pair.c;var one := rf(pconstant(q(1)))
		match op:
			"sin":return s
			"cos":return c
			"tan":return combine(s,c,"div")
			"cot":return combine(c,s,"div")
			"sec":return combine(one,c,"div")
			"csc":return combine(one,s,"div")
	if op=="abs":
		var v := scalar(a)
		if not v.is_empty():return rf(pconstant(q(absi(v[0]),v[1])))
	if op=="factorial":
		var v := scalar(a)
		if v.is_empty() or v[1]!=1 or v[0]<0 or v[0]>14:return {}
		var out := q(1)
		for k in range(2,int(v[0])+1):out=mul(out,q(k))
		return rf(pconstant(out))
	if op=="choose":
		var n := scalar(a);var r := scalar(normalize(args[1],depth+1))
		if n.is_empty() or r.is_empty() or n[1]!=1 or r[1]!=1 or n[0]>40 or n[0]<0 or r[0]<0 or r[0]>n[0]:return {}
		var out := q(1)
		for k in range(1,int(r[0])+1):out=divq(mul(out,q(int(n[0])-k+1)),q(k))
		return rf(pconstant(out))
	return {}

static func equivalent(a: Dictionary,b: Dictionary) -> bool:
	var left := normalize(a);var right := normalize(b)
	if left.is_empty() or right.is_empty():return false
	var delta := padd(pmul(left.n,right.d),pmul(right.n,left.d),true)
	return pzero(trig_reduce(delta))

static func parse_normal(source: String) -> Dictionary:
	var parsed := Parser.new().parse(source)
	return normalize(parsed.ast) if parsed.ok else {}

static func same(a: String,b: String) -> bool:
	var pa := Parser.new().parse(a);var pb := Parser.new().parse(b)
	return pa.ok and pb.ok and equivalent(pa.ast,pb.ast)

static func peval(p: Dictionary,variables: Dictionary) -> Array:
	var out := q(0)
	for key in p:
		var term: Array=p[key]
		for name in powers(key):
			if not variables.has(name):return []
			term=mul(term,power(variables[name],int(powers(key)[name])))
		out=add(out,term)
	return out

static func polynomial_text(coefficients: Array,variable: String="x") -> String:
	var terms: PackedStringArray=[]
	for i in range(coefficients.size()-1,-1,-1):
		var c: Array=coefficients[i] if coefficients[i] is Array else q(int(coefficients[i]))
		if c[0]==0:continue
		var term := "("+text(c)+")"
		if i>0:term+="*"+variable+("^"+str(i) if i>1 else "")
		terms.append(term)
	return "+".join(terms) if not terms.is_empty() else "0"

static func sparse_text(poly: Dictionary) -> String:
	var keys := poly.keys();keys.sort();var terms: PackedStringArray=[]
	for key in keys:
		if poly[key][0]==0:continue
		var term := "("+text(poly[key])+")"
		for name in powers(key):term+="*"+str(name)+( "^"+str(powers(key)[name]) if int(powers(key)[name])!=1 else "")
		terms.append(term)
	return "+".join(terms) if not terms.is_empty() else "0"

static func determinant(matrix: Array) -> Array:
	var n := matrix.size()
	if n<1 or n>3:return []
	for row in matrix:
		if not row is Array or row.size()!=n:return []
	if n==1:return matrix[0][0]
	var out := q(0)
	for col in range(n):
		var minor: Array=[]
		for i in range(1,n):
			var row: Array=[]
			for j in range(n):
				if j!=col:row.append(matrix[i][j])
			minor.append(row)
		var term := mul(matrix[0][col],determinant(minor))
		out=add(out,term if col%2==0 else neg(term))
	return out

static func solve(matrix: Array,rhs: Array) -> Dictionary:
	# Independent row reduction, not Cramer's rule used in teaching keys.
	var n := matrix.size()
	if n<2 or n>3 or rhs.size()!=n:return {}
	var rows: Array=[]
	for i in range(n):
		if matrix[i].size()!=n:return {}
		var row: Array=matrix[i].duplicate(true);row.append(rhs[i]);rows.append(row)
	var pivots: Array=[];var rank_value := 0
	for col in range(n):
		var pivot := -1
		for r in range(rank_value,n):
			if rows[r][col][0]!=0:pivot=r;break
		if pivot<0:continue
		var swap: Array=rows[rank_value];rows[rank_value]=rows[pivot];rows[pivot]=swap
		var divisor: Array=rows[rank_value][col]
		for j in range(col,n+1):rows[rank_value][j]=divq(rows[rank_value][j],divisor)
		for r in range(n):
			if r==rank_value:continue
			var factor: Array=rows[r][col]
			for j in range(col,n+1):rows[r][j]=add(rows[r][j],neg(mul(factor,rows[rank_value][j])))
		pivots.append(col);rank_value+=1
	for row in rows:
		var zero := true
		for j in range(n):
			if row[j].is_empty():return {}
			if row[j][0]!=0:zero=false
		if zero and row[n][0]!=0:return {"classification":"none","rank":rank_value}
	if rank_value<n:return {"classification":"infinite","rank":rank_value}
	var values: Array=[]
	for i in range(n):values.append(rows[i][n])
	return {"classification":"unique","values":values,"rank":rank_value}

static func divide_polynomial(dividend: Array,divisor: Array) -> Dictionary:
	var rem: Array=dividend.duplicate(true);var den: Array=divisor.duplicate(true)
	while rem.size()>1 and rem[-1][0]==0:rem.pop_back()
	while den.size()>1 and den[-1][0]==0:den.pop_back()
	if den.is_empty() or den[-1][0]==0 or rem.size()>13:return {}
	var quotient: Array=[]
	for _i in range(maxi(1,rem.size()-den.size()+1)):quotient.append(q(0))
	for _pass in range(14):
		if rem.size()<den.size() or (rem.size()==1 and rem[0][0]==0):break
		var shift := rem.size()-den.size();var factor := divq(rem[-1],den[-1]);quotient[shift]=factor
		for i in range(den.size()):rem[i+shift]=add(rem[i+shift],neg(mul(factor,den[i])))
		while rem.size()>1 and rem[-1][0]==0:rem.pop_back()
	return {"quotient":quotient,"remainder":rem}
