extends SceneTree
func _initialize():
 var B=load("res://scripts/ac_supply_bridge.gd")
 var window=[];var values=[];var dc=[]
 for i in 37:
  var t=.013+i*.00047;window.append({"time":t});values.append(2.+sqrt(2.)*(7.*cos(TAU*60.*t)-3.*sin(TAU*60.*t)));dc.append(5.)
 assert(B.fit_phasor(window,values,60.).distance_to(Vector2(7.,3.))<.00001)
 assert(B.fit_phasor(window,dc,60.).distance_to(Vector2(5.,0.))<.00001)
 var a=load("res://scripts/dc_station.gd").new();var b=load("res://scripts/dc_station.gd").new()
 a.solver.time=1.;b.solver.time=.5;a.generator.enabled=true
 var links=[{"a":{"station":0,"port":"GEN"},"b":{"station":1,"port":"R1a"}},{"a":{"station":0,"port":"REF"},"b":{"station":1,"port":"R1b"}}]
 load("res://scripts/dc_coupling.gd").step([a,b],links,.0005)
 assert(abs(a.solver.time-b.solver.time)<.0000001)
 print("PASS: DAQ phasor preserves magnitude/phase with DC offset and incomplete periods; connected clocks align")
 quit()
