extends RefCounted
## API-compatible core scheduler adapter. One host sidecar runs the same MCU engines
## conservatively by instruction time and yields to the shared solver at pin edges.
const Bridge=preload("res://scripts/firmware_backends/native_bridge.gd")
const Adapter=preload("res://scripts/firmware_backends/board_adapter.gd")
var bridge := Bridge.new()
var devices := {}
var waiting := false
var fault := ""
var queue: Array=[]
var started := false
var loaded := false
var in_flight := ""
var duration := 0.
var remaining := 0.
var states := {}
var controls := {}
var sample: Callable
var settle: Callable
var zero_edges := 0
var frame_serial := {}
var request_sequence := 0
var pending_sequence := -1
var pending_budget := -1.
var committed_time := 0.
var frame_open := false
var committing := false
var terminal_result := {}
const TIME_EPSILON := 1e-12
func configure(solve_callback: Callable,sample_callback: Callable) -> void:
 settle=solve_callback;sample=sample_callback
func add(id: String,nodes: Array,program: Dictionary,node_path: String,backend_path := "",epoch := 0) -> bool:
 if started or devices.has(id) or devices.size()>=8 or not Adapter.catalog().has(str(program.get("board",""))):return false
 var model: Dictionary=Adapter.catalog()[program.board]
 if nodes.size()!=model.pins.size():return false
 if devices.is_empty() and not bridge.start(node_path,backend_path):fault=bridge.last_error;return false
 devices[id]={"nodes":nodes.duplicate(),"program":program.duplicate(true),"epoch":epoch,"model":model,"running":true}
 states[id]={"powered":false,"outputs":{},"pulls":{},"cycles":0,"serial":[]}
 return true
func ready() -> bool:
 if not fault.is_empty() or waiting:return false
 if loaded:return true
 if not started:
  started=true;queue=[{"op":"group_begin"}]
  for id in devices:
   var command: Dictionary=devices[id].program.duplicate(true);command.op="load";command.device_id=id;command.board_epoch=int(devices[id].epoch);queue.append(command)
 var packet := pump()
 if not packet.is_empty() and not packet.get("ok",false):fault=str(packet.get("error","Group startup failed"));return false
 if queue.is_empty() and not bridge.pending:loaded=true
 return loaded
func pump() -> Dictionary:
 if bridge.pending:
  var reply := bridge.poll()
  if reply.is_empty():return {}
  if not reply.get("ok",false):return reply
  if in_flight=="group_tick":in_flight="";return reply
  in_flight=""
 if not queue.is_empty() and not bridge.pending:
  var command: Dictionary=queue.pop_front();in_flight=str(command.op)
  if in_flight=="group_tick":pending_sequence=int(command.tick_sequence);pending_budget=float(command.dt)
  if not bridge.request(command):return {"ok":false,"error":bridge.last_error}
 return {}
func inputs(voltages: Dictionary,now_controls: Dictionary) -> void:
 for id in devices:
  var entry: Dictionary=devices[id]
  var command := Adapter.tick_request(entry.model,entry.nodes,voltages,0.,bool(entry.running))
  command.erase("op");command.erase("dt")
  for key in ["reset","resume","step","breakpoints","uart_rx","aref"]:
   if now_controls.get(id,{}).has(key):command[key]=now_controls[id][key]
  queue.append({"op":"group_input","id":id,"epoch":int(entry.epoch),"input":command})
 request_sequence+=1
 queue.append({"op":"group_tick","dt":remaining,"tick_sequence":request_sequence})
func begin(dt: float,voltages: Dictionary,running := true,now_controls := {}) -> bool:
 if not loaded or waiting or not fault.is_empty() or not is_finite(dt) or dt<=0 or dt>.0005 or not sample.is_valid() or not settle.is_valid():return false
 duration=dt;remaining=dt;zero_edges=0;frame_open=true;terminal_result={};controls=now_controls.duplicate(true);frame_serial={}
 for id in devices:
  if not devices[id].has("running"):devices[id].running=running
  frame_serial[id]=[]
 inputs(voltages,controls);waiting=true
 return true
static func finite_number(value: Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value))
static func whole_number(value: Variant) -> bool:
 return finite_number(value) and float(value)>=0. and float(value)<=9007199254740991. and float(value)==floor(float(value))
