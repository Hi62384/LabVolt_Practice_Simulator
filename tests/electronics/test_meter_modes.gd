extends SceneTree
var failures:=0
func check(ok:bool,label:String):
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize():
	var station=load("res://scripts/dc_station.gd").new()
	check(station.apply({"op":"wire","a":"VΩ","b":"Ca"})=="", "capacitance voltage lead")
	check(station.apply({"op":"wire","a":"COM","b":"Cb"})=="", "capacitance return lead")
	check(station.apply({"op":"meter","mode":"Capacitance"})=="", "select capacitance")
	for value in [.000000001,.000001,.001]:
		check(station.apply({"op":"capacitor","value":value})=="", "set capacitance "+str(value))
		station.step()
		check(absf(float(station.meter)-value*1e6)<maxf(.0001,value*1e4),"capacitance by injected-current ramp "+str(value))
	station=load("res://scripts/dc_station.gd").new();station.master=true;station.channels[0].enabled=true;station.wires=[["CH1+","VΩ"],["CH1-","COM"]]
	station.meter_range=2;station.step();check(station.meter=="OL","voltage overload on 2 V range")
	station.meter_range=20;station.step();check(station.meter.begins_with("5.000"),"20 V range reads actual supply")
	station=load("res://scripts/dc_station.gd").new()
	check(station.apply({"op":"generator","key":"enabled","value":true})=="", "enable generator")
	check(station.apply({"op":"meter","mode":"AC V"})=="", "select AC voltage")
	check(station.apply({"op":"scope","key":"running","value":false})=="", "stop scope acquisition")
	check(station.apply({"op":"wire","a":"GEN","b":"VΩ"})=="", "AC voltage lead")
	check(station.apply({"op":"wire","a":"REF","b":"COM"})=="", "AC return lead")
	for i in 512:station.step()
	check(station.samples.is_empty() and station.meter.contains("RMS") and float(station.meter)>1,"AC meter keeps measuring while scope is stopped")
	station=load("res://scripts/dc_station.gd").new()
	station.wires=[["GEN","VΩ"],["REF","COM"]]
	check(station.apply({"op":"wire","a":"CH1+","b":"S1","lead_color":2})=="", "add colored lead to legacy wiring")
	check(station.lead_colors==[-1,-1,2], "new jacket color remains on its own wire")
	check(station.apply({"op":"unwire","index":0})=="" and station.lead_colors==[-1,2], "removal preserves jacket alignment")
	station.lead_colors.clear()
	check(station.apply({"op":"unwire","index":1})=="" and station.wires.size()==1, "legacy lead can be removed without a color")
	quit(failures)
