extends SceneTree
var failures := 0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:
	var solver=load("res://scripts/electronics_solver.gd").new()
	var parts: Array=[{"id":"v","kind":"supply","a":"p","b":"n","value":10.0,"limit":.1,"resistance":.01},{"id":"r","kind":"R","a":"p","b":"n","value":1000.0}]
	var result: Dictionary=solver.solve(parts)
	check(result.ok,"DC solves")
	if result.ok:
		check(absf(result.i.r-.01)<.000001,"Ohm law 10 V / 1k")
		check(result.mode.v=="CV","supply CV below current limit")
	parts[1].value=10.0;result=solver.solve(parts)
	check(result.ok and absf(result.i.r-.1)<.000001 and absf(result.drop.r-1)<.0001,"CC reduces voltage at .1 A")
	parts[1].value=1000.0;parts.append({"id":"v2","kind":"supply","a":"q","b":"p","value":5.0,"limit":.1,"resistance":.01});parts[1].a="q"
	result=solver.solve(parts);check(result.ok and absf(result.i.r-.015)<.00001,"isolated channels in series")
	parts=[{"id":"v","kind":"V","a":"p","b":"n","value":5.0},{"id":"r","kind":"R","a":"p","b":"x","value":1000.0},{"id":"c","kind":"C","a":"x","b":"n","value":.000001}]
	solver.reset()
	for i in range(100):result=solver.solve(parts,[],.00001)
	check(result.ok and absf(result.drop.c-5*(1-exp(-1)))<.02,"RC step one time constant")
	parts[2]={"id":"d","kind":"D","a":"x","b":"n","vf":.65,"ron":2.0}
	result=solver.solve(parts);check(result.ok and absf(result.i.d-(5-.65)/1002)<.000001,"diode actual forward current")
	parts[2].a="n";parts[2].b="x";result=solver.solve(parts)
	check(result.ok and absf(result.i.d)<1e-7,"reverse diode blocks")
	var station=load("res://scripts/dc_station.gd").new()
	station.master=true;station.channels[0].enabled=true
	station.wires=[["CH1+","R1a"],["CH1-","R1b"],["VΩ","R1a"],["COM","R1b"]]
	station.step();check(station.result.ok and absf(station.difference("VΩ","COM")-5)<.001,"wired supply and meter")
	station.meter_mode="Resistance";station.step();check(station.meter.begins_with("LIVE"),"ohmmeter rejects energized circuit")
	station.master=false;station.step();check(station.meter.begins_with("1000"),"ohmmeter injects test current")
	station=load("res://scripts/dc_station.gd").new();station.generator.enabled=true
	# Keep several real 10 Hz periods in the shared acquisition window.
	check(station.apply({"op":"scope","key":"timebase","value":.05})=="","scope timebase includes enough periods for frequency measurement")
	station.wires=[["GEN","R1a"],["REF","R1b"],["S1","R1a"],["GND","R1b"]]
	# Complete the 0.5 s triggered record, including its post-trigger portion.
	for i in range(1400):station.step()
	var stats: Dictionary=load("res://scripts/dc_station.gd").statistics(station.samples,1)
	check(absf(stats.frequency-10)<.1,"scope frequency comes from solved signal")
	print(stats);check(absf(stats.vpp-4.0*1000/1050)<.01,"generator 50 ohm loading changes waveform")
	var other=load("res://scripts/dc_station.gd").new();other.step();check(not other.master and other.wires.is_empty(),"independent stations")
	print("DC FAILURES: ",failures);quit(failures)


