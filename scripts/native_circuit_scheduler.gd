extends RefCounted
## Host-only native barrier. Electrical code consumes intervals only after all replies.
const Runtime=preload("res://scripts/firmware_backends/native_runtime.gd")
var devices := {}
var waiting := false
var duration := 0.
var previous := {}
var replies := {}
var fault := ""
func add(id: String,nodes: Array,program: Dictionary,node_path: String,backend_path := "") -> bool:
 if waiting or id.is_empty() or id.length()>256 or devices.has(id) or devices.size()>=8:return false
 var runtime=Runtime.new()
 if not runtime.load_program(node_path,program,backend_path):fault=str(runtime.state.status);runtime.close();return false
 if nodes.size()!=runtime.model.pins.size():runtime.close();return false
 devices[id]={"runtime":runtime,"nodes":nodes.duplicate(),"loaded":false}
 return true
func ready() -> bool:
 if waiting:return false
 var all_ready := true
 for entry in devices.values():
  if entry.loaded:continue
  var reply: Dictionary=entry.runtime.poll_step()
  if not reply.get("ready",false):all_ready=false;continue
  if not reply.get("ok",false):fault=str(reply.state.status);return false
  entry.loaded=true
 return all_ready
func begin(dt: float,voltages: Dictionary,running := true,controls := {}) -> bool:
 if not fault.is_empty() or not is_finite(dt) or dt<=0 or dt>.0005 or not ready():return false
 duration=dt;previous={};replies={}
 for id in devices:
  var entry: Dictionary=devices[id];previous[id]=entry.runtime.state.duplicate(true)
  if not entry.runtime.begin_step(entry.nodes,voltages,dt,bool(entry.get("running",running)),controls.get(id,{})):
   fault="Native request failed: "+id;close();return false
 waiting=true
 return true
func poll() -> Dictionary:
 if not waiting:return {"ready":false}
 for id in devices:
  if replies.has(id):continue
  var reply: Dictionary=devices[id].runtime.poll_step()
  if not reply.get("ready",false):continue
  if not reply.get("ok",false):fault=str(reply.state.status);close();return {"ready":true,"ok":false,"error":fault}
  replies[id]=reply.state.duplicate(true)
 if replies.size()!=devices.size():return {"ready":false}
 var edges: Array=[];var states := previous.duplicate(true)
 for id in replies:
  var final: Dictionary=replies[id]
  if not final.get("powered",false):states[id]=final.duplicate(true);continue
  states[id].powered=true
  var hz := 16000000. if final.get("board")=="uno" else 125000000.
  var start_cycles: float=float(previous[id].get("cycles",0))
  if float(final.get("cycles",0))<start_cycles:start_cycles=0.
  for event in final.get("events",[]):
   if event.get("type")!="gpio":continue
   var at := clampf((float(event.get("cycle",start_cycles))-start_cycles)/hz,0.,duration)
   edges.append({"order":edges.size(),"at":at,"id":id,"pin":str(event.get("pin","")),"state":int(event.get("state",2))})
 if edges.size()>2048:fault="Native electrical event budget exceeded";close();return {"ready":true,"ok":false,"error":fault}
 edges.sort_custom(func(a,b):return a.at<b.at or (a.at==b.at and a.order<b.order))
 var intervals: Array=[];var cursor := 0.
 for edge in edges:
  if edge.at>cursor:intervals.append({"dt":edge.at-cursor,"states":states.duplicate(true)});cursor=edge.at
  var state: Dictionary=states[edge.id]
  if not state.has("outputs"):state.outputs={}
  if not state.has("pulls"):state.pulls={}
  state.outputs.erase(edge.pin);state.pulls.erase(edge.pin)
  if edge.state in [0,1]:state.outputs[edge.pin]=edge.state
  elif edge.state in [3,4]:state.pulls[edge.pin]="up" if edge.state==3 else "down"
 if duration>cursor:intervals.append({"dt":duration-cursor,"states":states.duplicate(true)})
 waiting=false
 return {"ready":true,"ok":true,"intervals":intervals,"states":replies.duplicate(true),"duration":duration}
func close() -> void:
 for entry in devices.values():entry.runtime.close()
 devices.clear();waiting=false;previous={};replies={}
