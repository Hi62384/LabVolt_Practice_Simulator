extends SceneTree
func _initialize():
 var lab=load("res://scripts/lab_state.gd").new()
 var bridge=load("res://scripts/ac_supply_bridge.gd").new(lab)
 lab.initialize(bridge.available_ports(),{})
 lab.powered=true
 lab.cables.append_array([
  {"a":"DAQ_E0_P","b":"P_N"},{"a":"DAQ_E0_N","b":"P_A"},
  {"a":"DAQ_E1_P","b":"P_A"},{"a":"DAQ_E1_N","b":"P_N"}])
 lab.recalculate()
 assert(lab.powered and lab.readings.fault.is_empty())
 var e1: Vector2=lab.readings.daq_v[0]
 var e2: Vector2=lab.readings.daq_v[1]
 assert(absf(e1.length()-120.0)<.01 and absf(e2.length()-120.0)<.01)
 assert(e1.x< -119.0 and absf(e1.y)<.01 and e2.x>119.0 and absf(e2.y)<.01)
 print("PASS E1 reversed polarity produces 180 degrees relative to E2")
 quit()
