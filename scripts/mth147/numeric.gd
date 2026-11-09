extends RefCounted
const Parser = preload("res://scripts/mth147/parser.gd")
const Exact = preload("res://scripts/mth147/exact.gd")
const MAX_VALUE: float = 1e100
const MIN_NONZERO: float = 1e-100

static func evaluate(ast: Dictionary,variables: Dictionary={},depth: int=0,angle_unit: String="degrees") -> float:
	if depth>24 or ast.is_empty():return NAN
	var op := str(ast.get("op",""))
	if op=="num":
		var v := float(ast.get("value","nan"))
		var mantissa := str(ast.get("value","")).to_lower().split("e")[0]
		var nonzero := false
		for digit in mantissa:
			if digit in "123456789":nonzero=true
		return v if is_finite(v) and absf(v)<=MAX_VALUE and (v==0 and not nonzero or absf(v)>=MIN_NONZERO) else NAN
	if op=="symbol":
		var v := PI if ast.name=="pi" else float(variables.get(ast.name,NAN))
		return v if is_finite(v) and absf(v)<=MAX_VALUE and (v==0 or absf(v)>=MIN_NONZERO) else NAN
	var args: Array=ast.get("args",[])
	if args.is_empty():return NAN
	if angle_unit not in ["degrees","radians"]:return NAN
	var a := evaluate(args[0],variables,depth+1,angle_unit)
	if not is_finite(a):return NAN
	var b := evaluate(args[1],variables,depth+1,angle_unit) if args.size()>1 else 0.0
	if args.size()>1 and not is_finite(b):return NAN
	var result := NAN
	var angle := deg_to_rad(a) if angle_unit=="degrees" else a
	match op:
		"neg":result=-a
		"add":result=a+b
		"sub":result=a-b
		"mul":result=a*b
		"div":result=a/b if b!=0.0 else NAN
		"pow":
			if absf(b)>100 or (a==0 and b<=0):return NAN
			result=pow(a,b) if a>=0 or b==floor(b) else NAN
			if a<0 and b!=floor(b):
				var exponent := Exact.scalar(Exact.normalize(args[1]))
				if not exponent.is_empty() and int(exponent[1])%2==1:result=pow(absf(a),b)*(-1.0 if absi(int(exponent[0]))%2==1 else 1.0)
		"sqrt":result=sqrt(a) if a>=0 else NAN
		"cbrt":result=signf(a)*pow(absf(a),1.0/3.0)
		"root":
			if a!=floor(a) or a<2 or a>6 or (b<0 and int(a)%2==0):return NAN
			result=signf(b)*pow(absf(b),1.0/a)
		"sin":result=sin(angle)
		"cos":result=cos(angle)
		"tan":result=tan(angle) if absf(cos(angle))>1e-12 else NAN
		"sec":result=1.0/cos(angle) if absf(cos(angle))>1e-12 else NAN
		"csc":result=1.0/sin(angle) if absf(sin(angle))>1e-12 else NAN
		"cot":result=cos(angle)/sin(angle) if absf(sin(angle))>1e-12 else NAN
		"asin":result=asin(a) if absf(a)<=1 else NAN
		"acos":result=acos(a) if absf(a)<=1 else NAN
		"atan":result=atan(a)
		"atan2":result=atan2(a,b) if a!=0 or b!=0 else NAN
		"ln":result=log(a) if a>0 else NAN
		"log":result=log(a)/log(b) if a>0 and b>0 and b!=1 else NAN
		"exp":result=exp(a) if a<=log(MAX_VALUE) else NAN
		"abs":result=absf(a)
		"factorial":
			if a!=floor(a) or a<0 or a>40:return NAN
			result=1.0
			for k in range(2,int(a)+1):result*=k
		"choose":
			if a!=floor(a) or b!=floor(b) or a<0 or a>100 or b<0 or b>a:return NAN
			result=1.0
			for k in range(1,int(minf(b,a-b))+1):result*=float(a-k+1)/k
	if op in ["asin","acos","atan","atan2"] and angle_unit=="degrees":result=rad_to_deg(result)
	if result==0 and (op in ["mul","div","pow"] and a!=0 and (op!="mul" or b!=0) or op=="exp"):return NAN
	return result if is_finite(result) and absf(result)<=MAX_VALUE and (result==0 or absf(result)>=MIN_NONZERO) else NAN

static func from_text(text: String,variables: Dictionary={},angle_unit: String="degrees") -> float:
	var parsed := Parser.new().parse(text)
	return evaluate(parsed.ast,variables,0,angle_unit) if parsed.ok else NAN

static func literal(input: Variant) -> String:
	return String.num_scientific(input) if input is float else str(input)

static func from_value(input: Variant,variables: Dictionary={},angle_unit: String="degrees") -> float:
	return from_text(literal(input),variables,angle_unit)

