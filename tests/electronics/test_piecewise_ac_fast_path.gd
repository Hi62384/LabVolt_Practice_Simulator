extends SceneTree
const Lab=preload("res://scripts/lab_state.gd")
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
const Station=preload("res://scripts/dc_station.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Coupling=preload("res://scripts/dc_coupling.gd")
func fixture(fast: bool) -> Dictionary:
 var lab=Lab.new();var ac=Bridge.new(lab);lab.initialize(ac.available_ports(),{});lab.powered=true;lab.level=.1;lab.recalculate()
 var dc=Station.new();dc.fast_linear_ac_enabled=fast;dc.wires=[["R1b","Da"]]
 var links=[{"a":{"station":0,"port":"R1a"},"b":{"station":1,"port":"DAQ_I0_4"}},{"a":{"station":0,"port":"Db"},"b":{"station":1,"port":"PV_N"}}]
 lab.cables.append_array([{"a":"DAQ_I0_N","b":"PV_A"},{"a":"DAQ_E0_P","b":"PV_A"},{"a":"DAQ_E0_N","b":"PV_N"}])
 return {"lab":lab,"ac":ac,"dc":dc,"links":links}
func _initialize() -> void:
 var a=fixture(false);var b=fixture(true)
 for i in 1200:
  if i==400:
   for item in [a,b]:item.lab.frequency=50.0;item.lab.level=.3
  for item in [a,b]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if not a.dc.result.ok or not b.dc.result.ok:push_error("Diode solve failed at %d"%i);quit(1);return
  for id in ["r0","diode"]:
   if absf(float(a.dc.result.i[id])-float(b.dc.result.i[id]))>1e-7 or absf(float(a.dc.result.drop[id])-float(b.dc.result.drop[id]))>1e-6:
    push_error("Diode mismatch %s at %d"%[id,i]);quit(1);return
  for id in b.dc.result.i:
   if str(id).contains("#fast_bias"):push_error("Internal bias leaked into result");quit(1);return
  if i>80 and a.lab.readings.daq_i[0].distance_to(b.lab.readings.daq_i[0])>1e-6:push_error("Diode DAQ mismatch");quit(1);return
 if not b.dc.linear_ac_cache.get("piecewise",false):push_error("Single diode did not use fast path");quit(1);return
 var plan=Coupling.linear_frame_plan([b.dc,b.ac],b.links,Coupling.groups_for(2,b.links),.0005)
 if plan.is_empty():push_error("Diode frame plan missing");quit(1);return
 for i in 200:
  if not Coupling.linear_frame_step(plan,[b.dc,b.ac],.0005):push_error("Diode frame plan stopped");quit(1);return
  Coupling.step([a.dc,a.ac],a.links,.0005)
  if absf(float(a.dc.result.i.diode)-float(b.dc.result.i.diode))>1e-7:push_error("Diode planned-step mismatch");quit(1);return
 # Reactive memory must be used when selecting the diode region and when
 # updating capacitor and inductor state, including a switch transition.
 for item in [a,b]:
  item.lab.switches.C[0]=true;item.lab.switches.L[0]=true
  item.lab.cables.append_array([{"a":"C0_P","b":"PV_A"},{"a":"C0_N","b":"PV_N"},{"a":"L0_P","b":"PV_A"},{"a":"L0_N","b":"PV_N"}])
 for i in 1000:
  if i==350:
   for item in [a,b]:item.lab.switches.L[0]=false
  if i==600:
   for item in [a,b]:item.lab.switches.L[0]=true
  for item in [a,b]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if absf(float(a.dc.result.i.diode)-float(b.dc.result.i.diode))>1e-6:push_error("Reactive diode current mismatch at %d"%i);quit(1);return
  for id in ["C0_0","L0_0"]:
   if absf(float(a.ac.solver.memory.get(id,0.0))-float(b.ac.solver.memory.get(id,0.0)))>1e-6:push_error("Reactive diode memory mismatch %s at %d"%[id,i]);quit(1);return
 if not b.dc.linear_ac_cache.get("piecewise",false) or b.dc.linear_ac_cache.off.states.size()!=2:push_error("Reactive diode missed fast path");quit(1);return
 # Put the diode and reactive elements in the same series branch, so their
 # stored state directly affects the voltage that selects the diode region.
 var series_slow=fixture(false);var series_fast=fixture(true)
 for item in [series_slow,series_fast]:
  item.links[1].b.port="L0_P"
  item.lab.switches.L[0]=true;item.lab.switches.C[0]=true
  item.lab.cables.append_array([{"a":"L0_N","b":"PV_N"},{"a":"C0_P","b":"L0_P"},{"a":"C0_N","b":"L0_N"}])
 for i in 800:
  for item in [series_slow,series_fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if not series_slow.dc.result.ok or not series_fast.dc.result.ok:push_error("Series reactive solve failed");quit(1);return
  if absf(float(series_slow.dc.result.i.diode)-float(series_fast.dc.result.i.diode))>1e-6:push_error("Series diode mismatch at %d"%i);quit(1);return
  for id in ["C0_0","L0_0"]:
   if absf(float(series_slow.ac.solver.memory.get(id,0.0))-float(series_fast.ac.solver.memory.get(id,0.0)))>1e-6:push_error("Series reactive state mismatch %s at %d"%[id,i]);quit(1);return
 if not series_fast.dc.linear_ac_cache.get("piecewise",false):push_error("Series diode missed fast path");quit(1);return
 # Two different diode models in series with reactive components must choose
 # the same simultaneous operating point as the full nonlinear solver.
 var double_slow=fixture(false);var double_fast=fixture(true)
 for item in [double_slow,double_fast]:
  item.dc.board=Board.empty();item.dc.board.ports=["A1","A2","F1","F2"]
  item.dc.board.parts=[{"id":"led","type":"led","a":"A1","b":"A2"}]
  item.dc.wires.append(["Db","B1"]);item.links[1].a.port="B2"
  item.lab.switches.L[0]=true
  item.lab.cables.append_array([{"a":"L0_P","b":"PV_A"},{"a":"L0_N","b":"PV_N"}])
 for i in 800:
  for item in [double_slow,double_fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if not double_slow.dc.result.ok or not double_fast.dc.result.ok:push_error("Two-diode solve failed at %d"%i);quit(1);return
  for id in ["diode","board/led"]:
   if absf(float(double_slow.dc.result.i[id])-float(double_fast.dc.result.i[id]))>1e-6:push_error("Two-diode current mismatch %s at %d"%[id,i]);quit(1);return
  if i%20==0:
   for item_pair in [[double_slow.dc,double_fast.dc],[double_slow.ac,double_fast.ac]]:
    for pin in item_pair[0].result.v:
     if not item_pair[1].result.v.has(pin) or absf(float(item_pair[0].result.v[pin])-float(item_pair[1].result.v[pin]))>1e-6:push_error("Two-diode node mismatch %s at %d"%[pin,i]);quit(1);return
  if absf(float(double_slow.ac.solver.memory.get("L0_0",0.0))-float(double_fast.ac.solver.memory.get("L0_0",0.0)))>1e-6:push_error("Two-diode reactive state mismatch");quit(1);return
 if not double_fast.dc.linear_ac_cache.get("piecewise",false) or double_fast.dc.linear_ac_cache.diodes.size()!=2:push_error("Two-diode reactive circuit missed fast path");quit(1);return
 # Protection must see the same half-wave source current and trip at the same step.
 var trip_slow=fixture(false);var trip_fast=fixture(true)
 for item in [trip_slow,trip_fast]:item.dc.resistance[0]=1.0;item.lab.level=.3
 var tripped_at=[]
 for item in [trip_slow,trip_fast]:
  var at:=-1
  for i in 300:
   Coupling.step([item.dc,item.ac],item.links,.0005)
   if not item.lab.powered:at=i;break
  tripped_at.append(at)
 if tripped_at[0]<0 or tripped_at[0]!=tripped_at[1]:push_error("Diode breaker trip differs: %s"%str(tripped_at));quit(1);return
 print("PASS: diode fast paths match full solver across cycles, reactive state, edits, protection and DAQ");quit()
