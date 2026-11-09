extends SceneTree
func _initialize():
 var S=load("res://scripts/dc_station.gd");var C=load("res://scripts/dc_coupling.gd");var B=load("res://scripts/ac_supply_bridge.gd")
 var lab=load("res://scripts/lab_state.gd").new()
 lab.initialize(B.PORTS,{})
 lab.powered=true;lab.level=.1;lab.recalculate()
 var bridge=B.new(lab);var dc=S.new()
 var links=[{"a":{"station":1,"port":"PV_A"},"b":{"station":0,"port":"R1a"}},{"a":{"station":1,"port":"PV_N"},"b":{"station":0,"port":"R1b"}}]
 var sum=0.
 for i in 400:
  C.step([dc,bridge],links,.0005)
  assert(dc.result.ok)
  if i>=200:sum+=pow(float(dc.result.i.r0),2)
 assert(abs(sqrt(sum/200.)-.012)<.0001)
 assert(lab.powered)
 dc.resistance[0]=1.
 for i in 100:C.step([dc,bridge],links,.0005)
 assert(not lab.powered)
 assert("OVERCURRENT" in lab.readings.fault)
 print("PASS: AC supply waveform produces 12 mA RMS in remote 1k load; overload trips source")
 quit()
