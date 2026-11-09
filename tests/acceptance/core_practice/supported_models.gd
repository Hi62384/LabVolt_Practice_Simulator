extends RefCounted
## Bounded existing-model checks; these do not claim manual IC mouse coverage.
static func run(check: Callable) -> void:
	var models=load("res://scripts/device_models.gd");var catalog=load("res://scripts/electronics_catalog.gd").all()
	var n: Array=[]
	for i in 14:n.append(str(i))
	for input in [0.,5.]:
		var v:={"6":0.,"13":5.,"0":input}
		var out: Array=models.expand(catalog.hc04,"not",n,{},v)
		var driver: Dictionary=out.filter(func(p):return p.id=="not/out0")[0]
		check.call(driver.b==("13" if input==0. else "6") and float(driver.value)==40.,"Existing behavioral NOT gate low/high response")
	var stateful=load("res://scripts/stateful_devices.gd")
	var v:={"13":5.,"6":0.,"0":5.,"3":5.,"12":5.,"9":5.,"1":5.,"2":0.}
	var flip: Dictionary=stateful.tick("flip74",n,v,{},.0005)
	v["2"]=5.;flip=stateful.tick("flip74",n,v,flip,.0005);check.call(flip.a,"Existing74HC74 captures rising-edge data")
	v["1"]=0.;flip=stateful.tick("flip74",n,v,flip,.0005);check.call(flip.a,"Existing74HC74 holds between clock edges")
	v["0"]=0.;flip=stateful.tick("flip74",n,v,flip,.0005);check.call(not flip.a,"Existing74HC74 asynchronous clear")
	var pins: Array=["g","trig","out","v","ctrl","thresh","dis","v"]
	var timer: Dictionary=stateful.tick("timer555",pins,{"g":0.,"v":5.,"ctrl":3.333333,"trig":0.,"thresh":0.}, {},.0005)
	check.call(timer.get("q",false),"Existing555 trigger latch sets")
	timer=stateful.tick("timer555",pins,{"g":0.,"v":5.,"ctrl":3.333333,"trig":5.,"thresh":4.},timer,.0005)
	check.call(not timer.get("q",true),"Existing555 threshold resets latch")
	# Existing LVScript only; no platform/assembler/native helper or compiler.
	var firmware=load("res://scripts/firmware_runtime.gd").new()
	var script:="mode D0 out\nwrite D0 1\nhalt"
	var live: Dictionary=firmware.tick(script,["v","g","o","p","a","w"],{"v":5.,"g":0.},.0005,true)
	check.call(live.get("outputs",{}).get("D0",0)==1,"Existing LVScript drives output; no native/C++ path")
