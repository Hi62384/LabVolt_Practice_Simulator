extends "res://scripts/electronics_buses/group_scheduler.gd"
## Compose the chronological CPU barrier with commercial peripheral deadlines.
## All electrical work delegates to the existing shared station solver.
const Events=preload("res://scripts/commercial_devices/event_adapter.gd")
const BoardModel=preload("res://scripts/breadboard_model.gd")
const StationAdapter=preload("res://scripts/electronics_buses/station_adapter.gd")
var circuit_stations: Array=[]
var circuit_links: Array=[]
var elapsed_electrical := 0.
var settle_fault := ""
func set_context(stations: Array,links: Array) -> void:
 circuit_stations=stations;circuit_links=links
func begin(dt: float,voltages: Dictionary,running := true,now_controls := {}) -> bool:
 elapsed_electrical=0.;settle_fault=""
 return super.begin(dt,voltages,running,now_controls)
func configure(solve_callback: Callable,sample_callback: Callable) -> void:
 super.configure(func(next_states,dt):
  # A malformed/failed group reply must not replay already committed time.
  var safe_dt: float=minf(maxf(0.,float(dt)),maxf(0.,duration-elapsed_electrical))
  if dt>0. and safe_dt<=0.:return
  solve_callback.call(next_states,safe_dt)
  elapsed_electrical+=safe_dt
  _settle_peripherals()
 ,sample_callback)
func _settle_peripherals() -> void:
 for iteration in 8:
  var changed := false
  for station in circuit_stations:
   if station.board.is_empty():continue
   var expanded: Dictionary=BoardModel.expand(station.board,"board/",station.result.get("v",{}),station.firmware_states)
   var observed: Dictionary=Events.observe(expanded.parts,station.result,station.firmware_states)
   if observed.changed:
    station.firmware_states.merge(observed.updates,true);changed=true
  if not changed:return
  StationAdapter.solve(circuit_stations,circuit_links,0.)
 settle_fault="Peripheral outputs did not settle within eight same-time passes"
func inputs(voltages: Dictionary,now_controls: Dictionary) -> void:
 super.inputs(voltages,now_controls)
 var deadline := remaining
 for station in circuit_stations:
  if station.board.is_empty():continue
  var expanded: Dictionary=BoardModel.expand(station.board,"board/",station.result.get("v",{}),station.firmware_states)
  deadline=Events.next_delay(expanded.parts,station.firmware_states,deadline)
 if not queue.is_empty() and queue[-1].op=="group_tick":queue[-1].dt=deadline
func poll() -> Dictionary:
 var packet: Dictionary=super.poll()
 if not settle_fault.is_empty() and fault.is_empty():
  if packet.get("ready",false) and packet.get("consumed",false):
   fault=settle_fault;packet.ok=false;packet.error=settle_fault
   return packet
  return fail(settle_fault)
 return packet
func close() -> void:
 super.close()
 settle=Callable();sample=Callable()
 circuit_stations=[];circuit_links=[];elapsed_electrical=0.;settle_fault=""
