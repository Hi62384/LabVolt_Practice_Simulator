extends SceneTree
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
const Station=preload("res://scripts/dc_station.gd")
const Coupling=preload("res://scripts/dc_coupling.gd")
const Lab=preload("res://scripts/lab_state.gd")
func _initialize() -> void:
 var cases=[
  {"leads":[["DAQ_I0_N","R0_P"],["DAQ_E0_P","R0_P"],["DAQ_E0_N","R0_N"]],"input":"DAQ_I0_4"},
  {"leads":[["AM0_OUT","R0_P"],["V0_150","R0_P"],["V0_COM","R0_N"]],"input":"AM0_IN"},
  {"leads":[["W0_OUT","R0_P"],["V0_150","R0_P"],["V0_COM","R0_N"],["W0_VN","R0_N"]],"input":"W0_IN"}
 ]
 for setup in cases:
  var results=[]
  for prune in [false,true]:
   var lab=Lab.new();var bridge=Bridge.new(lab);bridge.prune_disconnected=prune
   lab.initialize(bridge.available_ports(),{});lab.switches.R[1]=true
   for lead in setup.leads:lab.cables.append({"a":lead[0],"b":lead[1]})
   var dc=Station.new();dc.prune_disconnected_passives=prune;dc.master=true;dc.channels[0].enabled=true;dc.channels[0].voltage=5.
   var links=[{"a":{"station":0,"port":"CH1+"},"b":{"station":1,"port":setup.input}},{"a":{"station":0,"port":"CH1-"},"b":{"station":1,"port":"R0_N"}}]
   for i in 120:Coupling.step([dc,bridge],links,.0005)
   if not bridge.result.get("ok",false):push_error("Coupled circuit failed");quit(1);return
   var snapshot={"i":float(bridge.result.i.get("R0_1",0)),"v":lab.readings.voltmeters[0],"a":lab.readings.ammeters[0],"w":lab.readings.wattmeters[0],"daq_v":lab.readings.daq_dc_v[0].x,"daq_i":lab.readings.daq_dc_i[0].x}
   results.append(snapshot)
  for key in results[0]:
   if absf(results[0][key]-results[1][key])>1e-8:
    push_error("Pruned and full results differ for %s (%s): %s vs %s"%[setup.input,key,results[0][key],results[1][key]]);quit(1);return
 print("PASS: full and pruned AC models agree for DAQ, ammeter and wattmeter circuits")
 quit()
