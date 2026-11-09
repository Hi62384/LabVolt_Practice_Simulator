extends SceneTree
func _initialize():
 var Solver=load("res://scripts/electronics_solver.gd")
 for current in [.01,-.01,0.]:
  for resistance in [100.,1000.,10000.]:
   var solver=Solver.new()
   var solved=solver.solve([{"id":"source","kind":"current_source","a":"plus","b":"minus","value":current,"compliance":30.,"resistance":.01,"rout":1e9},{"id":"load","kind":"R","a":"plus","b":"minus","value":resistance}])
   assert(solved.ok,solved.get("error",""))
   var expected=clampf(current*resistance,-30.,30.)
   assert(abs(solved.drop.load-expected)<.001)
   assert(abs(solved.i.load-expected/resistance)<.000001)
   assert(solved.mode.source==("CC" if abs(current*resistance)<=30 else "COMPLIANCE"))
 var opened=Solver.new().solve([{"id":"source","kind":"current_source","a":"plus","b":"minus","value":.01,"compliance":12.,"resistance":.01,"rout":1e9}])
 assert(opened.ok and abs(opened.drop.source-12.)<.001 and opened.mode.source=="COMPLIANCE")
 var station=load("res://scripts/dc_station.gd").new()
 assert(station.apply({"op":"current_source","key":"current","value":.01})=="")
 assert(station.apply({"op":"current_source","key":"compliance","value":20.})=="")
 assert(station.apply({"op":"current_source","key":"enabled","value":true})=="")
 station.master=true;station.resistance[0]=1000.;station.wires=[["IS+","R1a"],["IS-","R1b"],["VΩ","R1a"],["COM","R1b"]]
 station.step(.0005);assert(station.result.ok)
 assert(abs(station.result.drop.r0-(.01/(1./1000.+1./1e7+1./1e9)))<.000001 and station.result.mode.isource=="CC")
 station.resistance[0]=10000.;station.step(.0005)
 assert(station.result.ok and station.result.mode.isource=="COMPLIANCE" and abs(station.result.drop.r0-20.)<.001)
 assert(station.apply({"op":"current_source","key":"current","value":NAN})!="")
 assert(station.apply({"op":"current_source","key":"enabled","value":1})!="")
 assert(station.snapshot().current_source.compliance==20.)
 var combined=load("res://scripts/dc_station.gd").new();combined.master=true;combined.resistance[0]=1000.
 for source_index in 4:
  assert(combined.apply({"op":"current_source","index":source_index,"key":"current","value":.001*(source_index+1)})=="")
  assert(combined.apply({"op":"current_source","index":source_index,"key":"enabled","value":true})=="")
  var suffix="" if source_index==0 else str(source_index+1)
  combined.wires.append_array([["IS"+suffix+"+","R1a"],["IS"+suffix+"-","R1b"]])
 combined.step(.0005)
 assert(combined.result.ok and abs(combined.result.drop.r0-(.01/(1./1000.+4./1e9)))<.000001)
 assert(combined.snapshot().current_sources.size()==4)
 assert(combined.apply({"op":"current_source","index":4,"key":"enabled","value":true})!="")
 print("PASS: positive/negative/zero current across three loads, compliance/open-circuit, actual DC terminal wiring and readouts, source schema/NaN rejection")
 quit()
