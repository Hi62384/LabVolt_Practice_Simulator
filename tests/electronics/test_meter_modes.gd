extends SceneTree
var failures:=0
func check(ok:bool,label:String):
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize():
	var station=load("res://scripts/dc_station.gd").new()
	station.wires=[["VΩ","Ca"],["COM","Cb"]];station.meter_mode="Capacitance"
	for value in [.000000001,.000001,.001]:
		station.capacitance=value;station.step();check(absf(float(station.meter)-value*1e6)<maxf(.0001,value*1e4),"capacitance by injected-current ramp "+str(value))
	station=load("res://scripts/dc_station.gd").new();station.master=true;station.channels[0].enabled=true;station.wires=[["CH1+","VΩ"],["CH1-","COM"]]
	station.meter_range=2;station.step();check(station.meter=="OL","voltage overload on 2 V range")
	station.meter_range=20;station.step();check(station.meter.begins_with("5.000"),"20 V range reads actual supply")
	station=load("res://scripts/dc_station.gd").new();station.generator.enabled=true;station.meter_mode="AC V";station.scope.running=false;station.wires=[["GEN","VΩ"],["REF","COM"]]
	for i in 512:station.step()
	check(station.samples.is_empty() and station.meter.contains("RMS") and float(station.meter)>1,"AC meter keeps measuring while scope is stopped")
	quit(failures)
