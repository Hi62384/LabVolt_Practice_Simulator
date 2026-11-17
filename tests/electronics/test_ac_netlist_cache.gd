extends SceneTree
const Lab=preload("res://scripts/lab_state.gd")
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
func _initialize() -> void:
 var lab=Lab.new();var bridge=Bridge.new(lab);lab.initialize(bridge.available_ports(),{})
 lab.powered=true
 lab.cables.append_array([{"a":"LOW_0","b":"DAQ_E0_P"},{"a":"LOW_1","b":"DAQ_E0_N"},{"a":"P_A","b":"R0_P"},{"a":"P_N","b":"R0_N"}])
 lab.switches.R[0]=true
 for i in 60:
  bridge.solver.time=float(i)*.00113
  if i==10:lab.level=.19
  if i==20:lab.frequency=50.
  if i==30:lab.switches.R[1]=true
  if i==40:lab.daq_settings={"AO0":3.2,"DO0":true}
  if i==45:lab.cables.append({"a":"DAQ_AO0","b":"DAQ_AI0"})
  if i==50:lab.powered=false
  if i==55:lab.powered=true
  bridge.prepare_step(.0005)
  var cached: Array=bridge.netlist_active().duplicate(true)
  var fresh: Array=bridge._netlist(false)
  if cached.size()!=fresh.size():push_error("Netlist size differs at %d"%i);quit(1);return
  for j in cached.size():
   for key in fresh[j]:
    if key=="value":
     if absf(float(cached[j][key])-float(fresh[j][key]))>1e-10:push_error("Source mismatch at %d %s"%[i,fresh[j].id]);quit(1);return
    elif cached[j].get(key)!=fresh[j][key]:push_error("Part mismatch at %d %s"%[i,key]);quit(1);return
 print("PASS: cached AC netlist matches fresh topology and changing source waveforms")
 quit()

