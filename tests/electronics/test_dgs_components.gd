extends SceneTree
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Lib=preload("res://scripts/component_models/library.gd")
const Device=preload("res://scripts/device_models.gd")
func _initialize():
 var catalog=Catalog.all();var model:Dictionary=catalog.ls47
 var nodes:=[];var voltages:={}
 for i in 16:nodes.append(str(i));voltages[str(i)]=0.0
 voltages["15"]=5.0
 for pin in [2,3,4]:voltages[str(pin)]=5.0
 var expected:=["8","9","10","11","12","14"]
 var state:Dictionary=Lib.tick(model,nodes,voltages,{},.0005)
 assert(state.powered and state.drive.size()==6)
 for pin in expected:assert(state.drive[pin]==0)
 voltages["6"]=5.0
 state=Lib.tick(model,nodes,voltages,state,.0005)
 assert(state.drive.size()==2 and state.drive.has("11") and state.drive.has("10"))
 voltages["2"]=0.0
 state=Lib.tick(model,nodes,voltages,state,.0005)
 assert(state.drive.size()==7)
 voltages["3"]=0.0
 state=Lib.tick(model,nodes,voltages,state,.0005)
 assert(state.drive.is_empty())
 var display:Dictionary=catalog.seven_segment_ca
 var terminals:=["a","b","c","d","e","f","g","dp","common"]
 var parts:=Device.expand(display,"display",terminals,{})
 assert(parts.size()==8 and parts[0].a=="common" and parts[0].b=="a")
 var sim=preload("res://scripts/component_models/standalone.gd").new()
 var pins:=[]
 for i in 16:pins.append("pin%d"%i)
 pins[7]="g";pins[15]="vcc"
 var sources: Array=[{"id":"vcc","kind":"V","a":"vcc","b":"g","value":5.0,"resistance":.01}]
 for pin in [0,1,2,3,4,5,6]:
  sources.append({"id":"input%d"%pin,"kind":"V","a":pins[pin],"b":"g","value":5.0 if pin in [2,3,4,6] else 0.0,"resistance":.01})
 for pair in [[11,"b"],[10,"c"],[12,"a"]]:
  sources.append({"id":"res_"+pair[1],"kind":"R","a":"vcc","b":"led_"+pair[1],"value":330.0})
  sources.append({"id":"led_"+pair[1],"kind":"LED","a":"led_"+pair[1],"b":pins[pair[0]],"vf":1.8,"ron":10.0})
 var solved:Dictionary={}
 for i in 12:solved=sim.step([{"id":"chip","model":model,"nodes":pins}],sources,[],.0005)
 assert(solved.ok and float(solved.i.led_b)>.005 and float(solved.i.led_c)>.005 and absf(float(solved.i.led_a))<.0001)
 print("PASS 74LS47 BCD, lamp test, blanking and common-anode polarity")
 quit()
