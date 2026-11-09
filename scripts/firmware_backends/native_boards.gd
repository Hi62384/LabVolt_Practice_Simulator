extends RefCounted
## Header maps are physical board pins. Runtime GPIO-only nodes remain internal.
## Sources: official Uno R3 full pinout and Raspberry Pi Pico Rev3 datasheet.
const Adapter=preload("res://scripts/firmware_backends/board_adapter.gd")
static func catalog() -> Dictionary:
 var uno: Array=["NC","IOREF","RESET","3V3","5V","GND1","GND2","VIN"]
 for i in 6:uno.append("A"+str(i))
 for i in 14:uno.append("D"+str(i))
 uno.append_array(["GND3","AREF","SDA","SCL"])
 var pico: Array=["GP0","GP1","GND3","GP2","GP3","GP4","GP5","GND8","GP6","GP7","GP8","GP9","GND13","GP10","GP11","GP12","GP13","GND18","GP14","GP15","GP16","GP17","GND23","GP18","GP19","GP20","GP21","GND28","GP22","RUN","GP26","GP27","AGND","GP28","ADC_VREF","3V3","3V3_EN","GND38","VSYS","VBUS"]
 var nano: Array=["D1","D0","RESET","GND1","D2","D3","D4","D5","D6","D7","D8","D9","D10","D11","D12","D13","3V3","AREF","A0","A1","A2","A3","A4","A5","A6","A7","5V","RESET2","GND2","VIN"]
 var out := {}
 for board in ["uno","pico","nano"]:
  out["native_"+board]={"name":"Arduino Uno R3" if board=="uno" else "Arduino Nano (classic ATmega328P)" if board=="nano" else "Raspberry Pi Pico","kind":"native_controller","board":board,"category":"PCB","pins":uno if board=="uno" else nano if board=="nano" else pico,"price":50 if board=="uno" else 35,"space":8,"rarity":"Uncommon","rating":"Compiled native C/C++ image · host lockstep · GPIO/ADC/UART; cooperative electrical SPI/I2C when host bus adapter enabled; no USB/MicroPython. Educational board power model."}
 return out
static func logical_nodes(board: String,id: String,nodes: Array) -> Array:
 var model: Dictionary=catalog().get("native_"+board,{})
 if model.is_empty() or nodes.size()!=model.pins.size():return []
 var labels: Array=model.pins;var out: Array=[]
 for pin in Adapter.catalog()[board].pins:
  var label: String="5V" if pin=="VCC" else "GND1" if pin=="GND" and board in ["uno","nano"] else "GND3" if pin=="GND" else pin
  var index := labels.find(label)
  out.append(nodes[index] if index>=0 else id+"/@"+pin)
 return out
static func expand(model: Dictionary,id: String,n: Array,state: Dictionary,v: Dictionary,runtime: Dictionary) -> Array:
 if n.size()!=model.pins.size():return []
 var board: String=model.board;var names: Array=model.pins;var logical := logical_nodes(board,id,n)
 var get_node := func(label):return n[names.find(label)]
 var rail: String=logical[0];var ground: String=logical[1]
 var current: Dictionary=runtime.get(id,{})
 var out: Array=[{"id":id,"kind":"native_controller","board":board,"nodes":logical,"physical_nodes":n,"program":state.get("native_firmware",{}),"run":state.get("run",true),"reset_node":get_node.call("RESET" if board in ["uno","nano"] else "RUN"),"aref_node":get_node.call("AREF" if board in ["uno","nano"] else "ADC_VREF")}]
 out.append_array(Adapter.expand(Adapter.catalog()[board],id,logical,{},v,runtime))
 for i in names.size():
  if str(names[i]).begins_with("GND") or names[i]=="AGND":
   if n[i]!=ground:out.append({"id":id+"/ground"+str(i),"kind":"R","a":n[i],"b":ground,"value":.001})
 var rail_v := float(v.get(rail,0))-float(v.get(ground,0))
 var reset: String=get_node.call("RESET" if board in ["uno","nano"] else "RUN")
 out.append({"id":id+"/reset_pull","kind":"R","a":reset,"b":rail,"value":10000. if board in ["uno","nano"] else 50000.})
 if board in ["uno","nano"]:
  if board=="nano":out.append({"id":id+"/reset_alias","kind":"R","a":get_node.call("RESET2"),"b":reset,"value":.001})
  for pair in ([["IOREF","5V"],["SDA","A4"],["SCL","A5"]] if board=="uno" else []):out.append({"id":id+"/alias"+pair[0],"kind":"R","a":get_node.call(pair[0]),"b":get_node.call(pair[1]),"value":.001})
  var vin := float(v.get(get_node.call("VIN"),0))-float(v.get(ground,0))
  if vin>1.1:out.append({"id":id+"/reg5","kind":"supply","a":rail,"b":ground,"value":minf(5.,vin-1.1),"resistance":.2,"limit":.2})
  if rail_v>3.5:out.append({"id":id+"/reg3","kind":"supply","a":get_node.call("3V3"),"b":ground,"value":3.3,"resistance":.2,"limit":.05})
  out.append({"id":id+"/aref","kind":"R","a":get_node.call("AREF"),"b":rail,"value":1e7})
 else:
  var vsys: String=get_node.call("VSYS");var enable: String=get_node.call("3V3_EN")
  out.append({"id":id+"/usb_diode","kind":"D","a":get_node.call("VBUS"),"b":vsys,"vf":.3,"ron":.5})
  out.append({"id":id+"/enable_pull","kind":"R","a":enable,"b":vsys,"value":100000.})
  var supply := float(v.get(vsys,0))-float(v.get(ground,0))
  if supply>=1.8 and supply<=5.5 and float(v.get(enable,0))-float(v.get(ground,0))>.5:
   out.append({"id":id+"/reg3","kind":"supply","a":rail,"b":ground,"value":3.3,"resistance":.2,"limit":.3})
  out.append({"id":id+"/vref","kind":"R","a":get_node.call("ADC_VREF"),"b":rail,"value":200.})
  # Board-only GP24 and GP29 sense the actual external supply, not fake headers.
  for pair in [["GP24",get_node.call("VBUS"),5600.,10000.],["GP29",vsys,200000.,100000.]]:
   var gpio: String=id+"/@"+pair[0]
   out.append({"id":id+"/sense_hi"+pair[0],"kind":"R","a":pair[1],"b":gpio,"value":pair[2]})
   out.append({"id":id+"/sense_lo"+pair[0],"kind":"R","a":gpio,"b":ground,"value":pair[3]})
 return out
