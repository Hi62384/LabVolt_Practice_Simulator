extends SceneTree
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
func _initialize() -> void:
 for frequency in [20.0,50.0,60.0,120.0]:
  var window=[];var values=[]
  for i in 41:
   var t=float(i)*.00037+float(i%3)*.00002
   window.append({"time":t})
   values.append(3.5+24.0*cos(TAU*frequency*t+.63))
  var direct=Bridge.fit_signal(window,values,frequency)
  var context=Bridge.signal_fit_context(window,frequency)
  var shared=Bridge.fit_signal_with_context(context,values)
  if direct.ac.distance_to(shared.ac)>1e-9 or absf(direct.dc-shared.dc)>1e-9:push_error("Shared fit differs at %s Hz"%frequency);quit(1);return
  values.fill(4.5)
  direct=Bridge.fit_signal(window,values,frequency);shared=Bridge.fit_signal_with_context(context,values)
  if direct.ac!=shared.ac or absf(direct.dc-shared.dc)>1e-9:push_error("Constant fit differs");quit(1);return
 # Short, irregular and singular windows exercise the same pivot/failure path.
 for count in [3,8,100]:
  for frequency in [0.0,3.0,60.0,400.0]:
   var window=[];var values=[]
   for i in count:
    var t=float(i)*.00043+float(i%4)*.000013
    window.append({"time":t})
    values.append(1.25+3.0*cos(TAU*frequency*t+.31)+float(i%3)*.0001)
   var direct=Bridge.fit_signal(window,values,frequency)
   var shared=Bridge.fit_signal_with_context(Bridge.signal_fit_context(window,frequency),values)
   if direct.ac.distance_to(shared.ac)>1e-7 or absf(direct.dc-shared.dc)>1e-7:push_error("Shared fit differs with %d points at %s Hz"%[count,frequency]);quit(1);return
 print("PASS: shared DAQ fit matches independent fits for AC/DC and nonuniform samples")
 quit()
