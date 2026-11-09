extends RefCounted
## A bounded Pratt parser. No Expression/eval/OS/process calls are used.
const FUNCTIONS = {"sqrt":1,"cbrt":1,"root":2,"sin":1,"cos":1,"tan":1,"asin":1,"acos":1,"atan":1,"atan2":2,"sec":1,"csc":1,"cot":1,"abs":1,"factorial":1,"choose":2,"ln":1,"log":2,"exp":1}
const SYMBOLS = "abcdefghijklmnopqrstuvwxyz"
const NAMED_SYMBOLS = ["pi","alpha","beta","gamma","delta","epsilon","theta","lambda","mu","rho","sigma","phi","omega"]
var tokens: Array = []
var pos: int = 0
var error: String = ""
var nodes: int = 0

func parse(source: String) -> Dictionary:
	tokens=[];pos=0;error="";nodes=0
	if source.length()>512:return {"ok":false,"error":"Input exceeds 512 characters."}
	var s := source.replace("−","-").replace("×","*").replace("÷","/").replace("π","pi").replace("θ","theta").replace("φ","phi").replace("ω","omega")
	for pair in [["α","alpha"],["β","beta"],["γ","gamma"],["δ","delta"],["ε","epsilon"],["λ","lambda"],["μ","mu"],["ρ","rho"],["σ","sigma"]]:s=s.replace(pair[0],pair[1])
	var i := 0
	while i<s.length():
		var c := s[i]
		if c in " \t\r\n":i+=1;continue
		if c in "0123456789.":
			var start := i;var dots := 0
			while i<s.length() and s[i] in "0123456789.":
				if s[i]==".":dots+=1
				i+=1
			var number := s.substr(start,i-start)
			if dots>1 or number=="." or number.length()>32:return {"ok":false,"error":"Invalid or excessive numeric literal."}
			# Scientific e notation requires an explicit signed/integer exponent.
			if i<s.length() and s[i] in "eE":
				var j := i+1
				if j<s.length() and s[j] in "+-":j+=1
				var digit_start := j
				while j<s.length() and s[j] in "0123456789":j+=1
				if j>digit_start:
					number+=s.substr(i,j-i);i=j
			tokens.append({"type":"num","value":number})
		elif c.to_lower() in SYMBOLS:
			var start := i
			while i<s.length() and s[i].to_lower() in SYMBOLS:i+=1
			if s.substr(start,i-start)=="atan" and i<s.length() and s[i]=="2":i+=1
			var name := s.substr(start,i-start)
			if name.length()!=1 and name not in FUNCTIONS and name not in NAMED_SYMBOLS:return {"ok":false,"error":"Unknown symbol or function: "+name}
			tokens.append({"type":"name","value":name})
		elif c in "+-*/^(),!":tokens.append({"type":c,"value":c});i+=1
		else:return {"ok":false,"error":"Unsupported character."}
		if tokens.size()>256:return {"ok":false,"error":"Too many tokens."}
	if tokens.is_empty():return {"ok":false,"error":"Enter an answer."}
	tokens.append({"type":"end","value":""})
	var ast := expression(0,0)
	if error.is_empty() and peek()!="end":error="Unexpected token. Use parentheses and explicit operators."
	return {"ok":error.is_empty(),"ast":ast,"error":error}

func peek() -> String:
	return str(tokens[pos].type) if pos<tokens.size() else "end"

func node(op: String,args: Array=[],value: String="") -> Dictionary:
	nodes+=1
	if nodes>192:error="Expression exceeds 192 nodes."
	if op=="num":return {"op":op,"value":value}
	if op=="symbol":return {"op":op,"name":value}
	return {"op":op,"args":args}

func expression(minimum: int,depth: int) -> Dictionary:
	if depth>24:error="Expression nesting exceeds 24.";return {}
	if not error.is_empty():return {}
	var left: Dictionary={}
	var kind := peek()
	if kind in ["+","-"]:
		pos+=1;left=expression(25,depth+1)
		if kind=="-":left=node("neg",[left])
	elif kind=="num":left=node("num",[],str(tokens[pos].value));pos+=1
	elif kind=="name":
		var name := str(tokens[pos].value);pos+=1
		if name in FUNCTIONS:
			if peek()!="(":error="Function needs parentheses.";return {}
			pos+=1;var args: Array=[expression(0,depth+1)]
			while peek()=="," and error.is_empty():pos+=1;args.append(expression(0,depth+1))
			if peek()!=")" or args.size()!=int(FUNCTIONS[name]):error="Incorrect function arguments.";return {}
			pos+=1;left=node(name,args)
		else:left=node("symbol",[],name)
	elif kind=="(":
		pos+=1;left=expression(0,depth+1)
		if peek()!=")":error="Missing closing parenthesis.";return {}
		pos+=1
	else:error="Expected a number, symbol or parenthesis.";return {}
	while error.is_empty():
		kind=peek()
		if kind=="!":
			if 40<minimum:break
			pos+=1;left=node("factorial",[left]);continue
		var implicit := kind in ["num","name","("]
		var binding := 20 if implicit or kind in ["*","/"] else (10 if kind in ["+","-"] else (30 if kind=="^" else -1))
		if binding<minimum:break
		var op: String = "mul" if implicit else str({"+":"add","-":"sub","*":"mul","/":"div","^":"pow"}.get(kind,""))
		if not implicit:pos+=1
		var right := expression(binding if kind=="^" else binding+1,depth+1)
		left=node(op,[left,right])
	return left

static func valid_ast(ast: Variant,depth: int=0,budget: Array=[0]) -> bool:
	# Public ASTs are reserialized through this validator; no hidden executable objects.
	if depth==0:budget=[0]
	budget[0]+=1
	if depth>24 or budget[0]>192 or not ast is Dictionary:return false
	if ast.size()>3 or not (ast.get("op",null) is String or ast.get("op",null) is StringName):return false
	if str(ast.op).length()>16:return false
	var op := str(ast.get("op",""))
	var allowed := ["op","value"] if op=="num" else (["op","name"] if op=="symbol" else ["op","args"])
	for key in ast:
		if key not in allowed:return false
	if op=="num":
		if not ast.get("value",null) is String or str(ast.value).length()>40:return false
		var p := new().parse(str(ast.get("value","")))
		return p.ok and (p.ast.op=="num" or (p.ast.op=="neg" and p.ast.args[0].op=="num"))
	if op=="symbol":return ast.get("name",null) is String and (str(ast.get("name","")) in NAMED_SYMBOLS or (str(ast.get("name","")).length()==1 and str(ast.name).to_lower() in SYMBOLS))
	var arity := 2 if op in ["add","sub","mul","div","pow"] else (1 if op=="neg" else int(FUNCTIONS.get(op,-1)))
	if arity<0 or not ast.get("args",[]) is Array or ast.get("args",[]).size()!=arity:return false
	for child in ast.args:
		if not valid_ast(child,depth+1,budget):return false
	return true
