extends RefCounted
# LabVolt Script 1: bounded instruction interpreter. No Expression/eval, files or network.
const PINS={"D0":2,"D1":3,"A0":4,"PWM":5}
const TEMPLATE="mode D0 out\nwrite D0 1\nwait 500\nwrite D0 0\nwait 500\ngoto 2"
const APIS=["mode","write","read","analog","pwm","wait","set","add","if","goto","serial","halt"]
var instructions: Array=[]
var pc := 0
var wait_left := 0.0
var variables := {}
var outputs := {}
var modes := {}
var serial: Array=[]
var powered := false
var stopped := false
var status := "No power"
var code_hash := ""
var elapsed := 0.0
var compile_error := ""
var debug_paused := false
var debug_single_step := false
var breakpoints: Array=[]
var skip_breakpoint := -1
static func identifier(value: String) -> bool:
	if value.is_empty() or value.length()>20:return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789":return false
	return not value.left(1).is_valid_int()
static func operand(value: String) -> bool:return (value.is_valid_float() and is_finite(float(value))) or identifier(value)
static func compile(source: String) -> Dictionary:
	if source.length()>8192:return {"ok":false,"line":1,"error":"Program exceeds 8192 characters"}
	var lines := source.split("\n");var program: Array=[]
	if lines.size()>256:return {"ok":false,"line":1,"error":"Program exceeds 256 lines"}
	for i in lines.size():
		var clean := lines[i].split("#")[0].strip_edges().replace("\t"," ")
		var t := clean.split(" ",false);var error := ""
		if t.is_empty():program.append({"op":"nop","args":[],"line":i+1});continue
		match t[0]:
			"mode":
				if t.size()!=3 or t[1] not in ["D0","D1","PWM"] or t[2] not in ["in","out"]:error="mode D0|D1|PWM in|out"
			"write","pwm":
				if t.size()!=3 or t[1] not in ["D0","D1","PWM"] or not operand(t[2]):error="write/pwm pin value"
			"read","analog":
				if t.size()!=3 or not identifier(t[1]) or not PINS.has(t[2]):error="read/analog variable D0|D1|A0|PWM"
			"set","add":
				if t.size()!=3 or not identifier(t[1]) or not operand(t[2]):error="set/add variable number-or-variable"
			"wait","serial":
				if t.size()!=2 or not operand(t[1]):error="wait milliseconds / serial number-or-variable"
			"goto":
				if t.size()!=2 or not t[1].is_valid_int() or int(t[1])<1 or int(t[1])>lines.size():error="goto requires an existing line number"
			"if":
				if t.size()!=6 or not operand(t[1]) or t[2] not in ["==","!=","<",">","<=",">="] or not operand(t[3]) or t[4]!="goto" or not t[5].is_valid_int() or int(t[5])<1 or int(t[5])>lines.size():error="if value comparison value goto line"
			"halt":
				if t.size()!=1:error="halt takes no arguments"
			_:error="Unknown instruction: "+str(t[0])
		if error!="":return {"ok":false,"line":i+1,"error":error}
		program.append({"op":t[0],"args":Array(t.slice(1)),"line":i+1})
	return {"ok":true,"program":program}
func reset() -> void:
	pc=0;wait_left=0;variables.clear();outputs.clear();modes.clear();elapsed=0;stopped=not compile_error.is_empty();debug_paused=false;debug_single_step=false;skip_breakpoint=-1
func debug_pause() -> void:debug_paused=true
func debug_resume() -> void:
	debug_paused=false;skip_breakpoint=pc+1
func debug_step() -> void:
	debug_single_step=true;debug_resume()
func debug_breakpoints(lines: Array) -> void:
	breakpoints=lines.filter(func(line):return (line is int or line is float) and int(line)>=1 and int(line)<=256).slice(0,32)
func value(token: String) -> float:return float(token) if token.is_valid_float() else float(variables.get(token,0))
func tick(source: String,nodes: Array,volts: Dictionary,dt: float,run := true) -> Dictionary:
	if nodes.size()<6 or not is_finite(dt) or dt<0 or dt>1:
		outputs.clear();status="Invalid firmware tick inputs";return snapshot()
	if source.sha256_text()!=code_hash:
		code_hash=source.sha256_text();var compiled := compile(source);compile_error="" if compiled.ok else "Line %d: %s"%[compiled.line,compiled.error];reset();serial.clear()
		instructions=compiled.get("program",[])
		if not compiled.ok:status="Line %d: %s"%[compiled.line,compiled.error];stopped=true
	var vcc := float(volts.get(nodes[0],0))-float(volts.get(nodes[1],0))
	if not is_finite(vcc) or vcc<2.7 or vcc>5.5:
		if powered:reset()
		powered=false;outputs.clear();status="No power" if vcc<2.7 else "Supply outside 2.7–5.5 V";return snapshot()
	powered=true
	if not run:outputs.clear();status="Stopped";return snapshot()
	if not compile_error.is_empty():status=compile_error;stopped=true;return snapshot()
	if stopped:return snapshot()
	if debug_paused:status="Paused";return snapshot()
	elapsed+=dt;wait_left=maxf(0,wait_left-dt)
	if wait_left>0:status="Waiting";return snapshot()
	status="Running"
	for cycle in 64:
		if pc>=instructions.size():status="Finished";stopped=true;break
		if pc+1 in breakpoints and pc+1!=skip_breakpoint and not debug_single_step:debug_paused=true;status="Breakpoint";break
		skip_breakpoint=-1
		var command: Dictionary=instructions[pc];pc+=1;var a: Array=command.args
		match command.op:
			"mode":modes[a[0]]=a[1];outputs.erase(a[0])
			"write","pwm":
				if modes.get(a[0],"in")!="out":status="Line %d: set output mode first"%command.line;stopped=true;break
				outputs[a[0]]=clampf(value(a[1]),0,1) if command.op=="pwm" else (1.0 if value(a[1])!=0 else 0.0)
			"read","analog":
				var voltage := float(volts.get(nodes[PINS[a[1]]],0))-float(volts.get(nodes[1],0))
				variables[a[0]]=clampf(voltage/vcc,0,1)*1023 if command.op=="analog" else (1.0 if voltage>=.6*vcc else 0.0)
			"set":variables[a[0]]=value(a[1])
			"add":variables[a[0]]=clampf(float(variables.get(a[0],0))+value(a[1]),-1e12,1e12)
			"wait":wait_left=clampf(value(a[0]),0,3600000)/1000.0;break
			"goto":pc=int(a[0])-1
			"if":
				var left := value(a[0]);var right := value(a[2]);var yes := false
				match a[1]:
					"==":yes=left==right
					"!=":yes=left!=right
					"<":yes=left<right
					">":yes=left>right
					"<=":yes=left<=right
					">=":yes=left>=right
				if yes:pc=int(a[4])-1
			"serial":
				serial.append("%.3f s: %s"%[elapsed,str(value(a[0]))])
				if serial.size()>64:serial.pop_front()
			"halt":status="Halted";stopped=true;break
		if variables.size()>32:status="Variable limit (32) exceeded";stopped=true;outputs.clear();break
		if debug_single_step:break
	if debug_single_step:debug_single_step=false;debug_paused=true;status="Paused"
	return snapshot()
func snapshot() -> Dictionary:return {"outputs":outputs.duplicate(),"modes":modes.duplicate(),"status":status,"line":pc+1,"serial":serial.duplicate(),"powered":powered,"time":elapsed,"variables":variables.duplicate(),"paused":debug_paused,"backend":"labvoltscript-1"}
