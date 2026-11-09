extends RefCounted
## Presentation only: preserve the generated network, values, keys and rubric.
const Catalog=preload("res://scripts/equipment_catalog.gd")
static func socket(id:String)->String:
 var supply={"PV_A":"power supply: red socket 4 in the middle output column", "PV_B":"power supply: black socket 5 below 4", "PV_C":"power supply: blue socket 6 below 5", "PV_N":"power supply: pale-yellow N below 6", "AM0_OUT":"first (left/red) ammeter: socket ±", "AM0_IN":"first (left/red) ammeter: socket 0.5 A", "AM0_2_5":"first (left/red) ammeter: socket 2.5 A", "AM0_8":"first (left/red) ammeter: socket 8 A", "V0_COM":"first (left) voltmeter: black ± common socket", "V0_150":"first (left) voltmeter: yellow socket 100 V", "V0_300":"first (left) voltmeter: yellow socket 250 V"}
 if supply.has(id):return supply[id]
 if id.length()>=4 and id.substr(0,1) in ["R","L","C"] and id.substr(1,1).is_valid_int():
  var module_name={"R":"VARIABLE RESISTANCE","L":"VARIABLE INDUCTANCE","C":"VARIABLE CAPACITANCE"}[id.substr(0,1)]
  var bank=clampi(int(id.substr(1,1)),0,2)
  return "%s panel, %s bank: %s socket"%[module_name,["left/red","middle/black","right/blue"][bank],"top" if id.ends_with("_P") else "bottom"]
 return id
static func switch_labels(bank:Dictionary)->Array[String]:
 var kind:String=bank.kind;var stock:Array=Catalog.LOADS[kind].values
 for mask in range(1,8):
  var sum=0.
  for i in 3:
   if mask&(1<<i):sum+=float(stock[i]) if kind=="C" else 1./float(stock[i])
  var equivalent=sum if kind=="C" else 1./sum
  if absf(equivalent-float(bank.value))>maxf(1e-12,absf(float(bank.value))*1e-6):continue
  var labels:Array[String]=[]
  for i in 3:
   if mask&(1<<i):labels.append(("%.1f µF"%(float(stock[i])*1e6)) if kind=="C" else ("%.0f Ω"%float(stock[i])) if kind=="R" else ("%.1f H"%float(stock[i])))
  return labels
 return []
static func apply(assignment:Dictionary)->Dictionary:
 if assignment.get("course_id","")!="ELM253" or assignment.get("kind","")!="lab":return assignment
 var plan:Dictionary=assignment.get("physical_ac_plan",{})
 if not plan.get("banks") is Array or not plan.get("source_nodes") is Dictionary:return assignment
 var groups:Dictionary={};var wires:Array=[]
 for node in plan.source_nodes:groups[str(node)]=[str(plan.source_nodes[node])]
 var text:Array[String]=["Turn supply power OFF. Keep supply power OFF while selecting sockets, moving leads, changing bank switches, and making every cable connection.", "YOUR PHYSICAL BENCH — connect one cable at a time. These steps describe the physical experiment, not the separate calculation examples.", "Open the drawer under your assigned AC table. Click a coloured cable bag to take ONE cable. Click its first socket, then its second socket. Go back for the next cable.", "A socket means a round plug hole. A bank means one set of three little switches between a top and bottom socket. Look at the printed panel names. Press F while aiming at a control to inspect it; F/Esc returns to walking.", "Turn supply power OFF. Turn all resistance, inductance and capacitance bank switches OFF. Set the large supply dial to %.3f%% and frequency to %.1f Hz."%[float(plan.get("variable_level",0))*100,float(plan.get("frequency_hz",60))]]
 for bank in plan.banks:
  var id:String=str(bank.kind)+str(bank.index)
  var labels=switch_labels(bank)
  if labels.is_empty():return assignment # Never invent a stock switch setting.
  text.append("Find %s. Switch ON only %s; leave its other switches OFF."%[socket(id+"_P").trim_suffix(": top socket")," and ".join(labels)])
  for side in ["a","b"]:
   var node:String=str(bank[side])
   if not groups.has(node):groups[node]=[]
   groups[node].append(id+("_P" if side=="a" else "_N"))
 var meter="AM0_IN"
 var amps:float=assignment.get("reference_ac",{}).get("result",{}).get("currents",{}).get("R0",Vector2.ZERO).length()
 if amps>7.2:return {"error":"R0 current exceeds the supported 7.2 A limit. Keep supply power OFF; do not wire or energize this experiment."}
 if amps>.45:meter="AM0_2_5" if amps<=2.25 else "AM0_8"
 for terminals in groups.values():
  for i in range(1,terminals.size()):
   if str(terminals[i])=="R0_P":wires.append([terminals[0],"AM0_OUT"]);wires.append([meter,"R0_P"])
   else:wires.append([terminals[0],terminals[i]])
 var first:Dictionary=plan.banks.filter(func(bank):return str(bank.kind)+str(bank.index)=="R0")[0]
 var voltages:Dictionary=assignment.get("reference_ac",{}).get("result",{}).get("voltages",{})
 var volts:float=(voltages.get(first.a,Vector2.ZERO)-voltages.get(first.b,Vector2.ZERO)).length()
 wires.append(["V0_COM","R0_N"]);wires.append(["V0_150" if volts<=90 else "V0_300","R0_P"])
 text.append("Now make these %d cable connections, in order. Any cable colour works. When a socket already has a plug, click its end to stack the next one."%wires.size())
 for i in wires.size():text.append("Cable %d: %s → %s."%[i+1,socket(str(wires[i][0])),socket(str(wires[i][1]))])
 text.append("The ammeter is inserted into one wire feeding the resistor. The voltmeter uses two EXTRA cables across the resistor. Do not put the ammeter across the supply.")
 text.append("Check every cable against the steps. Turn the supply ON. Read the left ammeter and left voltmeter, then use Record equipment on the worksheet. Turn power OFF when finished. A node letter on the diagram just means sockets joined together; it is not another hidden part to find.")
 var old:String=assignment.get("procedure","")
 assignment.procedure="\n\n".join(text)
 assignment.equipment_text=assignment.procedure
 var teaching:Dictionary=assignment.get("teaching",{}).duplicate(true)
 teaching.equipment=assignment.procedure;assignment.teaching=teaching
 if not old.is_empty() and str(assignment.get("data","")).ends_with(old):assignment.data=str(assignment.data).trim_suffix(old)+assignment.procedure
 assignment.physical_wire_steps=wires
 return assignment
