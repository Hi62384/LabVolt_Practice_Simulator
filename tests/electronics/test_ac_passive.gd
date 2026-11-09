extends SceneTree
func _initialize():
 var B=load("res://scripts/ac_supply_bridge.gd");var S=load("res://scripts/dc_station.gd");var C=load("res://scripts/dc_coupling.gd")
 var lab=load("res://scripts/lab_state.gd").new();var bridge=B.new(lab)
 lab.initialize(bridge.available_ports(),{});lab.switches.R[1]=true
 lab.cables.append_array([{"a":"AM0_OUT","b":"R0_P"},{"a":"V0_150","b":"R0_P"},{"a":"V0_COM","b":"R0_N"}])
 var dc=S.new();dc.master=true;dc.channels[0].enabled=true;dc.channels[0].voltage=5.
 var links=[{"a":{"station":0,"port":"CH1+"},"b":{"station":1,"port":"AM0_IN"}},{"a":{"station":0,"port":"CH1-"},"b":{"station":1,"port":"R0_N"}}]
 for i in 120:C.step([dc,bridge],links,.0005)
 assert(dc.result.ok and bridge.result.ok)
 assert(abs(bridge.result.i.R0_1-5./600.)<.00001)
 assert(abs(lab.readings.voltmeters[0]-5.)<.001)
 assert(lab.readings.ammeters[0]>.0083)
 lab.switches.R[1]=false
 for i in 120:C.step([dc,bridge],links,.0005)
 assert(abs(bridge.result.i.get("R0_1",0))<.000001)
 assert(lab.readings.ammeters[0]<.0001)
 print("PASS: external DC supply drives AC resistor bank through real ammeter and voltmeter, switch removes load")
 quit()

