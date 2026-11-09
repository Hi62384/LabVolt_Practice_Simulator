extends SceneTree
var failures := 0
const Devices=preload("res://scripts/device_models.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
func check(ok: bool,label: String):
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize():
	var solver=load("res://scripts/electronics_solver.gd").new()
	var nodes: Array=[]
	for i in 14:nodes.append("p"+str(i))
	for type in ["hc00","hc08","hc32","hc86","hc04"]:
		for a in 2:
			for b in 2:
				var voltages={"p6":0.0,"p13":5.0,"p0":a*5.0,"p1":b*5.0}
				var parts=Devices.expand(Catalog.all()[type],"gate",nodes,{},voltages)
				var ids={};var unique=true
				for part in parts:
					if ids.has(part.id):unique=false
					ids[part.id]=true
				check(unique,type+" unique primitive ids")
				parts.append({"id":"supply","kind":"V","a":"p13","b":"p6","value":5.0})
				var output="p1" if type=="hc04" else "p2"
				parts.append({"id":"load","kind":"R","a":output,"b":"p6","value":1000.0})
				var result=solver.solve(parts)
				var expected=false
				match type:
					"hc00":expected=not(a==1 and b==1)
					"hc08":expected=a==1 and b==1
					"hc32":expected=a==1 or b==1
					"hc86":expected=a!=b
					"hc04":expected=a==0
				check(result.ok and absf(result.i.load-(5.0/1040 if expected else 0))<.00001,type+" truth table with loaded output "+str(a)+str(b))
	var pot=Devices.expand(Catalog.all().pot10k,"pot",["p","w","n"],{"setting":.25})
	pot.append({"id":"v","kind":"V","a":"p","b":"n","value":10.0})
	var result=solver.solve(pot)
	check(result.ok and absf(result.drop["pot/lower"]-7.5)<.001,"potentiometer divider actual voltage")
	var segments=Devices.expand(Catalog.all().seven_segment,"seg",["a","b","c","d","e","f","g","dp","n"],{})
	check(segments.size()==8,"seven segment exposes eight diode branches")
	quit(failures)
