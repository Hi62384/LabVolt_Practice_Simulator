extends SceneTree
const Lab=preload("res://scripts/lab_state.gd")
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
const Station=preload("res://scripts/dc_station.gd")
const Coupling=preload("res://scripts/dc_coupling.gd")
func make_case(fast: bool) -> Dictionary:
 var lab=Lab.new();var ac=Bridge.new(lab);lab.initialize(ac.available_ports(),{})
 lab.powered=true;lab.level=.2;lab.recalculate()
 var dc=Station.new();dc.fast_linear_ac_enabled=fast
 var links=[{"a":{"station":0,"port":"R1a"},"b":{"station":1,"port":"PV_A"}},{"a":{"station":0,"port":"R1b"},"b":{"station":1,"port":"PV_N"}}]
 return {"lab":lab,"ac":ac,"dc":dc,"links":links}
func _initialize() -> void:
 var slow=make_case(false);var fast=make_case(true)
 for i in 400:
  if i==130:
   slow.lab.frequency=50.;fast.lab.frequency=50.
  if i==230:
   slow.dc.resistance[0]=500.;fast.dc.resistance[0]=500.
  if i==320:
   slow.lab.level=.4;fast.lab.level=.4
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if not slow.dc.result.ok or not fast.dc.result.ok:push_error("Solver failed");quit(1);return
  for id in ["r0"]:
   if absf(float(slow.dc.result.i[id])-float(fast.dc.result.i[id]))>1e-8:push_error("Current mismatch at %d"%i);quit(1);return
  for id in ["R1a","R1b"]:
   if absf(float(slow.dc.result.v[id])-float(fast.dc.result.v[id]))>1e-7:push_error("Voltage mismatch at %d"%i);quit(1);return
  if slow.lab.readings.has("external_supply_rms") and fast.lab.readings.has("external_supply_rms"):
   if absf(float(slow.lab.readings.external_supply_rms.get("PV_A",0))-float(fast.lab.readings.external_supply_rms.get("PV_A",0)))>1e-7:push_error("RMS mismatch at %d"%i);quit(1);return
 if fast.dc.linear_ac_cache.is_empty():push_error("Fast path was never enabled");quit(1);return
 # Connected DAQ voltage/current channels must follow the same RMS phasors.
 var measured_slow=make_case(false);var measured_fast=make_case(true)
 for item in [measured_slow,measured_fast]:
  item.links[0].b.port="DAQ_I0_4"
  item.lab.cables.append_array([{"a":"DAQ_I0_N","b":"PV_A"},{"a":"DAQ_E0_P","b":"PV_A"},{"a":"DAQ_E0_N","b":"PV_N"}])
 for i in 250:
  for item in [measured_slow,measured_fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if i>80:
   if measured_slow.lab.readings.daq_v[0].distance_to(measured_fast.lab.readings.daq_v[0])>1e-7:push_error("DAQ voltage mismatch at %d"%i);quit(1);return
   if measured_slow.lab.readings.daq_i[0].distance_to(measured_fast.lab.readings.daq_i[0])>1e-7:push_error("DAQ current mismatch at %d"%i);quit(1);return
 if measured_fast.dc.linear_ac_cache.is_empty() or not measured_fast.dc.linear_ac_cache.get("eligible",true):push_error("DAQ circuit did not use fast path");quit(1);return
 # Three-phase and low-power sources share frequency but have distinct phases.
 var phase_slow=make_case(false);var phase_fast=make_case(true)
 for item in [phase_slow,phase_fast]:
  item.links[0].b.port="P_A";item.links[1].b.port="P_B"
  item.lab.cables.append_array([{"a":"DAQ_E0_P","b":"P_A"},{"a":"DAQ_E0_N","b":"P_B"},{"a":"DAQ_E1_P","b":"LOW_0"},{"a":"DAQ_E1_N","b":"LOW_1"}])
 for i in 250:
  for item in [phase_slow,phase_fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if absf(float(phase_slow.dc.result.i["r0"])-float(phase_fast.dc.result.i["r0"]))>1e-7:push_error("Three-phase load mismatch at %d"%i);quit(1);return
  if i>80:
   for channel in 2:
    if phase_slow.lab.readings.daq_v[channel].distance_to(phase_fast.lab.readings.daq_v[channel])>1e-6:push_error("Three-phase DAQ mismatch at %d"%i);quit(1);return
 if phase_fast.dc.linear_ac_cache.is_empty() or not phase_fast.dc.linear_ac_cache.get("eligible",true):push_error("Three-phase circuit missed fast path");quit(1);return
 # The ideal transformer equations must agree with a fresh transient solve.
 var tx_slow=make_case(false);var tx_fast=make_case(true)
 for item in [tx_slow,tx_fast]:
  item.links[0].b.port="TX_3";item.links[1].b.port="TX_4"
  item.lab.cables.append_array([{"a":"TX_1","b":"PV_A"},{"a":"TX_2","b":"PV_N"}])
 for i in 200:
  for item in [tx_slow,tx_fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if not tx_slow.dc.result.ok or not tx_fast.dc.result.ok:push_error("Transformer solve failed");quit(1);return
  if absf(float(tx_slow.dc.result.i["r0"])-float(tx_fast.dc.result.i["r0"]))>1e-7:push_error("Transformer mismatch at %d"%i);quit(1);return
 if tx_fast.dc.linear_ac_cache.is_empty() or not tx_fast.dc.linear_ac_cache.get("eligible",true):push_error("Transformer missed fast path");quit(1);return
 # The per-frame plan produces the same samples and stops on a protection trip.
 var planned=make_case(true);var reference=make_case(false)
 Coupling.step([planned.dc,planned.ac],planned.links,.0005)
 Coupling.step([reference.dc,reference.ac],reference.links,.0005)
 var groups=Coupling.groups_for(2,planned.links)
 var plan=Coupling.linear_frame_plan([planned.dc,planned.ac],planned.links,groups,.0005)
 if plan.is_empty():push_error("Linear frame plan was not created");quit(1);return
 for i in 120:
  if not Coupling.linear_frame_step(plan,[planned.dc,planned.ac],.0005):push_error("Valid frame plan stopped");quit(1);return
  Coupling.step([reference.dc,reference.ac],reference.links,.0005)
  if absf(float(planned.dc.result.i["r0"])-float(reference.dc.result.i["r0"]))>1e-8:push_error("Frame plan mismatch at %d"%i);quit(1);return
 planned.dc.fuse=true
 if Coupling.linear_frame_step(plan,[planned.dc,planned.ac],.0005):push_error("Frame plan ignored meter fuse");quit(1);return
 planned.dc.fuse=false;planned.lab.powered=false
 if Coupling.linear_frame_step(plan,[planned.dc,planned.ac],.0005):push_error("Frame plan ignored source trip");quit(1);return
 # Linear inductor and capacitor state must match the full transient solver,
 # including topology edits, stored state, and reconnection.
 for item in [slow,fast]:
  item.lab.switches.L[0]=true
  item.lab.cables.append_array([{"a":"L0_P","b":"PV_A"},{"a":"L0_N","b":"PV_N"}])
 for i in 600:
  if i==120:
   for item in [slow,fast]:
    item.lab.switches.C[0]=true
    item.lab.cables.append_array([{"a":"C0_P","b":"PV_A"},{"a":"C0_N","b":"PV_N"}])
  if i==300:
   slow.lab.switches.L[0]=false;fast.lab.switches.L[0]=false
  if i==400:
   slow.lab.switches.L[0]=true;fast.lab.switches.L[0]=true
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if absf(float(slow.dc.result.i["r0"])-float(fast.dc.result.i["r0"]))>1e-7:push_error("RLC load mismatch at %d"%i);quit(1);return
  for id in ["L0_0","C0_0"]:
   if absf(float(slow.ac.result.i.get(id,0.0))-float(fast.ac.result.i.get(id,0.0)))>1e-7:push_error("RLC current mismatch at %d %s"%[i,id]);quit(1);return
   if absf(float(slow.ac.solver.memory.get(id,0.0))-float(fast.ac.solver.memory.get(id,0.0)))>1e-7:push_error("RLC state mismatch at %d %s"%[i,id]);quit(1);return
 if not fast.dc.linear_ac_cache.get("eligible",true) or fast.dc.linear_ac_cache.get("states",[]).size()!=2:push_error("Small RLC circuit did not use fast path");quit(1);return
 # A four-state network still matches; a seventh state uses the full solver.
 for item in [slow,fast]:
  item.lab.switches.L[1]=true;item.lab.switches.C[1]=true
 for i in 120:
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  for id in ["L0_0","L0_1","C0_0","C0_1"]:
   if absf(float(slow.ac.result.i.get(id,0.0))-float(fast.ac.result.i.get(id,0.0)))>1e-7:push_error("Four-state current mismatch %s"%id);quit(1);return
 if not fast.dc.linear_ac_cache.get("eligible",true) or fast.dc.linear_ac_cache.states.size()!=4:push_error("Four-state network missed fast path");quit(1);return
 # Repeated state transitions should not drift away from the transient solver.
 for i in 4000:
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if i%100==0:
   for id in ["L0_0","L0_1","C0_0","C0_1"]:
    if absf(float(slow.ac.solver.memory.get(id,0.0))-float(fast.ac.solver.memory.get(id,0.0)))>1e-6:push_error("Long-run RLC state drift %s at %d"%[id,i]);quit(1);return
 for item in [slow,fast]:
  item.lab.switches.L[2]=true;item.lab.switches.C[2]=true;item.lab.switches.L[3]=true
  item.lab.cables.append_array([{"a":"L1_P","b":"PV_A"},{"a":"L1_N","b":"PV_N"}])
 for i in 3:
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
 if fast.dc.linear_ac_cache.get("eligible",true):push_error("Large RLC circuit did not fall back");quit(1);return
 print("PASS: linear AC/RLC fast path matches full solver across edits and stored state; larger circuits fall back")
 quit()
