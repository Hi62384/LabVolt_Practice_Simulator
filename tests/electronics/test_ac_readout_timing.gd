extends SceneTree
const Lab=preload("res://scripts/lab_state.gd")
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
func _initialize() -> void:
 var lab=Lab.new();var bridge=Bridge.new(lab);lab.initialize(bridge.available_ports(),{})
 bridge.occupied_ports={"DAQ_E0_P":true,"DAQ_E0_N":true}
 var last:=-INF;var updates:=0;var maximum_gap:=0.0
 for i in 2001:
  var t:=i*.0005;bridge.sample_time=t
  bridge.result={"ok":true,"i":{},"v":{"DAQ_E0_P":sqrt(2.)*12.*cos(TAU*60.*t),"DAQ_E0_N":0.0}}
  bridge.finish_step()
  if bridge.last_readout_time>last:
   if is_finite(last):maximum_gap=maxf(maximum_gap,bridge.last_readout_time-last)
   last=bridge.last_readout_time;updates+=1
 if updates<38 or updates>41 or maximum_gap>.026:
  push_error("Unexpected instrument update cadence: %d updates, max gap %.5f"%[updates,maximum_gap]);quit(1);return
 if lab.readings.daq_v[0].distance_to(Vector2(12,0))>1e-6:
  push_error("DAQ phasor changed with readout scheduling");quit(1);return
 print("PASS: DAQ phasor remains accurate and readout updates at least every 26 ms of simulation");quit()
