extends RefCounted
## Thin integration with existing station/coupling solvers. No alternate numerical solver.
static func bind(scheduler: RefCounted,stations: Array,links: Array,records: Dictionary) -> void:
 scheduler.configure(func(states,dt):
  for id in states:
   if records.has(id):stations[int(records[id].station)].firmware_states[records[id].part.id]=states[id]
  solve(stations,links,dt)
  if dt==0.:
   # First solve propagates new GPIO voltages; following zero-time passes let
   # existing edge-driven slave models assert ACK/MISO and settle shared nets.
   solve(stations,links,0.);solve(stations,links,0.)
 ,func():
  var voltages := {};var controls := {}
  for index in stations.size():
   for pin in stations[index].result.get("v",{}):voltages["station%d/"%index+str(pin)]=stations[index].result.v[pin]
  for id in records:
   var record: Dictionary=records[id];var part: Dictionary=record.part;var station=stations[int(record.station)]
   var v: Dictionary=station.result.get("v",{});var zero := float(v.get(part.nodes[1],0));var rail := float(v.get(part.nodes[0],0))-zero
   controls[id]={"reset":rail>1. and float(v.get(part.reset_node,0))-zero<rail*.3,"aref":maxf(.01,float(v.get(part.aref_node,rail+zero))-zero)}
  return {"voltages":voltages,"controls":controls}
 )
static func solve(stations: Array,links: Array,dt: float) -> void:
 if not links.is_empty():preload("res://scripts/dc_coupling.gd").step(stations,links,dt)
 else:
  for station in stations:station.step(dt)
