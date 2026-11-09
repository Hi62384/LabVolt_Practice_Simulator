extends SceneTree
func _initialize():
 var S=load("res://scripts/dc_station.gd");var C=load("res://scripts/dc_coupling.gd")
 var a=S.new();var b=S.new();var stations=[a,b];var links=[{"a":{"station":0,"port":"CH1+"},"b":{"station":1,"port":"R1a"}},{"a":{"station":0,"port":"CH1-"},"b":{"station":1,"port":"R1b"}}]
 a.master=true;a.channels[0].enabled=true;a.channels[0].voltage=10;a.channels[0].limit=.005
 C.step(stations,links,.0005)
 assert(a.result.ok and b.result.ok)
 assert(abs(float(b.result.i.r0)-.005)<.000001 and a.result.mode.s0=="CC")
 assert(abs(a.result.i.s0+b.result.i.r0)<.000001)
 assert(b.apply({"op":"resistor","index":0,"value":4000})=="")
 C.step(stations,links,.0005)
 assert(a.result.mode.s0=="CV" and abs(b.result.i.r0-.0025)<.000001)
 assert(b.apply({"op":"wire","a":"R1a","b":"Ca"})=="")
 assert(b.apply({"op":"wire","a":"R1b","b":"Cb"})=="")
 C.step(stations,links,.0005);var charge=b.solver.memory.cap
 assert(charge>0)
 C.step(stations,[],.0005)
 assert(not a.linked and not b.linked and b.solver.memory.cap>0 and b.solver.memory.cap<charge)
 print("PASS: inter-bench current loading, CC/CV transition, Kirchhoff current, capacitor state retained on disconnect")
 var rack=preload("res://scripts/lab_state.gd").new()
 rack.initialize(["P_N","PV_N","DC_7","DC_N7","IGBT_1","IGBT_2","IGBT_3","IGBT_GATE1","IGBT_COMMON","R0_P","R0_N"],{})
 rack.level=.5
 rack.powered=true
 rack.switches.R[2]=true
 for wire in [["DC_7","IGBT_1"],["DC_N7","IGBT_2"],["IGBT_3","R0_P"],["IGBT_2","R0_N"]]:
  rack.cables.append({"a":wire[0],"b":wire[1]})
 var bridge=preload("res://scripts/ac_supply_bridge.gd").new(rack)
 var generator=S.new()
 generator.generator.merge({"enabled":true,"wave":"Pulse","frequency":100.,"amplitude":2.5,"offset":2.5,"resistance":50.},true)
 var pulse_links=[
  {"a":{"station":0,"port":"GEN"},"b":{"station":1,"port":"IGBT_GATE1"}},
  {"a":{"station":0,"port":"REF"},"b":{"station":1,"port":"IGBT_COMMON"}}
 ]
 var output_low := false
 var output_high := false
 for i in 42:
  C.step([generator,bridge],pulse_links,.0005)
  if not bridge.result.ok:
   push_error("IGBT PWM solve failed: " + str(bridge.result))
   quit(1)
   return
  var volts: float = bridge.result.v.IGBT_3 - bridge.result.v.IGBT_2
  output_low = output_low or absf(volts)<.001
  output_high = output_high or absf(volts-60.)<.1
 if not (output_low and output_high):
  push_error("IGBT load did not follow both states of the external pulse")
  quit(1)
  return
 print("PASS: AC rack IGBT switches a loaded DC bus from another bench's pulse generator")
 quit()
