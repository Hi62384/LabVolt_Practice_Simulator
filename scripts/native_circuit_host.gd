extends RefCounted
## Host-wide asynchronous electrical barrier. Clients never instantiate a CPU.
const Scheduler=preload("res://scripts/native_electrical_scheduler.gd")
const Board=preload("res://scripts/breadboard_model.gd")
var scheduler=Scheduler.new()
var signature := ""
var node_path := ""
var checked_dependency := false
var active := false
var records := {}
var fault := ""
func close() -> void:
 scheduler.close();signature="";records={};active=false
func refresh(stations: Array) -> void:
 var found := {};var keys: Array=[]
 for index in stations.size():
  var station=stations[index]
  if not station.get("board") is Dictionary or station.board.is_empty():continue
  if station.has_method("board_simulating") and not station.board_simulating():continue
  if station.has_method("_fixed_board_expansion") and not station._fixed_board_expansion().is_empty():continue
  for part in Board.expand(station.board,"board/",station.result.get("v",{}),station.firmware_states).parts:
   if part.kind!="native_controller":continue
   var id := "station%d/"%index+str(part.id)
   if part.program.is_empty():station.firmware_states[part.id]={"powered":false,"outputs":{},"status":"No compiled image · open Code"};continue
   keys.append(id+":"+str(station.board_epoch)+":"+JSON.stringify(part.program).sha256_text())
   found[id]={"station":index,"part":part}
 keys.sort();var next := "|".join(keys)
 if next==signature:
  records=found
  return
 scheduler.close();signature=next;records=found;active=not found.is_empty();fault=""
 if not active:return
 if not checked_dependency:
  checked_dependency=true;node_path=preload("res://scripts/firmware_backends/native_host_config.gd").executable()
 if node_path=="":fail(stations,"Native runtime is unavailable on this host");return
 for id in records:
  var record: Dictionary=records[id];var part: Dictionary=record.part
  var nodes: Array=part.nodes.map(func(n):return "station%d/"%record.station+str(n))
  if not scheduler.add(id,nodes,part.program,node_path,"",int(stations[int(record.station)].board_epoch)):fail(stations,scheduler.fault);return
func fail(stations: Array,message: String) -> void:
 fault=message;scheduler.close();active=false
 for record in records.values():stations[record.station].firmware_states[record.part.id]={"powered":false,"outputs":{},"status":message}
func advance(stations: Array,links: Array,dt: float,refresh_devices := true) -> bool:
 if refresh_devices:refresh(stations)
 if not active:return false
 scheduler.set_context(stations,links)
 preload("res://scripts/electronics_buses/station_adapter.gd").bind(scheduler,stations,links,records)
 if scheduler.waiting:
  var packet: Dictionary=scheduler.poll()
  if not packet.get("ready",false):return false
  if not packet.get("ok",false):fail(stations,str(packet.get("error","Native backend failed")));return bool(packet.get("consumed",false))
  for interval in packet.intervals:
   for id in interval.states:
    var record: Dictionary=records[id]
    stations[record.station].firmware_states[record.part.id]=interval.states[id]
   solve(stations,links,float(interval.dt))
  for id in packet.states:
   var record: Dictionary=records[id];stations[record.station].firmware_states[record.part.id]=packet.states[id]
  return true
 if not scheduler.ready():
  if scheduler.fault!="":fail(stations,scheduler.fault)
  return false
 var voltages := {};var controls := {}
 for index in stations.size():
  for pin in stations[index].result.get("v",{}):voltages["station%d/"%index+str(pin)]=stations[index].result.v[pin]
 for id in records:
  var record: Dictionary=records[id];var part: Dictionary=record.part;var station=stations[record.station]
  var zero := float(station.result.get("v",{}).get(part.nodes[1],0))
  var rail := float(station.result.get("v",{}).get(part.nodes[0],0))-zero
  var reset := float(station.result.get("v",{}).get(part.reset_node,0))-zero
  controls[id]=station.native_controls.get(part.id,{}).duplicate(true)
  if rail>1 and reset<rail*.3:controls[id].reset=true
  controls[id].aref=maxf(.01,float(station.result.get("v",{}).get(part.aref_node,rail+zero))-zero)
  station.native_controls.erase(part.id)
  scheduler.devices[id].running=bool(part.run)
 if not scheduler.begin(dt,voltages,true,controls):
  if scheduler.fault!="":fail(stations,scheduler.fault)
 return false
static func solve(stations: Array,links: Array,dt: float) -> void:
 if not links.is_empty():preload("res://scripts/dc_coupling.gd").step(stations,links,dt)
 else:
  for station in stations:
   if station.get("portable_slot")==true and not station.board_simulating():continue
   station.step(dt)
