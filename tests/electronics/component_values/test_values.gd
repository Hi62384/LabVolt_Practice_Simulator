extends SceneTree
## Deferred engine fixtures: DO NOT RUN while the user is actively playtesting.
const Values=preload("res://scripts/electronics/component_values/values.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
var checks := 0

func check(value: bool, message: String) -> void:
	checks+=1
	assert(value,message)

func _init() -> void:
	var catalog := Catalog.all()
	for pair in [["4.7 kΩ","4700 ohms"],["1 MΩ","1e6 Ω"],["1 mF","1000 uF"],["100 nF","0.1 µF"],["1 μF","1000000 pF"],[".123456789012345 V","123456789012345e-15 V"]]:
		var unit := "Ω" if pair[0].ends_with("Ω") else ("F" if pair[0].ends_with("F") else "V")
		var first := Values.parse(pair[0],unit);var second := Values.parse(pair[1],unit)
		check(first.ok and second.ok and first.canonical==second.canonical,"SI canonical equality: "+pair[0])
		check(Values.parse(Values.format_value(first.value,unit),unit).canonical==first.canonical,"Lossless format roundtrip")
	check(Values.parse("1 MΩ","Ω").value!=Values.parse("1 mΩ","Ω").value,"SI case is significant")
	for bad in [true,null,[],{},"","NaN","inf","-inf","1e999","1e-999","1e1000","1e-13","1e13","1 kkΩ","1 volts","1 F junk","1_000","0x10","1,000","--1"]:
		check(not Values.parse(bad,"Ω").ok,"Hostile value rejected: "+str(bad))
	for amount in [1,1.0,"1","001",100000,"100000"]:check(Values.quantity(amount).ok,"Whole quantity accepted")
	for amount in [0,-1,1.5,"1.0","1e2"," 1","1 ","+1","-1",true,null,[],{},100001,"999999999999999999999999"]:check(not Values.quantity(amount).ok,"Hostile quantity rejected")
	check(not Values.quantity(INF).ok and not Values.quantity(NAN).ok,"Nonfinite quantity rejected")
	var arbitrary := Values.configure("r100",{"value":"333.125 Ω"},catalog)
	check(arbitrary.ok and arbitrary.id.begins_with("cv1:"),"Arbitrary resistance supported")
	check(arbitrary.id==Values.configure("r220",{"value":"333125 mΩ"},catalog).id,"Family base does not split identity")
	check(Values.resolve(arbitrary.id,catalog).id==arbitrary.id,"Procedural identity roundtrip")
	check(Values.configure("r100",{"value":"1 kΩ"},catalog).id=="r1000","Matching legacy identity retained")
	for id in catalog:check(Values.resolve(id,catalog).id==id,"Every legacy ID preserved: "+str(id))
	check(not Values.configure("r100",{"value":"0 Ω"},catalog).ok,"No false zero-ohm model")
	check(not Values.configure("r100",{"power_rating_w":1},catalog).ok,"Ideal resistor does not invent power model")
	check(not Values.configure("c1.0",{"voltage_rating":500},catalog).ok,"Text capacitor rating is not a simulation field")
	check(Values.configure("c1.0",{"value":"23.456 nF"},catalog).ok,"Arbitrary capacitor")
	check(Values.configure("l1",{"value":"7.123 mH"},catalog).ok,"Arbitrary inductor")
	check(Values.configure("r100_t1_w25",{"value":"333 Ω","power_rating_w":"2.37 W","resistance_tolerance":0.02},catalog).ok,"Independent physical resistor parameters")
	check(not Values.configure("r100_t1_w25",{"power_rating_w":101},catalog).ok,"Existing physical watts bound")
	check(not Values.configure("r100_t1_w25",{"resistance_tolerance":0.21},catalog).ok,"Existing manufacturing tolerance bound")
	check(Values.fields(catalog.schottky).has("vf") and Values.fields(catalog.schottky).has("ron"),"Diode numeric model fields exposed")
	for id in catalog:
		if catalog[id].get("worker_model","")=="relay":
			check(not Values.configure(id,{"pickup":"1 mA","release":"2 mA"},catalog).ok,"Relay ordering")
		if catalog[id].get("worker_model","")=="regulator":check(Values.fields(catalog[id]).has("limit"),"Current limit exposed")
	var before := JSON.stringify(catalog)
	var purchase := Values.intent("r100",{"value":"333 Ω"},"1000",catalog,99000)
	check(purchase.ok and purchase.quantity==1000 and purchase.total_price==1000,"Quantity arithmetic beyond old per-buy 100")
	check(not Values.intent("r100",{},1001,catalog,99000).ok,"Stack headroom")
	check(not Values.intent("r100",{},2,catalog,0,1).ok,"Optional capacity headroom")
	check(Values.intent("r100",{},1,catalog,0,1).ok,"Exact capacity boundary")
	check(not Values.intent("r100",{},1,catalog,-1).ok,"Invalid existing count")
	var expensive := catalog.duplicate(true);expensive.r100.price=1000000000
	check(not Values.intent("r100",{},2,expensive).ok,"Cost overflow blocked before multiplication")
	check(JSON.stringify(catalog)==before,"Validation does not mutate input catalog")
	check(not Values.resolve(arbitrary.id+";value=1",catalog).ok,"Duplicate fields rejected")
	check(not Values.resolve(arbitrary.id.replace("value=","price="),catalog).ok,"Client price injection rejected")
	check(not Values.resolve("cv1:r100:value=333000e-3",catalog).ok,"Noncanonical ID rejected")
	print("component_values deferred engine fixtures passed: ",checks)
	quit()
