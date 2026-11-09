extends SceneTree
func _initialize():
 var B=load("res://scripts/ac_supply_bridge.gd");var S=load("res://scripts/dc_station.gd");var C=load("res://scripts/dc_coupling.gd")
 var lab=load("res://scripts/lab_state.gd").new();var bridge=B.new(lab)
 lab.initialize(bridge.available_ports(),{});lab.switches.R[1]=true
 lab.cables.append_array([{"a":"DAQ_I0_N","b":"R0_P"},{"a":"DAQ_E0_P","b":"R0_P"},{"a":"DAQ_E0_N","b":"R0_N"}])
 var dc=S.new();dc.master=true;dc.channels[0].enabled=true;dc.channels[0].voltage=5.
 var links=[{"a":{"station":0,"port":"CH1+"},"b":{"station":1,"port":"DAQ_I0_4"}},{"a":{"station":0,"port":"CH1-"},"b":{"station":1,"port":"R0_N"}}]
 for i in 120:C.step([dc,bridge],links,.0005)
 assert(dc.result.ok and bridge.result.ok)
 assert(abs(bridge.result.i.R0_1-5./600.)<.00001)
 assert(abs(lab.readings.daq_v[0].length()-5.)<.001)
 assert(lab.readings.daq_i[0].length()>.0083)
 lab.switches.R[1]=false
 for i in 120:C.step([dc,bridge],links,.0005)
 assert(abs(bridge.result.i.get("R0_1",0))<.000001)
 assert(lab.readings.daq_i[0].length()<.0001)
 print("PASS: external DC supply drives AC resistor bank through DAQ voltage and current inputs, switch removes load")
 quit()


