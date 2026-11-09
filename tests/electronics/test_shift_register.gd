extends SceneTree
func _initialize():
 var M=load("res://scripts/stateful_devices.gd");var S=load("res://scripts/electronics_solver.gd")
 var pins=[];var v={}
 for i in 16:pins.append(str(i));v[str(i)]=0.
 v["15"]=5.;v["9"]=5.
 var state={}
 for bit in range(7,-1,-1):
  v["13"]=5. if (165&(1<<bit)) else 0.;v["10"]=0.;state=M.tick("shift595",pins,v,state,.0005)
  v["10"]=5.;state=M.tick("shift595",pins,v,state,.0005)
 assert(state.shift==165 and int(state.get("latched",0))==0)
 v["11"]=5.;state=M.tick("shift595",pins,v,state,.0005);assert(state.latched==165)
 var parts=M.expand("shift595","ic",pins,state).filter(func(p):return p.kind!="stateful")
 parts.append({"id":"v","kind":"V","a":"15","b":"7","value":5.,"resistance":.01})
 parts.append({"id":"load","kind":"R","a":"14","b":"7","value":1000.})
 var result=S.new().solve(parts);assert(result.ok);assert(abs(float(result.i.load)-5./1040.)<.00001)
 v["12"]=5.;state=M.tick("shift595",pins,v,state,.0005)
 parts=M.expand("shift595","ic",pins,state).filter(func(p):return p.kind!="stateful")
 parts.append({"id":"v","kind":"V","a":"15","b":"7","value":5.,"resistance":.01});parts.append({"id":"load","kind":"R","a":"14","b":"7","value":1000.})
 result=S.new().solve(parts);assert(result.ok and abs(float(result.i.load))<.000001)
 v["9"]=0.;state=M.tick("shift595",pins,v,state,.0005);assert(state.shift==0 and state.latched==165)
 v["15"]=0.;state=M.tick("shift595",pins,v,state,.0005);assert(not state.powered)
 print("PASS: 74HC595 serial order, separate latch, loaded output current, output disable, asynchronous shift clear, power loss")
 quit()