static func waves_equal(left: Dictionary,right: Dictionary,xtol: float=1e-8,ytol: float=1e-8) -> bool:
	var a := canonical_wave(left);var b := canonical_wave(right)
	if a.is_empty() or b.is_empty():return false
	if not close(a.period,b.period,xtol,1e-8) or not close(a.amplitude,b.amplitude,ytol,1e-8) or not close(a.offset,b.offset,ytol,1e-8):return false
	var difference := fposmod(float(a.phase)-float(b.phase),float(a.period))
	return minf(difference,float(a.period)-difference)<=xtol

static func canonical_wave(input: Dictionary) -> Dictionary:
	if input.get("kind","") not in ["sin","cos"]:return {}
	var out := {"kind":"sin"}
	for field in ["amplitude","period","phase","offset"]:
		var value := from_value(input.get(field,NAN))
		if not is_finite(value):return {}
		out[field]=value
	if float(out.period)<=0 or float(out.amplitude)==0:return {}
	if input.kind=="cos":out.phase=float(out.phase)-float(out.period)/4.0
	if float(out.amplitude)<0:out.amplitude=-float(out.amplitude);out.phase=float(out.phase)-float(out.period)/2.0
	out.phase=fposmod(float(out.phase),float(out.period));return out

static func close(a: float,b: float,absolute: float=1e-8,relative: float=1e-7) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b)<=maxf(absolute,relative*maxf(absf(a),absf(b)))

static func wave(function: Dictionary,x: float) -> float:
	var period := float(function.get("period",0))
	if period<=0 or not is_finite(x):return NAN
	var angle := TAU*(x-float(function.get("phase",0)))/period
	return float(function.get("offset",0))+float(function.get("amplitude",1))*(cos(angle) if function.get("kind","sin")=="cos" else sin(angle))

static func wave_points(function: Dictionary,start: float,end: float,count: int=129) -> Array:
	var points: Array=[]
	for i in range(clampi(count,2,256)):
		var x := lerpf(start,end,float(i)/float(clampi(count,2,256)-1))
		points.append({"x":x,"y":wave(function,x)})
	return points

static func triangle(a: float,b: float,c: float) -> Dictionary:
	if minf(a,minf(b,c))<=0 or a+b<=c or b+c<=a or a+c<=b:return {}
	var A := rad_to_deg(acos(clampf((b*b+c*c-a*a)/(2*b*c),-1,1)))
	var B := rad_to_deg(acos(clampf((a*a+c*c-b*b)/(2*a*c),-1,1)))
	var C := 180.0-A-B
	# A=(0,0), B=(c,0), C projected using the law of cosines.
	var x := (b*b+c*c-a*a)/(2*c);var y := sqrt(maxf(0,b*b-x*x))
	return {"kind":"triangle","sides":{"a":a,"b":b,"c":c},"angles":{"A":A,"B":B,"C":C},"vertices":[{"x":0.0,"y":0.0,"label":"A"},{"x":c,"y":0.0,"label":"B"},{"x":x,"y":y,"label":"C"}],"given":[],"unknown":[]}

static func ssa(A: float,a: float,b: float) -> Array:
	var out: Array=[]
	if A<=0 or A>=180 or a<=0 or b<=0:return out
	var sine := b*sin(deg_to_rad(A))/a
	if sine>1.0+1e-12 or sine<=0:return out
	var B := rad_to_deg(asin(clampf(sine,-1,1)))
	for candidate in [B,180.0-B]:
		var C := 180.0-A-float(candidate)
		if C<=1e-9:continue
		if out.size()>0 and close(candidate,float(out[0].B)):continue
		var c := a*sin(deg_to_rad(C))/sin(deg_to_rad(A))
		out.append({"A":A,"B":candidate,"C":C,"a":a,"b":b,"c":c})
	return out

static func trig_solutions(kind: String,target: float,lo: float,hi: float,scale: float=1.0,shift: float=0.0) -> Array:
	var result: Array=[]
	if lo>hi or absf(lo)>10000 or absf(hi)>10000 or scale==0 or absf(scale)>12:return result
	var bases: Array=[];var period := 360.0
	match kind:
		"sin":
			if absf(target)>1:return []
			var alpha := rad_to_deg(asin(target));bases=[alpha,180.0-alpha]
		"cos":
			if absf(target)>1:return []
			var alpha := rad_to_deg(acos(target));bases=[alpha,-alpha]
		"tan":bases=[rad_to_deg(atan(target))];period=180.0
		_:return []
	var ylo := minf(scale*lo+shift,scale*hi+shift);var yhi := maxf(scale*lo+shift,scale*hi+shift)
	for base in bases:
		var kmin := int(ceil((ylo-float(base))/period-1e-10));var kmax := int(floor((yhi-float(base))/period+1e-10))
		if kmax-kmin>256:return []
		for k in range(kmin,kmax+1):
			var x := (float(base)+period*k-shift)/scale;var duplicate := false
			for existing in result:
				if close(x,existing):duplicate=true
			if not duplicate:result.append(x)
	result.sort();return result