func response_error(packet: Dictionary) -> String:
 if not packet.get("ok") is bool:return "Invalid native group acknowledgement"
 if not packet.ok:return str(packet.get("error","Native group failed"))
 if not packet.get("state") is Dictionary:return "Invalid native group snapshot"
 var result: Dictionary=packet.state
 if not whole_number(result.get("schema")) or int(result.schema)!=1:return "Invalid native group schema"
 if pending_sequence<1 or not whole_number(result.get("tick_sequence")) or int(result.tick_sequence)!=pending_sequence:return "Native group reply sequence mismatch"
 if not is_finite(pending_budget) or pending_budget<0. or pending_budget>.0005:return "Invalid native group request budget"
 if not result.get("devices") is Dictionary or result.devices.size()!=devices.size():return "Invalid native group device set"
 if not finite_number(result.get("elapsed")) or float(result.elapsed)<0. or float(result.elapsed)>minf(remaining,pending_budget)+TIME_EPSILON:return "Invalid native group time consumption"
 var elapsed := minf(remaining,float(result.elapsed)) # rounding only, after bounds validation
 if not finite_number(result.get("time")) or absf(float(result.time)-(committed_time+elapsed))>TIME_EPSILON:return "Native group clock mismatch"
 if not result.get("bus_barrier") is bool or (elapsed==0. and pending_budget>0. and not result.bus_barrier):return "Invalid native group zero-time barrier"
 for id in result.devices:
  if not devices.has(id) or not result.devices[id] is Dictionary:return "Invalid native group device identity"
  var state: Dictionary=result.devices[id]
  if not whole_number(state.get("group_epoch")) or int(state.group_epoch)!=int(devices[id].epoch):return "Native group epoch mismatch"
  if not state.get("powered") is bool or not whole_number(state.get("cycles")):return "Invalid native group device state"
  if not state.get("outputs") is Dictionary or not state.get("pulls") is Dictionary:return "Invalid native group pin state"
  var pins: Array=devices[id].model.pins.slice(2)
  for pin in state.outputs:
   if not pin is String or pin not in pins or not whole_number(state.outputs[pin]) or int(state.outputs[pin])>1:return "Invalid native group GPIO drive"
  for pin in state.pulls:
   if not pin is String or pin not in pins or state.pulls[pin] not in ["up","down"]:return "Invalid native group GPIO pull"
  if not state.get("events") is Array or not state.events.is_empty():return "Unexpected native group edge replay"
  if not state.get("serial") is Array or state.serial.size()>256:return "Invalid native group serial data"
  for byte in state.serial:
   if not byte is Dictionary or not whole_number(byte.get("port")) or int(byte.port)>(1 if devices[id].model.board=="pico" else 0) or not whole_number(byte.get("value")) or int(byte.value)>255:return "Invalid native group UART byte"
 return ""
func poll() -> Dictionary:
 if not waiting or committing:return {"ready":false}
 var packet := pump()
 if packet.is_empty():return {"ready":false}
 # Validate the complete reply before any electrical, serial, or pin-state commit.
 var invalid := response_error(packet)
 if not invalid.is_empty():return fail(invalid)
 var result: Dictionary=packet.state
 var elapsed := minf(remaining,float(result.elapsed))
 var next_zero_edges := zero_edges+1 if elapsed==0. else 0
 if next_zero_edges>1024:return fail("Native group zero-edge budget reached")
 var previous := states.duplicate(true)
 # Consume the accepted budget BEFORE callbacks, so even a callback fault cannot
 # settle an already committed partial interval for a second time.
 remaining=maxf(0.,remaining-elapsed);committed_time+=elapsed;pending_sequence=-1;pending_budget=-1.;zero_edges=next_zero_edges
 states=result.devices.duplicate(true)
 for id in states:
  frame_serial[id].append_array(states[id].serial)
  if frame_serial[id].size()>256:frame_serial[id]=frame_serial[id].slice(-256)
 committing=true
 if elapsed>0:settle.call(previous,elapsed)
 if frame_open:settle.call(states.duplicate(true),0.)
 committing=false
 if not frame_open:return terminal_result.duplicate(true)
 if remaining<=1e-13:
  # Close representational roundoff locally instead of dropping budget or asking
  # a remote clock to advance by less than its representable time increment.
  if remaining>0.:
   var roundoff := remaining;remaining=0.;committed_time+=roundoff
   committing=true;settle.call(states.duplicate(true),roundoff);committing=false
   if not frame_open:return terminal_result.duplicate(true)
  waiting=false;frame_open=false
  for id in states:states[id].serial=frame_serial[id]
  terminal_result={"ready":true,"ok":true,"intervals":[],"states":states.duplicate(true),"duration":duration,"consumed":true}
  return terminal_result.duplicate(true)
 var sampled_value=sample.call()
 if not sampled_value is Dictionary:return fail("Invalid native group electrical sample")
 var sampled: Dictionary=sampled_value
 if not sampled.get("voltages",sampled) is Dictionary or not sampled.get("controls",{}) is Dictionary:return fail("Invalid native group electrical sample")
 var latest_controls: Dictionary=sampled.get("controls",{})
 for id in latest_controls:
  if not devices.has(id) or not latest_controls[id] is Dictionary:return fail("Invalid native group sampled controls")
 # Resume/step/UART byte injection are one-shot. Host physical reset and AREF are
 # resampled from the actual circuit by the station adapter at every barrier.
 for id in devices:
  if not controls.has(id):controls[id]={}
  for key in ["resume","step","uart_rx"]:controls[id].erase(key)
  controls[id].merge(latest_controls.get(id,{}),true)
 inputs(sampled.get("voltages",sampled),controls)
 return {"ready":false}
func fail(message: String) -> Dictionary:
 if not frame_open:return {"ready":true,"ok":false,"error":message,"consumed":false,"duration":0.,"already_closed":true}
 fault=message;waiting=false;frame_open=false;pending_sequence=-1;pending_budget=-1.;queue=[];in_flight="";bridge.close()
 var unconsumed := remaining
 remaining=0.;committed_time+=unconsumed
 terminal_result={"ready":true,"ok":false,"error":message,"consumed":true,"duration":duration}
 # Revoke the frame and debit its remainder before invoking any callback.
 # Invalid/stale replies contribute no elapsed time or new device state.
 if settle.is_valid():
  for id in states:states[id].outputs={};states[id].pulls={};states[id].powered=false;states[id].status=message
  settle.call(states.duplicate(true),0.)
  if unconsumed>0:settle.call(states.duplicate(true),unconsumed)
 return terminal_result.duplicate(true)
func close() -> void:
 bridge.close();devices={};states={};queue=[];waiting=false;started=false;loaded=false;in_flight="";remaining=0.;duration=0.;fault="";request_sequence=0;pending_sequence=-1;pending_budget=-1.;committed_time=0.;frame_open=false;committing=false;terminal_result={};sample=Callable();settle=Callable()
