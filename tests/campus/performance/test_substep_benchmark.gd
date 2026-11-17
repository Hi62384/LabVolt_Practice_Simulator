extends SceneTree
const Lab=preload("res://scripts/lab_state.gd")
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
const Station=preload("res://scripts/dc_station.gd")
const Coupling=preload("res://scripts/dc_coupling.gd")
func _initialize() -> void:
 var lab=Lab.new();var ac=Bridge.new(lab);lab.initialize(ac.available_ports(),{});lab.powered=true;lab.level=.1;lab.recalculate()
 var dc=Station.new();var links=[{"a":{"station":0,"port":"R1a"},"b":{"station":1,"port":"PV_A"}},{"a":{"station":0,"port":"R1b"},"b":{"station":1,"port":"PV_N"}}]
 lab.switches.L[0]=true;lab.switches.C[0]=true
 lab.cables.append_array([{"a":"L0_P","b":"PV_A"},{"a":"L0_N","b":"PV_N"},{"a":"C0_P","b":"PV_A"},{"a":"C0_N","b":"PV_N"}])
 Coupling.step([dc,ac],links,.0005)
 var plan=Coupling.linear_frame_plan([dc,ac],links,Coupling.groups_for(2,links),.0005)
 for idx in [0,1]:
  for field in ["v","i","drop"]:print("FIELDS ",idx," ",field," ",plan.cache.stations[idx].fields[field].size())
 var t=Time.get_ticks_usec()
 for i in 2000:Coupling.linear_frame_step(plan,[dc,ac],.0005)
 var total=Time.get_ticks_usec()-t
 t=Time.get_ticks_usec()
 for i in 2000:
  ac.sample_time+=.0005;ac.finish_step()
 var ac_time=Time.get_ticks_usec()-t
 t=Time.get_ticks_usec()
 for i in 2000:
  dc.solver.time+=.0005;dc.finish_step()
 var dc_time=Time.get_ticks_usec()-t
 print("AC_SUBSTEP total_us=%.1f ac_finish_us=%.1f dc_finish_us=%.1f"%[total/2000.0,ac_time/2000.0,dc_time/2000.0]);quit()


