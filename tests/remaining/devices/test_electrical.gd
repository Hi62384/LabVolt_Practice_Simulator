extends SceneTree
const P=preload("res://scripts/commercial_devices/peripherals.gd")
const C=preload("res://scripts/commercial_devices/catalog.gd")
const R=preload("res://scripts/commercial_devices/registers.gd")
const Events=preload("res://scripts/commercial_devices/event_adapter.gd")
const Solver=preload("res://scripts/electronics_solver.gd")
var checks:=0
var failed:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL "+label)
func source(id: String,a: String,b: String,value: float) -> Dictionary:return {"id":id,"kind":"V","a":a,"b":b,"value":value,"resistance":.00001}
func resistor(id: String,a: String,b: String,value: float) -> Dictionary:return {"id":id,"kind":"R","a":a,"b":b,"value":value}
func _initialize() -> void:
	for kind in ["lm358","lm324"]:
		var n: Array=[]
		for i in C.pins(kind).size():n.append(str(i))
		var ground: String=n[3] if kind=="lm358" else n[10];var power: String=n[7] if kind=="lm358" else n[3]
		var volts:={}
		for node in n:volts[node]=0.0
		volts[power]=5.0;volts[n[2]]=1.0;volts[n[1]]=1.0
		var parts:=P.expand(C.all()[kind],"amp",n,{},volts,{})
		parts.append_array([source("power",power,ground,5.0),source("signal",n[2],ground,1.0),resistor("load",n[0],ground,10000.)])
		var wires: Array=[[n[1],n[0]],[n[4],ground],[n[5],n[6]]]
		if kind=="lm324":wires.append_array([[n[9],ground],[n[8],n[7]],[n[11],ground],[n[12],n[13]]])
		var solved:=Solver.new().solve(parts,wires,0.)
		check(solved.ok,"actual MNA "+kind+" "+str(solved.get("error","")))
		if solved.ok:check(absf(float(solved.drop.load)-1.0)<.001,"independent unity feedback voltage "+kind)
		# Saturation: identical supply/load, open loop positive input1V / in-minus0V.
		volts[n[1]]=0.0
		parts=P.expand(C.all()[kind],"amp",n,{},volts,{})
		parts.append_array([source("power",power,ground,5.),source("signal",n[2],ground,1.),source("minus",n[1],ground,0.),resistor("load",n[0],ground,10000.)])
		solved=Solver.new().solve(parts,[],0.)
		check(solved.ok and absf(float(solved.drop.load)-3.5*10000./10050.)<.001,"loaded positive swing headroom "+kind)
		volts[n[2]]=4.0
		parts=P.expand(C.all()[kind],"amp",n,{},volts,{})
		check(not parts.any(func(part):return str(part.id)=="amp/amp0"),"common-mode outofrange highimpedance "+kind)
	var n: Array=C.pins("ssd1306")
	var s:=R.initial("ssd1306");s.powered=true;s.bus={"low":true}
	var parts:=P.expand(C.all().ssd1306,"oled",n,{}, {},{"oled":s}).filter(func(part):return part.kind!="io_device")
	parts.append_array([source("vcc",n[0],n[1],3.3),resistor("pullup",n[0],n[3],4700.)])
	var solved:=Solver.new().solve(parts,[],0.)
	check(solved.ok and float(solved.drop.pullup)>3.2,"actual MNA open-drain ACK sinks externalpullup")
	check(not parts.any(func(part):return part.get("a","")==n[3] and part.get("b","")==n[0]),"SDA never pushpull high")
	var pwm_state:=R.initial("pca9685");pwm_state.powered=true;pwm_state.registers[7]=16
	pwm_state.output_registers=pwm_state.registers.duplicate()
	var pwm_nodes: Array=C.pins("pca9685")
	parts=P.expand(C.all().pca9685,"pwm",pwm_nodes,{}, {"VDD":3.3,"VSS":0.0,"OE":0.0},{"pwm":pwm_state}).filter(func(part):return part.kind!="io_device")
	parts.append_array([source("vcc","VDD","VSS",3.3),resistor("load","LED0","VSS",1000.)])
	solved=Solver.new().solve(parts,[],0.)
	check(solved.ok and absf(float(solved.drop.load)-3.3*1000./1050.)<.001,"PCA actualphysicalpin finite PWM driver under load")
	var crystal:=P.expand(C.all().quartz,"xtal",["a","b"],{}, {},{})
	var inductance: float=crystal[1].value;var capacitance: float=crystal[2].value
	check(absf(1./(TAU*sqrt(inductance*capacitance))-32768.)<.00001,"independent BVD resonance32.768kHz")
	check(crystal.all(func(part):return part.kind in ["R","L","C"]),"crystal passive no fakeclock")
	var osc:=P.tick({"model":"oscillator","nodes":["v","g","o","e"]},{"ok":true,"v":{"v":3.3,"g":0.,"e":3.3}}, {},.0000001)
	check(osc.powered and not osc.undersampled,"oscillator powered finelysampled")
	check(absf(Events.max_step({"model":"oscillator"},osc)-.0000004)<1e-12,"oscillator exact next halfcycle deadline")
	var oscillator_nodes: Array=["v","g","o","e"]
	parts=P.expand(C.all().oscillator,"clock",oscillator_nodes,{}, {"v":3.3,"g":0.,"e":3.3},{"clock":osc}).filter(func(part):return part.kind!="io_device")
	parts.append_array([source("power","v","g",3.3),resistor("load","o","g",1000.)])
	solved=Solver.new().solve(parts,[["e","v"]],0.)
	check(solved.ok and absf(float(solved.drop.load)-3.3*1000./1040.)<.001,"oscillator high finite electrical driver")
	osc=P.tick({"model":"oscillator","nodes":oscillator_nodes},{"ok":true,"v":{"v":3.3,"g":0.,"e":3.3}},osc,.0000005)
	parts=P.expand(C.all().oscillator,"clock",oscillator_nodes,{}, {"v":3.3,"g":0.,"e":3.3},{"clock":osc}).filter(func(part):return part.kind!="io_device")
	parts.append_array([source("power","v","g",3.3),resistor("load","o","g",1000.)])
	solved=Solver.new().solve(parts,[["e","v"]],0.)
	check(solved.ok and absf(float(solved.drop.load))<.001,"oscillator actual next halfcycle switcheslow")
	var pwm:=R.initial("pca9685");pwm.powered=true;pwm.registers[8]=0;pwm.registers[9]=8;pwm.phase_time=0.0
	pwm.output_registers=pwm.registers.duplicate()
	check(absf(Events.max_step({"model":"pca9685"},pwm)-2048.*31./25000000.)<1e-12,"PCA nextedge independentlycomputed")
	var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(pwm))
	check(int(roundtrip.registers[9])==int(pwm.registers[9]) and float(roundtrip.phase_time)==float(pwm.phase_time) and R.pwm(roundtrip,0)==R.pwm(pwm,0),"PWM JSON-safe deterministic state")
	print("ELECTRICAL checks=",checks," failures=",failed)
	quit(1 if failed else 0)
