extends SceneTree
const Lab=preload("res://scripts/lab_state.gd")
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
func _initialize() -> void:
 var lab=Lab.new();var bridge=Bridge.new(lab);lab.initialize(bridge.available_ports(),{})
 var clock:=0.0
 for sample in 500:
  if sample==240:lab.frequency=47.0
  if sample==360:bridge.samples.clear()
  clock+=.0003+float(sample%5)*.0001
  bridge.sample_time=clock
  var currents={"P_A":2.0*sin(clock*37.0)}
  if sample%11!=0:currents["PV_B"]=.3+cos(clock*21.0)
  bridge.result={"ok":true,"i":currents,"v":{}}
  bridge.finish_step()
  var samples: Array=bridge.samples
  if samples.size()<3 or clock-float(samples[0].time)<.95/lab.frequency:continue
  for port in currents:
   var energy:=0.0;var duration:=0.0
   for i in range(1,samples.size()):
    var dt: float=samples[i].time-samples[i-1].time
    var value: float=samples[i].currents.get(port,0.0)
    energy+=value*value*dt;duration+=dt
   var expected:=sqrt(energy/maxf(duration,.000001))
   var actual: float=lab.readings.external_supply_rms[port]
   if absf(expected-actual)>1e-8:
    push_error("Rolling RMS differs at sample %d for %s: %s vs %s"%[sample,port,actual,expected]);quit(1);return
 # Constant-current sources should trip only above each source's own limit.
 for source in [["P_A",15.0],["PV_A",5.0],["DC_7",8.0],["DC_8",2.0],["LOW_0",3.0]]:
  for factor in [0.99,1.01]:
   var protected_lab=Lab.new();var protected_bridge=Bridge.new(protected_lab)
   protected_lab.initialize(protected_bridge.available_ports(),{});protected_lab.powered=true
   for i in 50:
    protected_bridge.sample_time=float(i)*.0005
    protected_bridge.result={"ok":true,"i":{source[0]:float(source[1])*factor},"v":{}}
    protected_bridge.finish_step()
   if protected_bridge.breaker_tripped!=(factor>1.0):
    push_error("Incorrect protection threshold for %s at factor %.2f"%[source[0],factor]);quit(1);return
 print("PASS: rolling RMS and source protection match expected values")
 quit()
